import Foundation
import Network
import CryptoKit
import AppKit
import os

public enum MeetySessionError: LocalizedError {
    case notConfigured, cancelled, tokenExchange(String), noAccount
    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "Google client ID is not configured. Set GOOGLE_CLIENT_ID (see README)."
        case .cancelled: return "Authorization flow was cancelled."
        case .tokenExchange(let m): return "Token request failed: \(m)"
        case .noAccount: return "No Google account is connected."
        }
    }
}

public struct AuthenticatedUser: Codable, Hashable, Identifiable {
    public var email: String
    public var name: String
    public var id: String { email }
}

enum AppConfig {
    static func string(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
    }
    static var googleClientID: String { string("GOOGLE_CLIENT_ID") }
    static var googleClientSecret: String { string("GOOGLE_CLIENT_SECRET") }
}

/// Google OAuth 2.0 for installed apps: PKCE + loopback redirect (RFC 8252).
public final class GoogleSignInCoordinator {
    static let scopes = ["openid", "email", "profile", "https://www.googleapis.com/auth/calendar"]

    private var listener: NWListener?

    public init() {}

    public func signIn() async throws -> (user: AuthenticatedUser, refreshToken: String, accessToken: String, expiry: Date) {
        let clientID = AppConfig.googleClientID
        guard !clientID.isEmpty else { throw MeetySessionError.notConfigured }
        let verifier = Self.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = Self.randomString(16)

        let (port, codeStream) = try await startLoopback(expectedState: state)
        let redirect = "http://127.0.0.1:\(port)"
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            .init(name: "client_id", value: clientID), .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"), .init(name: "scope", value: Self.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state), .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent select_account")]
        let authURL = c.url!
        await MainActor.run { _ = NSWorkspace.shared.open(authURL) }
        defer { listener?.cancel(); listener = nil }
        guard let code = try await codeStream() else { throw MeetySessionError.cancelled }

        let tok = try await Self.tokenRequest([
            "code": code, "client_id": clientID, "redirect_uri": redirect,
            "grant_type": "authorization_code", "code_verifier": verifier])
        guard let refresh = tok.refresh_token else { throw MeetySessionError.tokenExchange("no refresh token") }
        let user = try await Self.userInfo(accessToken: tok.access_token)
        return (user, refresh, tok.access_token, Date().addingTimeInterval(TimeInterval(tok.expires_in)))
    }

    public static func refresh(refreshToken: String) async throws -> (String, Date) {
        let tok = try await tokenRequest(["refresh_token": refreshToken, "client_id": AppConfig.googleClientID,
                                          "grant_type": "refresh_token"])
        return (tok.access_token, Date().addingTimeInterval(TimeInterval(tok.expires_in)))
    }

    struct TokenResponse: Decodable { let access_token: String; let expires_in: Int; let refresh_token: String? }

    static func tokenRequest(_ params: [String: String]) async throws -> TokenResponse {
        var p = params
        let secret = AppConfig.googleClientSecret
        if !secret.isEmpty { p["client_secret"] = secret }
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents(); form.queryItems = p.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw MeetySessionError.tokenExchange(String(data: data, encoding: .utf8) ?? "HTTP error")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    static func userInfo(accessToken: String) async throws -> AuthenticatedUser {
        var req = URLRequest(url: URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        struct Info: Decodable { let email: String; let name: String? }
        let i = try JSONDecoder().decode(Info.self, from: data)
        return AuthenticatedUser(email: i.email, name: i.name ?? i.email)
    }

    // MARK: loopback server
    private func startLoopback(expectedState: String) async throws -> (UInt16, () async throws -> String?) {
        let l = try NWListener(using: .tcp, on: .any)
        listener = l
        var continuation: CheckedContinuation<String?, Error>?
        var pending: Result<String?, Error>?
        let lock = NSLock()
        func deliver(_ r: Result<String?, Error>) {
            lock.lock(); defer { lock.unlock() }
            if let c = continuation { continuation = nil; c.resume(with: r) } else if pending == nil { pending = r }
        }
        l.newConnectionHandler = { conn in
            conn.start(queue: .global())
            conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                let line = data.flatMap { String(data: $0, encoding: .utf8) }?.components(separatedBy: "\r\n").first ?? ""
                let path = line.components(separatedBy: " ").dropFirst().first ?? "/"
                let comps = URLComponents(string: "http://127.0.0.1" + path)
                let q = Dictionary(uniqueKeysWithValues: (comps?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
                let ok = q["code"] != nil && q["state"] == expectedState
                let body = ok ? "<html><body>Authorization complete.<br>Return to Meetball.</body></html>"
                              : "<html><body>Not a valid redirect.</body></html>"
                let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
                if ok { deliver(.success(q["code"])) }
                else if q["error"] != nil { deliver(.success(nil)) }
            }
        }
        let port: UInt16 = try await withCheckedThrowingContinuation { cont in
            // The handler can fire more than once; resume the continuation only on the first ready/failed.
            let resumed = OSAllocatedUnfairLock(initialState: false)
            l.stateUpdateHandler = { st in
                let result: Result<UInt16, Error>
                switch st {
                case .ready: result = .success(l.port?.rawValue ?? 0)
                case .failed(let e): result = .failure(e)
                default: return
                }
                let isFirst = resumed.withLock { done -> Bool in
                    defer { done = true }
                    return !done
                }
                if isFirst { cont.resume(with: result) }
            }
            l.start(queue: .global())
        }
        let wait: () async throws -> String? = {
            try await withThrowingTaskGroup(of: String?.self) { group in
                group.addTask {
                    try await withCheckedThrowingContinuation { (c: CheckedContinuation<String?, Error>) in
                        lock.lock()
                        if let p = pending { lock.unlock(); c.resume(with: p) }
                        else { continuation = c; lock.unlock() }
                    }
                }
                group.addTask { try await Task.sleep(for: .seconds(300)); return nil }
                let first = try await group.next() ?? nil
                group.cancelAll()
                return first
            }
        }
        return (port, wait)
    }

    static func randomString(_ n: Int) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<n).map { _ in chars.randomElement()! })
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
