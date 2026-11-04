import Foundation
import StoreKit
import SwiftUI

public enum EntitlementState: Equatable { case unknown, free, pro }

/// StoreKit 2 subscription state. Product IDs come from the PRO_PRODUCT_IDS Info.plist key.
@MainActor
public final class SubscriptionManager: ObservableObject {
    @Published public private(set) var entitlementState: EntitlementState = .unknown
    @Published public private(set) var offerings: [Product] = []
    @Published public private(set) var isLoadingOfferings = false
    @Published public private(set) var latestExpirationDate: Date?
    @Published public private(set) var isAutoRenewing = false
    @Published public private(set) var activeProductIdentifier: String?
    @Published public var lastErrorMessage: String?

    /// Dev override: MEETBALL_FORCE_PRO=1 in the scheme environment.
    /// Pro is unlocked when PRO_UNLOCKED=YES in Info.plist (set in project.yml) or MEETBALL_FORCE_PRO=1 is in the environment.
    private let forcePro = ProcessInfo.processInfo.environment["MEETBALL_FORCE_PRO"] == "1"
        || AppConfig.string("PRO_UNLOCKED").uppercased() == "YES"
    private var updates: Task<Void, Never>?

    public var isPremiumActive: Bool { forcePro || entitlementState == .pro }
    var productIDs: [String] {
        AppConfig.string("PRO_PRODUCT_IDS").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public init() {
        updates = Task { [weak self] in
            for await _ in Transaction.updates { await self?.refresh() }
        }
        Task { await refresh() }
    }

    public func refresh() async {
        isLoadingOfferings = true
        defer { isLoadingOfferings = false }
        do { offerings = try await Product.products(for: productIDs).sorted { $0.price < $1.price } }
        catch { lastErrorMessage = error.localizedDescription }
        var pro = false; var exp: Date?; var pid: String?; var renew = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, productIDs.contains(t.productID), t.revocationDate == nil {
                pro = true; exp = t.expirationDate; pid = t.productID
                if let p = offerings.first(where: { $0.id == t.productID }),
                   let st = try? await p.subscription?.status.first, case .verified(let ri) = st.renewalInfo { renew = ri.willAutoRenew }
            }
        }
        entitlementState = pro ? .pro : .free
        latestExpirationDate = exp; activeProductIdentifier = pid; isAutoRenewing = renew
    }

    public func purchase(_ product: Product) async {
        do {
            switch try await product.purchase() {
            case .success(let v):
                if case .verified(let t) = v { await t.finish() } else { lastErrorMessage = "Purchase failed verification." }
                await refresh()
            default: break
            }
        } catch { lastErrorMessage = error.localizedDescription }
    }

    public func restore() async {
        do { try await AppStore.sync(); await refresh() } catch { lastErrorMessage = error.localizedDescription }
    }
}
