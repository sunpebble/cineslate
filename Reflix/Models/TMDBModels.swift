import Foundation

enum MediaType: String, Codable, Hashable {
    case movie, tv, person
}

/// A lightweight, type-erased reference used for navigation into the detail page.
struct MediaRef: Hashable, Identifiable {
    let id: Int
    let type: MediaType
}

struct TMDBPagedResponse<T: Codable>: Codable {
    let results: [T]
}

/// One media row from trending / search / discover endpoints.
struct TMDBMedia: Codable, Identifiable, Hashable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let profilePath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let mediaTypeRaw: String?
    let genreIds: [Int]?

    /// Filled in from the calling endpoint when TMDB omits `media_type`.
    /// Not in `CodingKeys`, so it is neither decoded from TMDB nor persisted to
    /// the cache — `resolvedType`'s inference covers every cached endpoint.
    var forcedType: MediaType?

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case profilePath = "profile_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case mediaTypeRaw = "media_type"
        case genreIds = "genre_ids"
    }

    var displayTitle: String { title ?? name ?? "" }

    var year: String? {
        let raw = releaseDate ?? firstAirDate
        guard let raw, raw.count >= 4 else { return nil }
        return String(raw.prefix(4))
    }

    var resolvedType: MediaType {
        if let forcedType { return forcedType }
        if let mediaTypeRaw, let t = MediaType(rawValue: mediaTypeRaw) { return t }
        if profilePath != nil { return .person }
        if firstAirDate != nil { return .tv }
        return .movie
    }

    var ref: MediaRef { MediaRef(id: id, type: resolvedType) }
}

// MARK: - Detail

struct TMDBGenre: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
}

struct TMDBCastMember: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let character: String?
    let profilePath: String?

    enum CodingKeys: String, CodingKey {
        case id, name, character
        case profilePath = "profile_path"
    }
}

struct TMDBCredits: Codable, Hashable {
    let cast: [TMDBCastMember]
}

struct TMDBImage: Codable, Hashable {
    let filePath: String
    enum CodingKeys: String, CodingKey { case filePath = "file_path" }
}

struct TMDBImages: Codable, Hashable {
    let backdrops: [TMDBImage]
}

struct TMDBDetail: Codable, Identifiable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let runtime: Int?
    let episodeRunTime: [Int]?
    let numberOfSeasons: Int?
    let numberOfEpisodes: Int?
    let voteAverage: Double?
    let genres: [TMDBGenre]?
    let tagline: String?
    let credits: TMDBCredits?
    let similar: TMDBPagedResponse<TMDBMedia>?
    let images: TMDBImages?

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview, runtime, genres, tagline, credits, similar, images
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case episodeRunTime = "episode_run_time"
        case numberOfSeasons = "number_of_seasons"
        case numberOfEpisodes = "number_of_episodes"
        case voteAverage = "vote_average"
    }

    var displayTitle: String { title ?? name ?? "" }

    var year: String? {
        let raw = releaseDate ?? firstAirDate
        guard let raw, raw.count >= 4 else { return nil }
        return String(raw.prefix(4))
    }

    var runtimeMinutes: Int? {
        if let runtime, runtime > 0 { return runtime }
        if let first = episodeRunTime?.first, first > 0 { return first }
        return nil
    }

    /// e.g. "2025, 2 小时 30 分钟, 剧情, 惊悚"
    func metaLine(type: MediaType) -> String {
        var parts: [String] = []
        if let year { parts.append(year) }
        if let mins = runtimeMinutes {
            if type == .tv {
                parts.append("单集 \(mins) 分钟")
            } else {
                let h = mins / 60, m = mins % 60
                parts.append(h > 0 ? "\(h) 小时 \(m) 分钟" : "\(m) 分钟")
            }
        } else if type == .tv, let seasons = numberOfSeasons {
            parts.append("共 \(seasons) 季")
        }
        let genreNames = (genres ?? []).prefix(2).map(\.name)
        parts.append(contentsOf: genreNames)
        return parts.joined(separator: ", ")
    }
}

// MARK: - Image URL helper

enum TMDBImageSize: String {
    case w185, w342, w500, w780, original
}

func tmdbImageURL(_ path: String?, _ size: TMDBImageSize) -> URL? {
    guard let path, !path.isEmpty else { return nil }
    return URL(string: AppConfig.tmdbImageBase + size.rawValue + path)
}
