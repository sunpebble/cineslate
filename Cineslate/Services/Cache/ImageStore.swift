import UIKit
import CryptoKit

/// `NSCache` is documented thread-safe but isn't marked `Sendable`; this thin
/// wrapper lets the cache cross isolation boundaries cleanly (Swift 6 ready).
private final class MemoryImageCache: @unchecked Sendable {
    private let cache = NSCache<NSURL, UIImage>()

    init(countLimit: Int, totalCostLimit: Int) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    func object(for url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }
    func set(_ image: UIImage, for url: URL, cost: Int) {
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }
    func removeAll() { cache.removeAllObjects() }
}

/// Two-tier (memory + disk) image cache. Every TMDB image in the app flows
/// through here so posters/backdrops survive relaunch and render offline,
/// instead of relying on the tiny default `URLCache`.
///
/// - Memory: `NSCache` (thread-safe, auto-evicts under memory pressure), bounded
///   by a decoded-byte cost budget so a few `.original` backdrops can't blow up.
/// - Disk: raw image bytes under `Caches/CineslateImages/<sha256>`, pruned to a soft
///   byte budget with an approximate-LRU (oldest `mtime` first) policy.
/// - In-flight downloads of the same URL are coalesced.
///
/// All blocking disk I/O (reads, writes, trimming) runs OFF the actor — the
/// actor only coordinates the in-flight table, so a slow disk read or a
/// directory-wide trim never serializes other image lookups.
actor ImageStore {
    /// Injectable byte loader (defaults to `URLSession`) so tests avoid network.
    typealias Loader = @Sendable (URL) async -> Data?

    static let shared = ImageStore()

    private let memory: MemoryImageCache
    private let directory: URL
    private let maxDiskBytes: Int
    private let loader: Loader
    private let fileManager = FileManager.default

    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    /// Bytes written since the last trim; trimming is throttled to this budget so
    /// it doesn't run after every single download.
    private var pendingTrimBytes = 0
    private var isTrimming = false
    private static let trimThreshold = 16 * 1024 * 1024

    init(directoryName: String = "CineslateImages",
         maxDiskBytes: Int = 256 * 1024 * 1024,
         loader: @escaping Loader = ImageStore.networkLoader) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.maxDiskBytes = maxDiskBytes
        self.loader = loader
        memory = MemoryImageCache(countLimit: 250, totalCostLimit: 128 * 1024 * 1024)
    }

    // MARK: Public API

    /// Synchronous, lock-free memory peek. Lets SwiftUI show an already-cached
    /// image instantly (no flicker, no actor hop) while scrolling.
    nonisolated func memoryImage(for url: URL) -> UIImage? {
        memory.object(for: url)
    }

    /// Returns the image for `url`, checking memory → disk → network in order.
    /// Concurrent calls for the same URL share a single download. The disk/network
    /// work happens off the actor.
    func image(for url: URL) async -> UIImage? {
        if let hit = memory.object(for: url) { return hit }
        if let existing = inFlight[url] { return await existing.value }

        let task = Task.detached(priority: .utility) { [self] in await fetchOffActor(url) }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        return image
    }

    /// Drops every cached image from both tiers.
    func clear() {
        memory.removeAll()
        pendingTrimBytes = 0
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files { try? fileManager.removeItem(at: file) }
    }

    func diskUsageBytes() -> Int {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    /// Test seam: evicts only the memory tier, leaving disk intact.
    nonisolated func evictMemory() {
        memory.removeAll()
    }

    // MARK: Fetch pipeline (runs off the actor)

    private nonisolated func fetchOffActor(_ url: URL) async -> UIImage? {
        let fileURL = diskURL(for: url)
        if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
            memory.set(image, for: url, cost: cost(of: image))
            touch(fileURL)
            return image
        }
        guard let data = await loader(url), let image = UIImage(data: data) else { return nil }
        memory.set(image, for: url, cost: cost(of: image))
        try? data.write(to: fileURL, options: .atomic)
        await registerWrite(bytes: data.count)
        return image
    }

    /// Accounts for a fresh disk write and kicks off a throttled, off-actor trim.
    private func registerWrite(bytes: Int) {
        pendingTrimBytes += bytes
        guard pendingTrimBytes >= Self.trimThreshold, !isTrimming else { return }
        pendingTrimBytes = 0
        isTrimming = true
        Task.detached(priority: .utility) { [self] in
            trimDisk()
            await finishTrim()
        }
    }

    private func finishTrim() { isTrimming = false }

    // MARK: Disk helpers (nonisolated; never touch the actor's serial executor)

    private nonisolated func diskURL(for url: URL) -> URL {
        directory.appendingPathComponent(Self.hash(url.absoluteString))
    }

    private nonisolated func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    private nonisolated func cost(of image: UIImage) -> Int {
        if let cg = image.cgImage { return cg.bytesPerRow * cg.height }
        return Int(image.size.width * image.size.height * 4)
    }

    /// Evicts oldest-`mtime` files until the directory fits the byte budget.
    /// `nonisolated` so it can run on a background task without blocking lookups;
    /// `internal` so unit tests can drive it deterministically.
    nonisolated func trimDisk() {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys)) else { return }

        var infos: [(url: URL, date: Date, size: Int)] = files.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: keys),
                  let size = v.fileSize, let date = v.contentModificationDate else { return nil }
            return (url, date, size)
        }
        var total = infos.reduce(0) { $0 + $1.size }
        guard total > maxDiskBytes else { return }

        infos.sort { $0.date < $1.date }   // oldest first
        for info in infos {
            if total <= maxDiskBytes { break }
            try? fm.removeItem(at: info.url)
            total -= info.size
        }
    }

    // MARK: Loader

    static let networkLoader: Loader = { url in
        try? await sharedSession.data(from: url).0
    }

    private static let sharedSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = nil                                  // ImageStore IS the cache
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = 20
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }()

    static func hash(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
