import XCTest
@testable import Reflix

/// Covers the studio-logo / genre-backdrop artwork added to the discover feed:
/// the `/network/{id}/images` decode and the cache snapshot's backward
/// compatibility with the new (optional) artwork fields.
final class DiscoverArtworkTests: XCTestCase {

    // MARK: Network logo decoding

    /// A `/network/{id}/images` payload decodes into `TMDBNetworkImages` and the
    /// first logo's `file_path` is what the studio card uses. `iso_639_1: null`
    /// must not break decoding (network logos are always language-neutral).
    func testNetworkImagesDecodesFirstLogoPath() throws {
        let json = Data(#"""
        {"id":213,"logos":[
          {"file_path":"/Ai3sZtq7afD07waB615luFR4GRZ.png","iso_639_1":null,"vote_average":5.3},
          {"file_path":"/second.png","iso_639_1":null,"vote_average":1.0}
        ]}
        """#.utf8)
        let images = try JSONDecoder().decode(TMDBNetworkImages.self, from: json)
        XCTAssertEqual(images.logos.first?.filePath, "/Ai3sZtq7afD07waB615luFR4GRZ.png")
    }

    /// A network with no logos decodes cleanly to an empty list (→ gradient
    /// fallback on the card, no crash).
    func testNetworkImagesWithoutLogos() throws {
        let json = Data(#"{"id":999,"logos":[]}"#.utf8)
        let images = try JSONDecoder().decode(TMDBNetworkImages.self, from: json)
        XCTAssertTrue(images.logos.isEmpty)
        XCTAssertNil(images.logos.first?.filePath)
    }

    // MARK: Snapshot backward compatibility

    /// A snapshot persisted before the artwork fields existed (no `studioLogos`
    /// / `genreBackdrops` keys) must still decode — otherwise every existing
    /// cache becomes a miss and the feed flashes empty on launch.
    func testLegacySnapshotDecodesWithoutArtworkFields() throws {
        let json = Data(#"{"heroes":[],"rankedTV":[],"trendingTV":[],"people":[]}"#.utf8)
        let snap = try JSONDecoder().decode(DiscoverSnapshot.self, from: json)
        XCTAssertNil(snap.studioLogos)
        XCTAssertNil(snap.genreBackdrops)
    }

    /// The `[Int: String]` artwork maps survive a JSON cache round-trip with
    /// their integer keys intact.
    func testSnapshotArtworkRoundTrips() throws {
        let snap = DiscoverSnapshot(heroes: [], rankedTV: [], trendingTV: [], people: [],
                                    studioLogos: [213: "/netflix.png", 453: "/hulu.png"],
                                    genreBackdrops: [18: "/drama.jpg"])
        let data = try JSONEncoder().encode(snap)
        let restored = try JSONDecoder().decode(DiscoverSnapshot.self, from: data)
        XCTAssertEqual(restored.studioLogos?[213], "/netflix.png")
        XCTAssertEqual(restored.studioLogos?[453], "/hulu.png")
        XCTAssertEqual(restored.genreBackdrops?[18], "/drama.jpg")
    }
}
