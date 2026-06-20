import Foundation

/// Network errors surfaced to the UI.
enum TMDBError: LocalizedError {
    case badStatus(Int)
    case invalidKey

    var errorDescription: String? {
        switch self {
        case .invalidKey: return "TMDB API Key 无效"
        case .badStatus(let code): return "TMDB 请求失败（\(code)）"
        }
    }
}

/// All TMDB v3 calls used by the app.
final class TMDBService {
    static let shared = TMDBService()

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }()

    private let decoder: JSONDecoder = JSONDecoder()

    private func get<T: Decodable>(_ path: String,
                                   query: [URLQueryItem] = [],
                                   language: String? = "zh-CN") async throws -> T {
        var comps = URLComponents(string: AppConfig.tmdbBaseURL + path)!
        var items = query
        items.append(URLQueryItem(name: "api_key", value: KeyStore.tmdbKey))
        // Some endpoints (e.g. network logos) must NOT be language-filtered, so
        // `language: nil` skips the parameter entirely rather than narrowing.
        if let language { items.append(URLQueryItem(name: "language", value: language)) }
        items.append(URLQueryItem(name: "include_adult", value: "false"))
        comps.queryItems = items

        let (data, response) = try await session.data(from: comps.url!)
        guard let http = response as? HTTPURLResponse else { throw TMDBError.badStatus(-1) }
        if http.statusCode == 401 { throw TMDBError.invalidKey }
        guard (200..<300).contains(http.statusCode) else { throw TMDBError.badStatus(http.statusCode) }
        return try decoder.decode(T.self, from: data)
    }

    private func tag(_ list: [TMDBMedia], _ type: MediaType) -> [TMDBMedia] {
        list.map { var m = $0; m.forcedType = type; return m }
    }

    // MARK: Discover feed

    func trending(_ type: MediaType, window: String = "day") async throws -> [TMDBMedia] {
        let lang = type == .person ? "en-US" : "zh-CN"
        let r: TMDBPagedResponse<TMDBMedia> = try await get("/trending/\(type.rawValue)/\(window)", language: lang)
        return tag(r.results, type)
    }

    func popularTV() async throws -> [TMDBMedia] {
        let r: TMDBPagedResponse<TMDBMedia> = try await get("/tv/popular")
        return tag(r.results, .tv)
    }

    func popularMovies() async throws -> [TMDBMedia] {
        let r: TMDBPagedResponse<TMDBMedia> = try await get("/movie/popular")
        return tag(r.results, .movie)
    }

    // MARK: Browse

    func discover(type: MediaType, genre: Int? = nil, network: Int? = nil) async throws -> [TMDBMedia] {
        var q = [URLQueryItem(name: "sort_by", value: "popularity.desc")]
        if let genre { q.append(URLQueryItem(name: "with_genres", value: String(genre))) }
        if let network, type == .tv { q.append(URLQueryItem(name: "with_networks", value: String(network))) }
        let r: TMDBPagedResponse<TMDBMedia> = try await get("/discover/\(type.rawValue)", query: q)
        return tag(r.results, type)
    }

    /// First available logo path for a TMDB network (studio browse cards), or nil.
    ///
    /// No `language` filter: network logos carry `iso_639_1 == null`, so a
    /// language query would filter every one of them out.
    func networkLogoPath(_ networkId: Int) async throws -> String? {
        let r: TMDBNetworkImages = try await get("/network/\(networkId)/images", language: nil)
        return r.logos.first?.filePath
    }

    func search(_ query: String) async throws -> [TMDBMedia] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let q = [URLQueryItem(name: "query", value: query)]
        let r: TMDBPagedResponse<TMDBMedia> = try await get("/search/multi", query: q)
        return r.results.filter { $0.resolvedType != .person || $0.profilePath != nil }
    }

    // MARK: Detail

    func detail(_ ref: MediaRef) async throws -> TMDBDetail {
        let q = [
            URLQueryItem(name: "append_to_response", value: "credits,similar,images,external_ids"),
            URLQueryItem(name: "include_image_language", value: "en,null,zh"),
        ]
        return try await get("/\(ref.type.rawValue)/\(ref.id)", query: q)
    }
}
