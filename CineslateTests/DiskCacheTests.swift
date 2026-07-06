import XCTest
@testable import Cineslate

final class DiskCacheTests: XCTestCase {

    private func makeCache() -> DiskCache {
        DiskCache(directoryName: "CineslateDataTests-\(UUID().uuidString)")
    }

    func testSaveLoadRoundTrip() async {
        let cache = makeCache()
        await cache.save("k", ["a", "b", "c"])
        let entry = await cache.load("k", as: [String].self)
        XCTAssertEqual(entry?.payload, ["a", "b", "c"])
        await cache.clear()
    }

    func testMissReturnsNil() async {
        let cache = makeCache()
        let entry = await cache.load("absent", as: [String].self)
        XCTAssertNil(entry)
    }

    func testTypeMismatchReturnsNil() async {
        let cache = makeCache()
        await cache.save("k", ["a"])
        // Wrong payload type on the same key decodes to nil (treated as a miss).
        let entry = await cache.load("k", as: Int.self)
        XCTAssertNil(entry)
        await cache.clear()
    }

    func testRemoveAndClear() async {
        let cache = makeCache()
        await cache.save("k1", ["x"])
        await cache.save("k2", ["y"])
        await cache.remove("k1")
        let removed = await cache.load("k1", as: [String].self)
        XCTAssertNil(removed)
        let kept = await cache.load("k2", as: [String].self)
        XCTAssertNotNil(kept)
        await cache.clear()
        let afterClear = await cache.load("k2", as: [String].self)
        XCTAssertNil(afterClear)
    }

    func testDiskUsageGrowsWithSaves() async {
        let cache = makeCache()
        let empty = await cache.diskUsageBytes()
        XCTAssertEqual(empty, 0)
        await cache.save("k", Array(repeating: "payload", count: 50))
        let used = await cache.diskUsageBytes()
        XCTAssertGreaterThan(used, 0)
        await cache.clear()
    }

    func testSafeFileName() {
        XCTAssertEqual(DiskCache.safeFileName("detail-tv-42"), "detail-tv-42")
        XCTAssertEqual(DiskCache.safeFileName("browse-genre-18"), "browse-genre-18")
        XCTAssertEqual(DiskCache.safeFileName("a/b c:d"), "a_b_c_d")
        XCTAssertEqual(DiskCache.safeFileName(""), "_")
    }
}
