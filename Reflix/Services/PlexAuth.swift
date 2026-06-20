import AuthenticationServices
import UIKit

enum PlexAuthError: LocalizedError {
    case cancelled
    case timedOut
    case server(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "已取消 Plex 登录"
        case .timedOut: return "Plex 授权超时，请重试"
        case .server(let m): return m
        }
    }
}

/// Drives Plex's PIN-based OAuth: create a PIN, let the user authorise in a
/// web session, then poll until an auth token is issued.
@MainActor
final class PlexAuth: NSObject, ASWebAuthenticationPresentationContextProviding {

    private let session = URLSession(configuration: .default)
    private var webSession: ASWebAuthenticationSession?
    /// Set once the web auth browser closes (forwardUrl callback or user dismiss).
    private var webSessionClosed = false

    /// Headers identifying this client to plex.tv.
    nonisolated static func headers(token: String? = nil) -> [String: String] {
        var h = [
            "X-Plex-Product": AppConfig.plexProduct,
            "X-Plex-Version": AppConfig.plexVersion,
            "X-Plex-Client-Identifier": KeyStore.plexClientID,
            "X-Plex-Platform": "iOS",
            "X-Plex-Device": "iPhone",
            "X-Plex-Device-Name": "Reflix",
            "Accept": "application/json",
        ]
        if let token { h["X-Plex-Token"] = token }
        return h
    }

    /// Runs the full login flow and returns a stored credential.
    func login() async throws -> PlexCredential {
        let pin = try await createPin()

        // Present the browser AND poll concurrently. Plex's web auth does not
        // reliably redirect to a custom-scheme forwardUrl, so we never depend on
        // the ASWebAuthenticationSession callback to finish the flow. Polling is
        // the source of truth: the instant the PIN is linked we have the token
        // and dismiss the browser ourselves — the user returns to the app
        // automatically without waiting on a redirect that may never come.
        startWebSession(url: buildAuthURL(code: pin.code))
        defer { cancelWebSession() }

        let token = try await pollForToken(pinID: pin.id, code: pin.code)
        let account = (try? await fetchAccount(token: token))
        let username = account?.displayName ?? "Plex"
        return PlexCredential(authToken: token, username: username, clientID: KeyStore.plexClientID)
    }

    // MARK: Steps

    private func createPin() async throws -> PlexPin {
        var req = URLRequest(url: URL(string: AppConfig.plexPinsURL + "?strong=true")!)
        req.httpMethod = "POST"
        Self.headers().forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await session.data(for: req)
        guard let code = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else {
            throw PlexAuthError.server("无法创建 Plex 授权请求")
        }
        return try JSONDecoder().decode(PlexPin.self, from: data)
    }

    private func buildAuthURL(code: String) -> URL {
        var items = [
            URLQueryItem(name: "clientID", value: KeyStore.plexClientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "forwardUrl", value: AppConfig.plexForwardURL),
            URLQueryItem(name: "context[device][product]", value: AppConfig.plexProduct),
        ]
        var comps = URLComponents()
        comps.queryItems = items
        let query = comps.percentEncodedQuery ?? ""
        // Plex reads parameters from the URL fragment.
        return URL(string: AppConfig.plexAuthAppURL + "#?" + query)!
    }

    /// Presents the web auth browser without blocking. The completion handler
    /// only flips `webSessionClosed` — the poll loop drives the actual flow.
    private func startWebSession(url: URL) {
        webSessionClosed = false
        let webSession = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: AppConfig.plexCallbackScheme
        ) { [weak self] _, _ in
            Task { @MainActor in self?.webSessionClosed = true }
        }
        webSession.presentationContextProvider = self
        webSession.prefersEphemeralWebBrowserSession = false
        self.webSession = webSession
        if !webSession.start() {
            webSessionClosed = true
        }
    }

    /// Dismisses the browser if it's still open (e.g. once we have the token).
    private func cancelWebSession() {
        webSession?.cancel()
        webSession = nil
    }

    private func pollForToken(pinID: Int, code: String) async throws -> String {
        let url = URL(string: "\(AppConfig.plexPinsURL)/\(pinID)?code=\(code)")!
        // PIN lives 30 min; poll ~3 min so slow logins (2FA etc.) still complete.
        var graceRemaining = 5
        for _ in 0..<180 {
            var req = URLRequest(url: url)
            Self.headers().forEach { req.setValue($1, forHTTPHeaderField: $0) }
            if let (data, _) = try? await session.data(for: req),
               let pin = try? JSONDecoder().decode(PlexPin.self, from: data),
               let token = pin.authToken, !token.isEmpty {
                return token
            }
            // The user closed the browser without a token landing yet. Plex may
            // have linked the PIN a beat before dismissal, so keep polling for a
            // few more seconds; if nothing arrives, treat it as a cancellation.
            if webSessionClosed {
                graceRemaining -= 1
                if graceRemaining <= 0 { throw PlexAuthError.cancelled }
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw PlexAuthError.timedOut
    }

    private func fetchAccount(token: String) async throws -> PlexAccount {
        var req = URLRequest(url: URL(string: AppConfig.plexUserURL)!)
        Self.headers(token: token).forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let (data, _) = try await session.data(for: req)
        return try JSONDecoder().decode(PlexAccount.self, from: data)
    }

    // MARK: ASWebAuthenticationPresentationContextProviding

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
