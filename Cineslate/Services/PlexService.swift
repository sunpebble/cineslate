import Foundation
import SwiftUI

/// Stateless Plex HTTP: discover servers, match a TMDB title in a library,
/// and build a "open in Plex" deep link.
struct PlexService {
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 8
        return URLSession(configuration: cfg)
    }()

    // MARK: Servers

    func loadServers(token: String) async -> [PlexServer] {
        var comps = URLComponents(string: AppConfig.plexResourcesURL)!
        comps.queryItems = [
            URLQueryItem(name: "includeHttps", value: "1"),
            URLQueryItem(name: "includeRelay", value: "1"),
        ]
        var req = URLRequest(url: comps.url!)
        PlexAuth.headers(token: token).forEach { req.setValue($1, forHTTPHeaderField: $0) }

        guard let (data, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let resources = try? JSONDecoder().decode([PlexResource].self, from: data)
        else { return [] }

        return resources.filter(\.isServer).compactMap { res in
            let connections = res.connections ?? []
            let uris = orderedURIs(connections)
            guard !uris.isEmpty else { return nil }
            let relayURIs = Set(connections.filter { $0.relay == true }.compactMap { URL(string: $0.uri) })
            return PlexServer(
                name: res.name,
                machineIdentifier: res.clientIdentifier,
                accessToken: res.accessToken ?? token,
                connectionURIs: uris,
                relayURIs: relayURIs
            )
        }
    }

    private func orderedURIs(_ connections: [PlexConnection]) -> [URL] {
        func rank(_ c: PlexConnection) -> Int {
            if c.local == true { return 0 }          // LAN first
            if c.relay != true { return 1 }          // direct public
            return 2                                  // relay last
        }
        return connections
            .sorted { rank($0) < rank($1) }
            .compactMap { URL(string: $0.uri) }
    }

    // MARK: Matching

    func findMatch(server: PlexServer, ref: MediaRef, title: String, year: String?) async -> PlexMetadata? {
        let type = ref.type == .movie ? "1" : "2"

        for base in server.connectionURIs {
            // First reachable connection wins; query it by GUID, then by title.
            guard let byGuid = await query(base: base, token: server.accessToken, path: "/library/all",
                                           items: [URLQueryItem(name: "guid", value: "tmdb://\(ref.id)"),
                                                   URLQueryItem(name: "type", value: type)])
            else { continue }  // unreachable → try next connection

            if let hit = byGuid.first(where: { $0.matchesTMDB(ref.id) }) ?? byGuid.first {
                return hit
            }
            if let byTitle = await query(base: base, token: server.accessToken, path: "/library/all",
                                         items: [URLQueryItem(name: "title", value: title),
                                                 URLQueryItem(name: "type", value: type)]),
               let hit = matchByTitle(byTitle, title: title, year: year) {
                return hit
            }
            return nil  // server reachable, no match here
        }
        return nil
    }

    private func query(base: URL, token: String, path: String, items: [URLQueryItem]) async -> [PlexMetadata]? {
        var comps = URLComponents(url: base.appendingPathComponent(path.trimmingCharacters(in: ["/"])),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = items
        var req = URLRequest(url: comps.url!)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        PlexAuth.headers(token: token).forEach { req.setValue($1, forHTTPHeaderField: $0) }

        guard let (data, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }  // unreachable / error
        let container = try? JSONDecoder().decode(PlexMediaContainerResponse.self, from: data)
        return container?.mediaContainer.metadata ?? []
    }

    private func matchByTitle(_ items: [PlexMetadata], title: String, year: String?) -> PlexMetadata? {
        func norm(_ s: String) -> String {
            s.lowercased().filter { !$0.isWhitespace }
        }
        let target = norm(title)
        let yearInt = year.flatMap(Int.init)
        let exact = items.filter { norm($0.title ?? "") == target }
        if let yearInt, let hit = exact.first(where: { $0.year == yearInt }) { return hit }
        if let hit = exact.first { return hit }
        return items.first { norm($0.title ?? "").contains(target) || target.contains(norm($0.title ?? "")) }
    }

    // MARK: Deep link

    func deepLink(machineID: String, ratingKey: String) -> URL {
        let key = "/library/metadata/\(ratingKey)"
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ratingKey
        return URL(string: "https://app.plex.tv/desktop/#!/server/\(machineID)/details?key=\(key)")!
    }

    // MARK: Playback

    private static let directContainers: Set<String> = ["mp4", "m4v", "mov"]
    private static let directVideoCodecs: Set<String> = ["h264", "hevc"]
    private static let directAudioCodecs: Set<String> = ["aac"]

    /// Resolves a stream URL for `ratingKey`: direct play when AVPlayer can
    /// handle the file as-is, otherwise an HLS transcode session.
    func fetchPlayable(server: PlexServer, ratingKey: String) async -> PlexPlayable? {
        for base in server.connectionURIs {
            // A show/season ratingKey carries no media of its own — drill down to
            // the first episode. Movies/episodes resolve to themselves.
            guard let meta = await resolvePlayableMetadata(base: base, token: server.accessToken, ratingKey: ratingKey),
                  let playKey = meta.ratingKey,
                  let media = meta.media?.first,
                  let part = media.parts?.first
            else { continue }  // unreachable / no playable media → next connection

            let title = meta.title ?? String(localized: "正在播放")
            let durationMs = part.duration ?? media.duration ?? meta.duration
            let duration = durationMs.map { Double($0) / 1000 }

            // Relay connections throttle bandwidth and only proxy transcode
            // streams, so never serve a raw-file direct link over them.
            let isRelay = server.relayURIs.contains(base)
            if canDirectPlay(media), !isRelay, let key = part.key,
               let url = directURL(base: base, key: key, token: server.accessToken) {
                return PlexPlayable(url: url, isTranscoded: false, title: title,
                                    durationSeconds: duration, base: base,
                                    token: server.accessToken, session: nil)
            }

            let session = UUID().uuidString
            let url = transcodeURL(base: base, ratingKey: playKey, token: server.accessToken,
                                   session: session, resolution: media.pixelResolution,
                                   maxBitrate: media.bitrate)
            return PlexPlayable(url: url, isTranscoded: true, title: title,
                                durationSeconds: duration, base: base,
                                token: server.accessToken, session: session)
        }
        return nil
    }

    /// Walks a ratingKey down to a concrete, playable item. A movie or episode
    /// already carries Media/Part and resolves to itself; a show resolves to its
    /// first season's first episode, a season to its first episode.
    private func resolvePlayableMetadata(base: URL, token: String,
                                         ratingKey: String, depth: Int = 0) async -> PlexMetadata? {
        guard let meta = await fetchMetadata(base: base, token: token, ratingKey: ratingKey) else { return nil }
        if meta.media?.first?.parts?.first != nil { return meta }   // already playable
        guard depth < 3,                                            // show → season → episode
              let children = await fetchChildren(base: base, token: token, ratingKey: ratingKey),
              let next = firstPlayableChild(children)?.ratingKey
        else { return nil }
        return await resolvePlayableMetadata(base: base, token: token, ratingKey: next, depth: depth + 1)
    }

    /// Children of a container: a show's seasons, or a season's episodes.
    private func fetchChildren(base: URL, token: String, ratingKey: String) async -> [PlexMetadata]? {
        guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        comps.path = "/library/metadata/\(ratingKey)/children"
        guard let url = comps.url else { return nil }

        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        PlexAuth.headers(token: token).forEach { req.setValue($1, forHTTPHeaderField: $0) }

        guard let (data, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let container = try? JSONDecoder().decode(PlexMediaContainerResponse.self, from: data)
        else { return nil }
        return container.mediaContainer.metadata
    }

    /// Lowest-numbered child, skipping Specials (season/episode index 0) when a
    /// regular one exists. Falls back to source order if indices are missing.
    private func firstPlayableChild(_ children: [PlexMetadata]) -> PlexMetadata? {
        let sorted = children.sorted { ($0.index ?? Int.max) < ($1.index ?? Int.max) }
        return sorted.first { ($0.index ?? 0) >= 1 } ?? sorted.first ?? children.first
    }

    /// Releases a transcode session so the server stops the ffmpeg process.
    func stopTranscode(base: URL, token: String, sessionID: String) async {
        guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return }
        comps.path = "/video/:/transcode/universal/stop"
        comps.queryItems = [
            URLQueryItem(name: "session", value: sessionID),
            URLQueryItem(name: "X-Plex-Token", value: token),
            URLQueryItem(name: "X-Plex-Client-Identifier", value: KeyStore.plexClientID),
        ]
        guard let url = comps.url else { return }
        _ = try? await session.data(from: url)
    }

    private func canDirectPlay(_ media: PlexMedia) -> Bool {
        guard let container = media.container?.lowercased(),
              Self.directContainers.contains(container),
              let video = media.videoCodec?.lowercased(),
              Self.directVideoCodecs.contains(video),
              let audio = media.audioCodec?.lowercased(),
              Self.directAudioCodecs.contains(audio)
        else { return false }
        return true
    }

    private func fetchMetadata(base: URL, token: String, ratingKey: String) async -> PlexMetadata? {
        guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        comps.path = "/library/metadata/\(ratingKey)"
        comps.queryItems = [URLQueryItem(name: "checkFiles", value: "1")]
        guard let url = comps.url else { return nil }

        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        PlexAuth.headers(token: token).forEach { req.setValue($1, forHTTPHeaderField: $0) }

        guard let (data, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let container = try? JSONDecoder().decode(PlexMediaContainerResponse.self, from: data)
        else { return nil }
        return container.mediaContainer.metadata?.first
    }

    /// Direct file URL — token in the query because AVPlayer can't attach
    /// headers to its segment/range requests.
    private func directURL(base: URL, key: String, token: String) -> URL? {
        guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        comps.path = key
        comps.queryItems = [
            URLQueryItem(name: "X-Plex-Token", value: token),
            URLQueryItem(name: "X-Plex-Client-Identifier", value: KeyStore.plexClientID),
        ]
        return comps.url
    }

    /// Universal transcoder → HLS playlist. `subtitles=none` because we overlay
    /// OpenSubtitles ourselves; `directStream=1` copies compatible tracks.
    private func transcodeURL(base: URL, ratingKey: String, token: String,
                              session: String, resolution: String?, maxBitrate: Int?) -> URL {
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = "/video/:/transcode/universal/start.m3u8"
        var items: [URLQueryItem] = [
            URLQueryItem(name: "path", value: "/library/metadata/\(ratingKey)"),
            URLQueryItem(name: "mediaIndex", value: "0"),
            URLQueryItem(name: "partIndex", value: "0"),
            URLQueryItem(name: "protocol", value: "hls"),
            URLQueryItem(name: "directPlay", value: "0"),
            URLQueryItem(name: "directStream", value: "1"),
            URLQueryItem(name: "fastSeek", value: "1"),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "subtitles", value: "none"),
            URLQueryItem(name: "audioBoost", value: "100"),
            URLQueryItem(name: "videoQuality", value: "100"),
            URLQueryItem(name: "session", value: session),
            URLQueryItem(name: "X-Plex-Session-Identifier", value: session),
            URLQueryItem(name: "X-Plex-Token", value: token),
            URLQueryItem(name: "X-Plex-Client-Identifier", value: KeyStore.plexClientID),
            URLQueryItem(name: "X-Plex-Product", value: AppConfig.plexProduct),
            URLQueryItem(name: "X-Plex-Version", value: AppConfig.plexVersion),
            URLQueryItem(name: "X-Plex-Platform", value: "iOS"),
            URLQueryItem(name: "X-Plex-Device", value: "iPhone"),
            URLQueryItem(name: "X-Plex-Device-Name", value: "Cineslate"),
        ]
        if let resolution { items.append(URLQueryItem(name: "videoResolution", value: resolution)) }
        if let maxBitrate, maxBitrate > 0 {
            items.append(URLQueryItem(name: "maxVideoBitrate", value: String(maxBitrate)))
        }
        comps.queryItems = items
        return comps.url!
    }
}

/// Observable Plex connection state shared across the app.
@MainActor
final class PlexStore: ObservableObject {
    @Published private(set) var credential: PlexCredential?
    @Published private(set) var servers: [PlexServer] = []
    @Published var isConnecting = false
    @Published var errorMessage: String?

    private let service = PlexService()

    var isConnected: Bool { credential != nil }
    var username: String? { credential?.username }
    var serverCount: Int { servers.count }

    init() {
        if let data = Keychain.load(account: Keychain.plexAccount),
           let cred = try? JSONDecoder().decode(PlexCredential.self, from: data) {
            credential = cred
            Task { await refreshServers() }
        }
    }

    func connect() async {
        isConnecting = true
        errorMessage = nil
        do {
            let cred = try await PlexAuth().login()
            persist(cred)
            await refreshServers()
        } catch let error as PlexAuthError {
            if case .cancelled = error {} else { errorMessage = error.errorDescription }
        } catch {
            errorMessage = error.localizedDescription
        }
        isConnecting = false
    }

    func disconnect() {
        credential = nil
        servers = []
        Keychain.clear(account: Keychain.plexAccount)
    }

    func refreshServers() async {
        guard let token = credential?.authToken else { return }
        servers = await service.loadServers(token: token)
    }

    func findSource(ref: MediaRef, title: String, year: String?) async -> PlexMatch? {
        guard isConnected, !servers.isEmpty else { return nil }
        for server in servers {
            if let meta = await service.findMatch(server: server, ref: ref, title: title, year: year),
               let ratingKey = meta.ratingKey {
                return PlexMatch(
                    serverName: server.name,
                    resolution: meta.resolutionLabel,
                    server: server,
                    ratingKey: ratingKey,
                    deepLink: service.deepLink(machineID: server.machineIdentifier, ratingKey: ratingKey)
                )
            }
        }
        return nil
    }

    /// Resolves a concrete stream URL for in-app playback.
    func resolvePlayable(_ match: PlexMatch) async -> PlexPlayable? {
        await service.fetchPlayable(server: match.server, ratingKey: match.ratingKey)
    }

    /// Tears down a transcode session when playback ends.
    func stopPlayback(_ playable: PlexPlayable) async {
        guard let session = playable.session else { return }
        await service.stopTranscode(base: playable.base, token: playable.token, sessionID: session)
    }

    private func persist(_ cred: PlexCredential) {
        credential = cred
        if let data = try? JSONEncoder().encode(cred) {
            Keychain.save(data, account: Keychain.plexAccount)
        }
    }
}
