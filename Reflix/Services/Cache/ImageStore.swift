import UIKit
import CryptoKit

/// Two-tier (memory + disk) image cache. Every TMDB image in the app flows
/// through here so posters/backdrops survive relaunch and render offline,
/// instead of relying on the tiny default `URLCache`.
///
/// - Memory: `NSCache` (thread-safe, auto-evicts under memory pressure).
/// - Disk: raw image bytes under `Caches/ReflixImages/<sha256>`, pruned to a
///   soft byte budget with an approximate-LRU (oldest `mtime` first) policy.
/// - In-flight downloads of the same URL are coalesced so a fast-scrolling list
///   never fires duplicate requests for the same poster.
actor ImageStore {
    /// Injectable byte loader (defaults to `URLSession`) so tests avoid network.
    typealias Loader = @Sendable (URL) async -> Data?

    static let shared = ImageStore()

    /// Lock-free, thread-safe — accessed from the synchronous `memoryImage`
    /// fast path as well as from inside the actor.
    nonisolated let memory: NSCache<NSURL, UIImage>

    private let directory: URL
    private let maxDiskBytes: Int
    private let loader: Loader
    private let fileManager = FileManager.default
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    init(directoryName: String = "ReflixImages",
         maxDiskBytes: Int = 256 * 1024 * 1024,
         loader: @escaping Loader = ImageStore.networkLoader) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.maxDiskBytes = maxDiskBytes
        self.loader = loader
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 250
        memory = cache
    }

    // MARK: Public API

    /// Synchronous, lock-free memory peek. Lets SwiftUI show an already-cached
    /// image instantly (no flicker, no actor hop) while scrolling.
    nonisolated func memoryImage(for url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }

    /// Returns the image for `url`, checking memory → disk → network in order.
    /// Concurrent calls for the same URL share a single download.
    func image(for url: URL) async -> UIImage? {
        if let hit = memory.object(forKey: url as NSURL) { return hit }
        if let existing = inFlight[url] { return await existing.value }

        let task = Task { await self.fetch(url) }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        return image
    }

    /// Drops every cached image from both tiers.
    func clear() {
        memory.removeAllObjects()
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files { try? fileManager.removeItem(at: file) }
    }

    func diskUsageBytes() -> Int {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    // MARK: Fetch pipeline

    private func fetch(_ url: URL) async -> UIImage? {
        let fileURL = diskURL(for: url)
        if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
            memory.setObject(image, forKey: url as NSURL)
            touch(fileURL)
            return image
        }
        guard let data = await loader(url), let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: url as NSURL)
        try? data.write(to: fileURL, options: .atomic)
        trimDisk()
        return image
    }

    // MARK: Disk helpers (actor-isolated; `internal` for unit tests)

    private func diskURL(for url: URL) -> URL {
        directory.appendingPathComponent(Self.hash(url.absoluteString))
    }

    private func touch(_ url: URL) {
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    /// Evicts oldest-`mtime` files until the directory fits the byte budget.
    func trimDisk() {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? fileManager.contentsOfDirectory(
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
            try? fileManager.removeItem(at: info.url)
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
