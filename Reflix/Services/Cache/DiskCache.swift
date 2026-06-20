import Foundation

/// One cached payload plus the wall-clock time it was written, so callers can
/// apply their own TTL / freshness policy on read.
struct CacheEntry<T: Codable>: Codable {
    let savedAt: Date
    let payload: T

    func age(now: Date = Date()) -> TimeInterval { now.timeIntervalSince(savedAt) }

    /// Pure freshness decision used by the stale-while-revalidate callers.
    /// `now` is injectable so it can be unit-tested deterministically.
    func isFresh(ttl: TimeInterval, now: Date = Date()) -> Bool {
        age(now: now) < ttl
    }
}

/// Soft TTLs for the stale-while-revalidate data caches.
enum CacheTTL {
    static let discover: TimeInterval = 10 * 60        // 发现页
    static let browse: TimeInterval = 30 * 60          // 分类/工作室浏览
    static let detail: TimeInterval = 24 * 60 * 60     // 详情页
}

/// Thread-safe (actor-isolated) JSON cache for arbitrary `Codable` snapshots.
/// Files live under `Caches/ReflixData/`, keyed by a filesystem-safe name.
actor DiskCache {
    static let shared = DiskCache()

    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileManager = FileManager.default

    init(directoryName: String = "ReflixData") {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func save<T: Codable>(_ key: String, _ value: T) {
        let entry = CacheEntry(savedAt: Date(), payload: value)
        guard let data = try? encoder.encode(entry) else { return }
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    func load<T: Codable>(_ key: String, as type: T.Type) -> CacheEntry<T>? {
        guard let data = try? Data(contentsOf: fileURL(for: key)) else { return nil }
        return try? decoder.decode(CacheEntry<T>.self, from: data)
    }

    func remove(_ key: String) {
        try? fileManager.removeItem(at: fileURL(for: key))
    }

    func clear() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files { try? fileManager.removeItem(at: file) }
    }

    func diskUsageBytes() -> Int {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { sum, url in
            sum + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent(Self.safeFileName(key) + ".json")
    }

    /// Maps an arbitrary cache key to a filesystem-safe file name.
    static func safeFileName(_ key: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let mapped = key.map { allowed.contains($0) ? $0 : "_" }
        let sanitized = String(mapped)
        return sanitized.isEmpty ? "_" : sanitized
    }
}
