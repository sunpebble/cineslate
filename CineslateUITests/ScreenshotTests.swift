import XCTest

/// Captures App Store screenshots headlessly and writes PNGs to the runner's
/// Documents container so the host can pull them via `simctl get_app_container`.
final class ScreenshotTests: XCTestCase {

    private func save(_ shot: XCUIScreenshot, _ name: String) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent(name)
        try? shot.pngRepresentation.write(to: url)
        let att = XCTAttachment(screenshot: shot)
        att.name = name
        att.lifetime = .keepAlways
        add(att)
    }

    func testCaptureScreenshots() throws {
        let app = XCUIApplication()
        app.launch()
        // Wait for TMDB content (trending/hero) on first launch.
        sleep(16)

        let screen = XCUIScreen.main

        // 1. Discover (hero + trending grid).
        save(screen.screenshot(), "cineslate-1-discover.png")
        sleep(1)

        // 2. Open a media detail from the grid.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.58)).tap()
        sleep(7)
        save(screen.screenshot(), "cineslate-2-detail.png")

        // 3. Scroll the detail to reveal cast / similar.
        app.swipeUp()
        sleep(3)
        save(screen.screenshot(), "cineslate-3-detail-more.png")
    }
}
