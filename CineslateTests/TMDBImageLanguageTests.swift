import XCTest
@testable import Cineslate

/// Artwork must follow the UI language: `include_image_language` is built from
/// the content language, and the title-logo pick ranks the preferred language
/// first (with English / language-neutral fallbacks) instead of hardcoding zh.
final class TMDBImageLanguageTests: XCTestCase {

    // MARK: include_image_language

    func testChineseUIRequestsChineseThenEnglishThenNeutralImages() {
        XCTAssertEqual(TMDBService.includeImageLanguages(for: "zh-CN"), "zh,en,null")
    }

    func testEnglishUIRequestsEnglishThenNeutralImages() {
        XCTAssertEqual(TMDBService.includeImageLanguages(for: "en-US"), "en,null")
    }

    func testImageLanguageDropsRegionSubtag() {
        XCTAssertEqual(TMDBService.imageLanguage(for: "zh-CN"), "zh")
        XCTAssertEqual(TMDBService.imageLanguage(for: "en-US"), "en")
    }

    // MARK: Title logo ranking

    /// Builds a TMDBDetail via decode (mirrors MediaCodingTests; no memberwise init).
    private func makeDetail(logos: [[String: Any]]) -> TMDBDetail {
        let dict: [String: Any] = [
            "id": 1,
            "images": ["backdrops": [], "logos": logos],
        ]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(TMDBDetail.self, from: data)
    }

    private let mixedLogos: [[String: Any]] = [
        ["file_path": "/en.png", "iso_639_1": "en", "vote_average": 9.0],
        ["file_path": "/zh.png", "iso_639_1": "zh", "vote_average": 1.0],
        ["file_path": "/neutral.png", "vote_average": 10.0],
        ["file_path": "/ja.png", "iso_639_1": "ja", "vote_average": 10.0],
    ]

    func testChinesePreferencePicksChineseLogoDespiteLowerVote() {
        let detail = makeDetail(logos: mixedLogos)
        XCTAssertEqual(detail.titleLogoPath(preferring: "zh"), "/zh.png")
    }

    func testEnglishPreferencePicksEnglishLogoOverChinese() {
        let detail = makeDetail(logos: mixedLogos)
        XCTAssertEqual(detail.titleLogoPath(preferring: "en"), "/en.png")
    }

    /// English UI with no English art must still prefer language-neutral art over
    /// any other foreign language — guards the collapsed single-tier English path.
    func testEnglishPreferenceFallsBackToNeutralOverForeign() {
        let noEn = mixedLogos.filter { ($0["iso_639_1"] as? String) != "en" }
        XCTAssertEqual(makeDetail(logos: noEn).titleLogoPath(preferring: "en"), "/neutral.png")
    }

    func testFallsBackToEnglishThenNeutralWhenPreferredMissing() {
        let noZh = mixedLogos.filter { ($0["iso_639_1"] as? String) != "zh" }
        XCTAssertEqual(makeDetail(logos: noZh).titleLogoPath(preferring: "zh"), "/en.png")

        let neutralOnly: [[String: Any]] = [
            ["file_path": "/neutral.png", "vote_average": 2.0],
            ["file_path": "/ja.png", "iso_639_1": "ja", "vote_average": 10.0],
        ]
        XCTAssertEqual(makeDetail(logos: neutralOnly).titleLogoPath(preferring: "zh"), "/neutral.png")
    }

    func testSameRankTieBrokenByHigherVote() {
        let logos: [[String: Any]] = [
            ["file_path": "/zh-low.png", "iso_639_1": "zh", "vote_average": 3.0],
            ["file_path": "/zh-high.png", "iso_639_1": "zh", "vote_average": 8.0],
        ]
        XCTAssertEqual(makeDetail(logos: logos).titleLogoPath(preferring: "zh"), "/zh-high.png")
    }

    func testNoLogosReturnsNilSoUIFallsBackToTextTitle() {
        XCTAssertNil(makeDetail(logos: []).titleLogoPath(preferring: "zh"))
    }
}
