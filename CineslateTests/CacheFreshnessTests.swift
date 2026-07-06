import XCTest
@testable import Cineslate

/// The stale-while-revalidate freshness decision (`CacheEntry.isFresh`).
final class CacheFreshnessTests: XCTestCase {

    func testFreshWithinTTL() {
        let now = Date()
        let entry = CacheEntry(savedAt: now.addingTimeInterval(-60), payload: 1)
        XCTAssertTrue(entry.isFresh(ttl: 120, now: now))
    }

    func testStaleBeyondTTL() {
        let now = Date()
        let entry = CacheEntry(savedAt: now.addingTimeInterval(-300), payload: 1)
        XCTAssertFalse(entry.isFresh(ttl: 120, now: now))
    }

    func testBoundaryIsExclusive() {
        let now = Date()
        // age == ttl is treated as stale (strictly-less-than).
        let entry = CacheEntry(savedAt: now.addingTimeInterval(-120), payload: 1)
        XCTAssertFalse(entry.isFresh(ttl: 120, now: now))
    }

    func testAgeIsMonotonic() {
        let now = Date()
        let entry = CacheEntry(savedAt: now.addingTimeInterval(-90), payload: 1)
        XCTAssertEqual(entry.age(now: now), 90, accuracy: 0.001)
    }
}
