import XCTest
import UIKit
@testable import Reflix

/// Counts loader invocations across concurrent calls.
private actor CallCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

final class ImageStoreTests: XCTestCase {

    /// A real, decodable 1×1 PNG (~70 bytes) so `UIImage(data:)` succeeds.
    private static let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!

    private func makeStore(maxDiskBytes: Int = 10_000_000,
                           counter: CallCounter? = nil) -> ImageStore {
        ImageStore(directoryName: "ReflixImagesTests-\(UUID().uuidString)",
                   maxDiskBytes: maxDiskBytes) { _ in
            if let counter { await counter.increment() }
            return ImageStoreTests.onePixelPNG
        }
    }

    func testReturnsDecodedImage() async {
        let store = makeStore()
        let url = URL(string: "https://example.com/a.png")!
        let image = await store.image(for: url)
        XCTAssertNotNil(image)
        await store.clear()
    }

    func testDeduplicatesConcurrentLoads() async {
        let counter = CallCounter()
        let url = URL(string: "https://example.com/dedup.png")!
        let store = ImageStore(directoryName: "ReflixImagesTests-\(UUID().uuidString)",
                               maxDiskBytes: 10_000_000) { _ in
            await counter.increment()
            try? await Task.sleep(nanoseconds: 50_000_000)   // hold so others coalesce
            return ImageStoreTests.onePixelPNG
        }
        async let a = store.image(for: url)
        async let b = store.image(for: url)
        async let c = store.image(for: url)
        _ = await (a, b, c)
        let calls = await counter.value
        XCTAssertEqual(calls, 1, "concurrent loads of the same URL must share one download")
        await store.clear()
    }

    func testDiskHitRefillsMemoryWithoutReloading() async {
        let counter = CallCounter()
        let store = makeStore(counter: counter)
        let url = URL(string: "https://example.com/disk.png")!

        _ = await store.image(for: url)        // network → disk + memory
        store.memory.removeAllObjects()         // evict memory tier only
        XCTAssertNil(store.memoryImage(for: url))

        _ = await store.image(for: url)        // should hit DISK, not loader
        let calls = await counter.value
        XCTAssertEqual(calls, 1, "second fetch must come from disk")
        XCTAssertNotNil(store.memoryImage(for: url), "disk hit should refill memory")
        await store.clear()
    }

    func testTrimEvictsOldestToFitBudget() async {
        // Budget fits ~1 file; writing 3 must trigger LRU eviction.
        let store = makeStore(maxDiskBytes: 100)
        for i in 0..<3 {
            _ = await store.image(for: URL(string: "https://example.com/\(i).png")!)
            try? await Task.sleep(nanoseconds: 12_000_000)   // distinct mtime ordering
        }
        let usage = await store.diskUsageBytes()
        XCTAssertLessThanOrEqual(usage, 100, "disk cache must stay within its byte budget")
        await store.clear()
    }
}
