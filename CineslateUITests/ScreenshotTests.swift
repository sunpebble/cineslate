import XCTest

/// Captures App Store screenshots headlessly and writes PNGs to the runner's
/// Documents container so the host can pull them via `simctl get_app_container`.
final class ScreenshotTests: XCTestCase {

    private func save(_ shot: XCUIScreenshot, _ name: String) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent(name)
        try? shot.pngRepresentation.write(to: url)
        let att = XCTAttachment(screenshot: shot); att.name = name; att.lifetime = .keepAlways; add(att)
    }

    func testCaptureScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en-US)", "-AppleLocale", "en_US"]
        app.launch()
        sleep(16)

        let screen = XCUIScreen.main
        save(screen.screenshot(), "cineslate-en-1-discover.png"); sleep(1)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.58)).tap()
        sleep(7)
        save(screen.screenshot(), "cineslate-en-2-detail.png")

        app.swipeUp(); sleep(3)
        save(screen.screenshot(), "cineslate-en-3-detail-more.png")
    }
}
