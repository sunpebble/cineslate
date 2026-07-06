import Foundation

// MARK: - Config

/// OpenSubtitles REST credentials, persisted in the Keychain. Only `apiKey`
/// is required; username/password raise the daily download quota.
struct OpenSubtitlesConfig: Codable, Equatable {
    var apiKey: String
    var username: String?
    var password: String?

    var hasLogin: Bool {
        guard let username, let password else { return false }
        return !username.isEmpty && !password.isEmpty
    }
    var isUsable: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Identifies the credentials a cached token belongs to.
    var fingerprint: String { "\(apiKey)|\(username ?? "")|\(password ?? "")" }
}

// MARK: - Result item

/// One subtitle candidate from a search, ready to be presented + downloaded.
struct OpenSubtitleItem: Identifiable, Hashable {
    let id: String          // subtitle_id (stable for the row)
    let fileId: Int         // what /download needs
    let language: String    // e.g. "zh-CN"
    let release: String
    let downloads: Int
    let hd: Bool
    let hearingImpaired: Bool
    let aiTranslated: Bool

    var languageLabel: String { OpenSubtitlesService.languageLabel(language) }
}

// MARK: - Errors

enum OpenSubtitlesError: LocalizedError {
    case notConfigured
    case badStatus(Int, String?)
    case noLink
    case decodeFailed
    case quotaExceeded(String?)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return String(localized: "未配置 OpenSubtitles API Key（在设置中填写）")
        case .badStatus(let code, let msg): return msg ?? String(format: String(localized: "OpenSubtitles 请求失败（%lld）"), code)
        case .noLink: return String(localized: "未获取到字幕下载链接")
        case .decodeFailed: return String(localized: "字幕解析失败")
        case .quotaExceeded(let msg): return msg ?? String(localized: "今日字幕下载配额已用尽")
        }
    }
}

// MARK: - Service

/// Talks to the current OpenSubtitles REST API (api.opensubtitles.com/api/v1).
/// Search → pick a file_id → POST /download for a one-time link → fetch text.
actor OpenSubtitlesService {
    static let shared = OpenSubtitlesService()

    private let defaultHost = "api.opensubtitles.com"
    private var host: String
    private var token: String?
    private var tokenFingerprint: String?    // credentials the cached token belongs to

    private let userAgent = "Cineslate v\(AppConfig.plexVersion)"
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        return URLSession(configuration: cfg)
    }()

    init() { host = defaultHost }

    // MARK: Config persistence (Keychain)

    nonisolated static var isConfigured: Bool { loadConfig()?.isUsable ?? false }

    nonisolated static func loadConfig() -> OpenSubtitlesConfig? {
        guard let data = Keychain.load(account: Keychain.openSubtitlesAccount) else { return nil }
        return try? JSONDecoder().decode(OpenSubtitlesConfig.self, from: data)
    }

    nonisolated static func saveConfig(_ config: OpenSubtitlesConfig) {
        if let data = try? JSONEncoder().encode(config) {
            Keychain.save(data, account: Keychain.openSubtitlesAccount)
        }
        Task { await shared.resetSession() }
    }

    nonisolated static func clearConfig() {
        Keychain.clear(account: Keychain.openSubtitlesAccount)
        Task { await shared.resetSession() }
    }

    private func resetSession() {
        token = nil
        tokenFingerprint = nil
        host = defaultHost
    }

    /// Invalidates a cached token when the active config no longer matches the
    /// credentials that produced it (account switch, login removed, etc.).
    private func syncToken(for config: OpenSubtitlesConfig) {
        if tokenFingerprint != config.fingerprint {
            token = nil
            tokenFingerprint = nil
            host = defaultHost
        }
    }

    // MARK: Search

    /// Searches subtitles. Movies match best by `imdbId`/`tmdbId`; for shows we
    /// fall back to a title `query` since the detail page has no episode picker.
    func search(tmdbId: Int?, imdbId: String?, query: String?,
                isMovie: Bool, languages: [String]) async throws -> [OpenSubtitleItem] {
        let config = try requireConfig()
        syncToken(for: config)

        var items: [URLQueryItem] = [
            URLQueryItem(name: "languages", value: languages.joined(separator: ",")),
            URLQueryItem(name: "order_by", value: "download_count"),
            URLQueryItem(name: "order_direction", value: "desc"),
        ]
        items.append(URLQueryItem(name: "type", value: isMovie ? "movie" : "all"))
        if isMovie, let imdb = normalizedIMDB(imdbId) {
            items.append(URLQueryItem(name: "imdb_id", value: imdb))
        } else if isMovie, let tmdbId {
            items.append(URLQueryItem(name: "tmdb_id", value: String(tmdbId)))
        } else if let query, !query.isEmpty {
            items.append(URLQueryItem(name: "query", value: query))
        } else if let tmdbId {
            items.append(URLQueryItem(name: "tmdb_id", value: String(tmdbId)))
        }

        var comps = URLComponents(string: "https://\(host)/api/v1/subtitles")!
        comps.queryItems = items
        var req = URLRequest(url: comps.url!)
        applyHeaders(&req, config: config)

        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        guard let decoded = try? JSONDecoder().decode(OSSearchResponse.self, from: data) else {
            throw OpenSubtitlesError.decodeFailed
        }
        return decoded.data.compactMap { $0.toItem() }
    }

    // MARK: Download + parse

    /// POSTs /download for a one-time link, fetches it, and parses to cues.
    func downloadCues(fileId: Int) async throws -> [SubtitleCue] {
        let config = try requireConfig()
        syncToken(for: config)
        // Login (when credentials exist) may switch `host` to a VIP endpoint,
        // so build the download URL afterwards.
        if config.hasLogin { try await ensureLogin(config) }

        let comps = URLComponents(string: "https://\(host)/api/v1/download")!
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        applyHeaders(&req, config: config)
        req.httpBody = try JSONSerialization.data(withJSONObject: ["file_id": fileId, "sub_format": "srt"])

        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        guard let decoded = try? JSONDecoder().decode(OSDownloadResponse.self, from: data),
              let link = decoded.link, let linkURL = URL(string: link) else {
            throw OpenSubtitlesError.noLink
        }

        let (fileData, fileResponse) = try await session.data(from: linkURL)
        try validate(fileResponse, data: fileData)
        guard let text = decodeText(fileData) else { throw OpenSubtitlesError.decodeFailed }
        let cues = SubtitleParser.parse(text)
        guard !cues.isEmpty else { throw OpenSubtitlesError.decodeFailed }
        return cues
    }

    // MARK: Login (optional, for higher quota)

    private func ensureLogin(_ config: OpenSubtitlesConfig) async throws {
        guard token == nil, config.hasLogin,
              let username = config.username, let password = config.password else { return }

        var req = URLRequest(url: URL(string: "https://\(host)/api/v1/login")!)
        req.httpMethod = "POST"
        applyHeaders(&req, config: config)
        req.httpBody = try JSONSerialization.data(withJSONObject: ["username": username, "password": password])

        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        guard let decoded = try? JSONDecoder().decode(OSLoginResponse.self, from: data) else { return }
        token = decoded.token
        tokenFingerprint = config.fingerprint
        // The login response may pin the account to a VIP host.
        if let base = decoded.base_url, let baseHost = URL(string: base)?.host
            ?? URL(string: "https://\(base)")?.host {
            host = baseHost
        }
    }

    // MARK: Helpers

    private func requireConfig() throws -> OpenSubtitlesConfig {
        guard let config = Self.loadConfig(), config.isUsable else {
            throw OpenSubtitlesError.notConfigured
        }
        return config
    }

    private func applyHeaders(_ req: inout URLRequest, config: OpenSubtitlesConfig) {
        req.setValue(config.apiKey, forHTTPHeaderField: "Api-Key")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Only attach a bearer token for login-backed configs; a leftover token
        // must never ride along with an API-key-only config.
        if config.hasLogin, let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(OSErrorResponse.self, from: data))?.message
            if http.statusCode == 406 || http.statusCode == 429 {
                throw OpenSubtitlesError.quotaExceeded(message)
            }
            throw OpenSubtitlesError.badStatus(http.statusCode, message)
        }
    }

    /// IMDb ids on this API are bare digits (no `tt`, no leading zeros).
    private func normalizedIMDB(_ raw: String?) -> String? {
        guard var s = raw else { return nil }
        if s.hasPrefix("tt") { s.removeFirst(2) }
        while s.count > 1 && s.hasPrefix("0") { s.removeFirst() }
        return s.allSatisfy(\.isNumber) && !s.isEmpty ? s : nil
    }

    /// Subtitle files come in mixed encodings; try the common ones in order.
    private func decodeText(_ data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        for encoding in [String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))), .isoLatin1, .windowsCP1252] {
            if let s = String(data: data, encoding: encoding) { return s }
        }
        return nil
    }

    nonisolated static func languageLabel(_ code: String) -> String {
        switch code.lowercased() {
        case "zh-cn", "zh", "zh-hans": return String(localized: "简体中文")
        case "zh-tw", "zh-hk", "zh-hant": return String(localized: "繁體中文")
        case "en": return String(localized: "英语")
        case "ja": return String(localized: "日语")
        case "ko": return String(localized: "韩语")
        case "fr": return String(localized: "法语")
        case "de": return String(localized: "德语")
        case "es": return String(localized: "西班牙语")
        case "ru": return String(localized: "俄语")
        default: return code.uppercased()
        }
    }
}

// MARK: - Wire shapes

private struct OSSearchResponse: Decodable { let data: [OSSubtitle] }

private struct OSSubtitle: Decodable {
    let id: String?
    let attributes: OSAttributes?

    func toItem() -> OpenSubtitleItem? {
        guard let attributes, let fileId = attributes.files?.first(where: { $0.file_id != nil })?.file_id
        else { return nil }
        return OpenSubtitleItem(
            id: id ?? String(fileId),
            fileId: fileId,
            language: attributes.language ?? "—",
            release: attributes.release ?? "",
            downloads: attributes.download_count ?? 0,
            hd: attributes.hd ?? false,
            hearingImpaired: attributes.hearing_impaired ?? false,
            aiTranslated: (attributes.ai_translated ?? false) || (attributes.machine_translated ?? false)
        )
    }
}

private struct OSAttributes: Decodable {
    let language: String?
    let download_count: Int?
    let hd: Bool?
    let hearing_impaired: Bool?
    let ai_translated: Bool?
    let machine_translated: Bool?
    let release: String?
    let files: [OSFile]?
}

private struct OSFile: Decodable { let file_id: Int? }
private struct OSDownloadResponse: Decodable { let link: String?; let remaining: Int? }
private struct OSLoginResponse: Decodable { let token: String?; let base_url: String? }
private struct OSErrorResponse: Decodable {
    let message: String?
    let errors: [String]?
    enum CodingKeys: String, CodingKey { case message, errors }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        errors = try? c.decode([String].self, forKey: .errors)
        if let m = try? c.decode(String.self, forKey: .message) {
            message = m
        } else {
            message = errors?.joined(separator: "; ")
        }
    }
}
