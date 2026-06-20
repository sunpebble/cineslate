import Foundation

// MARK: - Auth

/// Response from POST /api/v2/pins
struct PlexPin: Decodable {
    let id: Int
    let code: String
    let authToken: String?
}

/// Persisted Plex credential (account token + identity).
struct PlexCredential: Codable {
    var authToken: String
    var username: String
    var clientID: String
}

/// GET /api/v2/user
struct PlexAccount: Decodable {
    let username: String?
    let title: String?
    let email: String?
    var displayName: String { username ?? title ?? email ?? "Plex" }
}

// MARK: - Resources (servers)

struct PlexResource: Decodable {
    let name: String
    let clientIdentifier: String
    let provides: String
    let accessToken: String?
    let connections: [PlexConnection]?

    var isServer: Bool { provides.contains("server") }
}

struct PlexConnection: Decodable {
    let `protocol`: String?
    let address: String?
    let port: Int?
    let uri: String
    let local: Bool?
    let relay: Bool?
}

/// A server we can query, with its candidate connection URIs (preference-ordered).
struct PlexServer: Identifiable, Hashable {
    let name: String
    let machineIdentifier: String
    let accessToken: String
    let connectionURIs: [URL]
    /// Relay (plex.tv-proxied) URIs — bandwidth-throttled, so never direct-play over these.
    let relayURIs: Set<URL>
    var id: String { machineIdentifier }
}

// MARK: - Library lookup

struct PlexMediaContainerResponse: Decodable {
    let mediaContainer: PlexMediaContainer
    enum CodingKeys: String, CodingKey { case mediaContainer = "MediaContainer" }
}

struct PlexMediaContainer: Decodable {
    let metadata: [PlexMetadata]?
    enum CodingKeys: String, CodingKey { case metadata = "Metadata" }
}

struct PlexMetadata: Decodable {
    let ratingKey: String?
    let title: String?
    let type: String?
    let year: Int?
    let index: Int?             // season number / episode number within a container
    let duration: Int?          // ms
    let guid: String?
    let media: [PlexMedia]?
    let guids: [PlexGuid]?

    enum CodingKeys: String, CodingKey {
        case ratingKey, title, type, year, index, duration, guid
        case media = "Media"
        case guids = "Guid"
    }

    /// Best available video resolution label, e.g. "1080p" / "4K".
    var resolutionLabel: String? {
        guard let res = media?.compactMap(\.videoResolution).first else { return nil }
        switch res.lowercased() {
        case "4k": return "4K"
        case "sd": return "SD"
        default: return res + "p"
        }
    }

    func matchesTMDB(_ id: Int) -> Bool {
        let needle = "tmdb://\(id)"
        if let guid, guid.contains(needle) { return true }
        if let guids, guids.contains(where: { $0.id?.contains(needle) == true }) { return true }
        return false
    }
}

struct PlexGuid: Decodable {
    let id: String?
}

struct PlexMedia: Decodable {
    let id: Int?
    let videoResolution: String?
    let container: String?
    let videoCodec: String?
    let audioCodec: String?
    let bitrate: Int?           // kbps
    let width: Int?
    let height: Int?
    let duration: Int?          // ms
    let parts: [PlexPart]?

    enum CodingKeys: String, CodingKey {
        case id, videoResolution, container, videoCodec, audioCodec, bitrate, width, height, duration
        case parts = "Part"
    }

    /// `1920x1080` for the transcoder's `videoResolution` param, if known.
    var pixelResolution: String? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return "\(width)x\(height)"
    }
}

struct PlexPart: Decodable {
    let id: Int?
    let key: String?           // e.g. /library/parts/12345/167.../file.mkv
    let container: String?
    let duration: Int?         // ms
    let size: Int?
    let streams: [PlexStream]?

    enum CodingKeys: String, CodingKey {
        case id, key, container, duration, size
        case streams = "Stream"
    }
}

/// A track inside a Part. `streamType`: 1=video, 2=audio, 3=subtitle.
struct PlexStream: Decodable {
    let id: Int?
    let streamType: Int?
    let codec: String?
    let language: String?
    let languageCode: String?
    let displayTitle: String?
    let selected: Bool?
    let forced: Bool?
}

/// A concrete playable match surfaced on the detail page. Carries enough
/// context (server + ratingKey) to resolve a stream URL for in-app playback.
struct PlexMatch: Hashable {
    let serverName: String
    let resolution: String?
    let server: PlexServer
    let ratingKey: String
    let deepLink: URL
}

/// A resolved Plex stream ready to feed AVPlayer (direct file or HLS playlist).
struct PlexPlayable {
    let url: URL               // AVPlayer source
    let isTranscoded: Bool     // true → HLS transcode session that must be stopped
    let title: String
    let durationSeconds: Double?
    let base: URL              // reachable server base (for /stop)
    let token: String          // server accessToken
    let session: String?       // transcode session id, nil when direct play
}
