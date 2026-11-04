import Foundation
import SwiftUI
import Security

public enum MeetySessionState: Equatable {
    case signedOut
    case signingIn
    case signedIn
}

/// Multi-account Google session. Refresh tokens live in the Keychain, account list in UserDefaults.
@MainActor
public final class SessionManager: ObservableObject {
    @Published public private(set) var accounts: [AuthenticatedUser] = []
    @Published public private(set) var state: MeetySessionState = .signedOut
    @Published public var lastError: String?
    @Published public var accentHex: [String: String] = [:]

    private let keychain = KeychainClient()
    private var access: [String: (token: String, expiry: Date)] = [:]
    private let defaults = UserDefaults.standard

    public init() {
        if let d = defaults.data(forKey: "accounts"), let a = try? JSONDecoder().decode([AuthenticatedUser].self, from: d) {
            accounts = a
        }
        accentHex = (defaults.dictionary(forKey: "accentHex") as? [String: String]) ?? [:]
        // Drop accounts whose refresh token is missing (e.g. saved by an older build); they can't authenticate.
        let stale = accounts.filter { keychain.get("refresh.\($0.email)") == nil }
        if !stale.isEmpty {
            accounts.removeAll { stale.contains($0) }
            persist()
            lastError = "Please sign in again: saved credentials for \(stale.map(\.email).joined(separator: ", ")) were not found."
        }
        state = accounts.isEmpty ? .signedOut : .signedIn
    }

    public func addAccount() async {
        state = .signingIn; lastError = nil
        do {
            let r = try await GoogleSignInCoordinator().signIn()
            let status = keychain.set(r.refreshToken, for: "refresh.\(r.user.email)")
            guard status == errSecSuccess else {
                lastError = "Couldn't save credentials to the Keychain (status \(status)). Sign-in was not completed."
                state = accounts.isEmpty ? .signedOut : .signedIn
                return
            }
            access[r.user.email] = (r.accessToken, r.expiry)
            if !accounts.contains(r.user) { accounts.append(r.user); persist() }
        } catch { lastError = error.localizedDescription }
        state = accounts.isEmpty ? .signedOut : .signedIn
    }

    public func remove(_ user: AuthenticatedUser) {
        keychain.remove("refresh.\(user.email)")
        access[user.email] = nil
        accounts.removeAll { $0 == user }
        persist()
        state = accounts.isEmpty ? .signedOut : .signedIn
    }

    /// Called when the API reports no usable credentials for an account.
    public func invalidate(email: String) {
        guard let u = accounts.first(where: { $0.email == email }) else { return }
        remove(u)
        lastError = "Please sign in again: credentials for \(email) are no longer available."
    }

    public func accessToken(for email: String) async throws -> String {
        if let t = access[email], t.expiry > Date().addingTimeInterval(60) { return t.token }
        guard let refresh = keychain.get("refresh.\(email)") else { throw MeetySessionError.noAccount }
        let (tok, exp) = try await GoogleSignInCoordinator.refresh(refreshToken: refresh)
        access[email] = (tok, exp)
        return tok
    }

    public func setAccent(_ hex: String, for email: String) {
        accentHex[email] = hex
        defaults.set(accentHex, forKey: "accentHex")
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(accounts) { defaults.set(d, forKey: "accounts") }
    }
}
