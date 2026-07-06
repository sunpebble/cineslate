import Foundation

/// Central configuration for TMDB + Plex.
enum AppConfig {
    // MARK: TMDB
    static let tmdbDefaultKey = "da82a300296f78b312c3ae9416dd71ce"
    static let tmdbBaseURL = "https://api.themoviedb.org/3"
    static let tmdbImageBase = "https://image.tmdb.org/t/p/"

    // MARK: Plex
    static let plexProduct = "Cineslate"
    static let plexVersion = "1.0"
    static let plexPinsURL = "https://plex.tv/api/v2/pins"
    static let plexAuthAppURL = "https://app.plex.tv/auth"
    static let plexResourcesURL = "https://plex.tv/api/v2/resources"
    static let plexUserURL = "https://plex.tv/api/v2/user"
    /// ASWebAuthenticationSession callback scheme (no Info.plist registration needed).
    static let plexCallbackScheme = "cineslate"
}
