import Foundation

/// Central configuration for TMDB + Supabase.
enum AppConfig {
    // MARK: TMDB
    static let tmdbDefaultKey = "da82a300296f78b312c3ae9416dd71ce"
    static let tmdbBaseURL = "https://api.themoviedb.org/3"
    static let tmdbImageBase = "https://image.tmdb.org/t/p/"

    // MARK: Supabase
    static let supabaseURL = "https://vxaevdehoeuookaqhbjn.supabase.co"
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ4YWV2ZGVob2V1b29rYXFoYmpuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE4NzM4MjgsImV4cCI6MjA5NzQ0OTgyOH0.1Mu_Tcd69s7rGLCwLo9M0iOQ0uKIwuMqihSCQ_5h63I"

    static var supabaseRestURL: String { supabaseURL + "/rest/v1" }
    static var supabaseAuthURL: String { supabaseURL + "/auth/v1" }
    static var supabaseFunctionsURL: String { supabaseURL + "/functions/v1" }

    // MARK: Plex
    static let plexProduct = "Reflix"
    static let plexVersion = "1.0"
    static let plexPinsURL = "https://plex.tv/api/v2/pins"
    static let plexAuthAppURL = "https://app.plex.tv/auth"
    static let plexResourcesURL = "https://plex.tv/api/v2/resources"
    static let plexUserURL = "https://plex.tv/api/v2/user"
    /// ASWebAuthenticationSession callback scheme (no Info.plist registration needed).
    static let plexCallbackScheme = "reflix"
}
