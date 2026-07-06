import XCTest
@testable import Cineslate

/// TMDBMedia must keep its resolved type across a cache (JSON) round-trip even
/// when the type can't be re-inferred from the remaining fields — otherwise a
/// cached TV item with a null first_air_date decodes back as a movie and
/// navigation opens the wrong endpoint.
final class MediaCodingTests: XCTestCase {

    private func roundTrip(_ media: TMDBMedia) throws -> TMDBMedia {
        let data = try JSONEncoder().encode(media)
        return try JSONDecoder().decode(TMDBMedia.self, from: data)
    }

    /// Builds a TMDBMedia via decode (there is no public memberwise init).
    private func makeMedia(firstAirDate: String? = nil, mediaTypeRaw: String? = nil) -> TMDBMedia {
        var dict: [String: Any] = ["id": 42, "name": "X"]
        if let firstAirDate { dict["first_air_date"] = firstAirDate }
        if let mediaTypeRaw { dict["media_type"] = mediaTypeRaw }
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(TMDBMedia.self, from: data)
    }

    func testForcedTVTypeSurvivesRoundTripWithoutFirstAirDate() throws {
        var media = makeMedia(firstAirDate: nil, mediaTypeRaw: nil)
        media.forcedType = .tv          // tagged from /tv/popular, no media_type field
        let restored = try roundTrip(media)
        XCTAssertEqual(restored.resolvedType, .tv)
    }

    func testForcedMovieTypeSurvives() throws {
        var media = makeMedia(firstAirDate: nil, mediaTypeRaw: nil)
        media.forcedType = .movie
        let restored = try roundTrip(media)
        XCTAssertEqual(restored.resolvedType, .movie)
    }

    func testInferredTypeFromMediaTypeRawSurvives() throws {
        // No forcedType but media_type present (trending feed) → resolved type persisted.
        let media = makeMedia(firstAirDate: nil, mediaTypeRaw: "tv")
        let restored = try roundTrip(media)
        XCTAssertEqual(restored.resolvedType, .tv)
    }

    func testLiveTMDBDecodeHasNoForcedType() throws {
        // A raw TMDB payload (no rfx_resolved_type key) must not gain a forcedType.
        let json = Data(#"{"id":1,"name":"Show","first_air_date":"2024-01-01"}"#.utf8)
        let media = try JSONDecoder().decode(TMDBMedia.self, from: json)
        XCTAssertNil(media.forcedType)
        XCTAssertEqual(media.resolvedType, .tv)   // inferred from first_air_date
    }
}
