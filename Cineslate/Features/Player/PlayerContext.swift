import Foundation

/// Everything the player needs: a resolvable Plex source plus the TMDB
/// identifiers used to look up subtitles.
struct PlayerContext: Identifiable, Hashable {
    let id = UUID()
    let match: PlexMatch
    let tmdbId: Int
    let imdbId: String?
    let title: String
    let year: String?
    let mediaType: MediaType
}
