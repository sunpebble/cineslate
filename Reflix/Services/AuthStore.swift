import Foundation
import SwiftUI

/// Holds the Supabase session and drives email sign-up / sign-in / sign-out
/// against GoTrue + the `signup` edge function. Session persists in Keychain.
@MainActor
final class AuthStore: ObservableObject {

    struct Session: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var userId: String
        var email: String
    }

    @Published private(set) var session: Session?
    @Published var isWorking = false
    @Published var errorMessage: String?

    var isAuthenticated: Bool { session != nil }
    var email: String { session?.email ?? "" }

    private let session_ = URLSession(configuration: .default)

    init() {
        if let data = Keychain.load(),
           let saved = try? JSONDecoder().decode(Session.self, from: data) {
            session = saved
        }
    }

    // MARK: Public actions

    func signUp(email: String, password: String) async {
        await run {
            try await self.createConfirmedUser(email: email, password: password)
            let session = try await self.passwordGrant(email: email, password: password)
            self.persist(session)
        }
    }

    func signIn(email: String, password: String) async {
        await run {
            let session = try await self.passwordGrant(email: email, password: password)
            self.persist(session)
        }
    }

    func signOut() {
        session = nil
        Keychain.clear()
    }

    /// 发送 6 位邮箱验证码（注册即登录）。成功返回 true。
    func sendEmailOTP(email: String) async -> Bool {
        var ok = false
        await run {
            try await self.requestEmailOTP(email: email)
            ok = true
        }
        return ok
    }

    /// 校验邮箱验证码并建立 session。
    func verifyEmailOTP(email: String, code: String) async {
        await run {
            let session = try await self.verifyOTPToken(email: email, code: code)
            self.persist(session)
        }
    }

    /// Returns a non-expired access token, refreshing first if needed.
    func validAccessToken() async -> String? {
        guard let current = session else { return nil }
        if current.expiresAt.timeIntervalSinceNow > 60 { return current.accessToken }
        do {
            let refreshed = try await refresh(current.refreshToken)
            persist(refreshed)
            return refreshed.accessToken
        } catch {
            // Refresh failed → treat as logged out.
            signOut()
            return nil
        }
    }

    // MARK: Networking

    private func createConfirmedUser(email: String, password: String) async throws {
        var req = URLRequest(url: URL(string: AppConfig.supabaseFunctionsURL + "/signup")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email, "password": password,
            "display_name": String(email.split(separator: "@").first ?? ""),
        ])
        let (data, response) = try await session_.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        if code == 200 { return }
        // 409 = already registered → fall through and let the password grant decide.
        if code == 409 { return }
        let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
        throw AuthError.message(msg ?? "注册失败")
    }

    private func requestEmailOTP(email: String) async throws {
        var req = URLRequest(url: URL(string: AppConfig.supabaseAuthURL + "/otp")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email, "create_user": true,
        ])
        let (data, response) = try await session_.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        if code == 200 { return }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let msg = (json?["msg"] as? String)
            ?? (json?["error_description"] as? String)
            ?? (json?["message"] as? String)
        throw AuthError.message(localized(msg))
    }

    private func verifyOTPToken(email: String, code: String) async throws -> Session {
        var req = URLRequest(url: URL(string: AppConfig.supabaseAuthURL + "/verify")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email, "token": code, "type": "email",
        ])
        return try await decodeToken(from: req, fallbackEmail: email)
    }

    private func passwordGrant(email: String, password: String) async throws -> Session {
        var req = URLRequest(url: URL(string: AppConfig.supabaseAuthURL + "/token?grant_type=password")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        return try await decodeToken(from: req, fallbackEmail: email)
    }

    private func refresh(_ refreshToken: String) async throws -> Session {
        var req = URLRequest(url: URL(string: AppConfig.supabaseAuthURL + "/token?grant_type=refresh_token")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
        return try await decodeToken(from: req, fallbackEmail: session?.email ?? "")
    }

    private func decodeToken(from request: URLRequest, fallbackEmail: String) async throws -> Session {
        let (data, response) = try await session_.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.message("服务器响应异常")
        }
        guard code == 200, let access = json["access_token"] as? String else {
            let msg = (json["error_description"] as? String)
                ?? (json["msg"] as? String)
                ?? (json["message"] as? String)
            throw AuthError.message(localized(msg))
        }
        let refresh = json["refresh_token"] as? String ?? ""
        let expiresIn = json["expires_in"] as? Double ?? 3600
        let user = json["user"] as? [String: Any]
        let userId = user?["id"] as? String ?? ""
        let userEmail = (user?["email"] as? String) ?? fallbackEmail
        return Session(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(expiresIn),
            userId: userId,
            email: userEmail
        )
    }

    // MARK: Helpers

    private func persist(_ newSession: Session) {
        session = newSession
        if let data = try? JSONEncoder().encode(newSession) { Keychain.save(data) }
    }

    private func run(_ work: @escaping () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        do {
            try await work()
        } catch let AuthError.message(text) {
            errorMessage = text
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func localized(_ message: String?) -> String {
        guard let message else { return "登录失败，请重试" }
        let lower = message.lowercased()
        if lower.contains("invalid login credentials") { return "邮箱或密码错误" }
        if lower.contains("email not confirmed") { return "邮箱尚未验证" }
        if lower.contains("expired") || lower.contains("invalid token") { return "验证码错误或已过期" }
        if lower.contains("for security purposes") || lower.contains("rate limit") || lower.contains("too many") {
            return "操作过于频繁，请稍后再试"
        }
        return message
    }

    enum AuthError: Error { case message(String) }
}
