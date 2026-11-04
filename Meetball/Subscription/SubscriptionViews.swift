import SwiftUI
import StoreKit

public struct ProBadge: View {
    public init() {}
    public var body: some View {
        Text("PRO").font(.system(size: 9, weight: .bold)).padding(.horizontal, 5).padding(.vertical, 2)
            .background(LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing), in: Capsule())
            .foregroundStyle(.white)
    }
}

public struct PaywallView: View {
    @EnvironmentObject var subs: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    public init() {}
    public var body: some View {
        VStack(spacing: 16) {
            Text("Upgrade to Meetball Pro").font(.title.bold())
            VStack(alignment: .leading, spacing: 8) {
                BulletRow("Hard, fullscreen-ish alerts that make missing meetings practically impossible")
                BulletRow("Smart follow-ups: \"Are you still joining?\"")
                BulletRow("Per-calendar alert rules")
                BulletRow("More reminder timings and quiet hours")
            }
            if subs.isLoadingOfferings { ProgressView() }
            else if subs.offerings.isEmpty { Text("No offerings available. Check PRO_PRODUCT_IDS and your StoreKit configuration.").font(.caption).foregroundStyle(.secondary) }
            ForEach(subs.offerings) { p in
                Button { Task { await subs.purchase(p) } } label: {
                    HStack { Text(p.displayName); Spacer(); Text(p.displayPrice).bold() }.padding(8)
                }.buttonStyle(.borderedProminent)
            }
            if let e = subs.lastErrorMessage { Text(e).font(.caption).foregroundStyle(.red) }
            HStack { Button("Restore purchases") { Task { await subs.restore() } }; Spacer(); Button("Not now") { dismiss() } }
        }
        .padding(24).frame(width: 440)
        .onChange(of: subs.isPremiumActive) { _, new in if new { dismiss() } }
    }
}

public struct SubscriptionStatusView: View {
    @EnvironmentObject var subs: SubscriptionManager
    @State private var showPaywall = false
    public init() {}
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if subs.isPremiumActive {
                Label("Meetball Pro is active", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                if let d = subs.latestExpirationDate {
                    Text(subs.isAutoRenewing ? "Renews \(d.formatted(date: .abbreviated, time: .omitted))" : "Expires \(d.formatted(date: .abbreviated, time: .omitted))").foregroundStyle(.secondary)
                }
            } else {
                Text("You're on the free plan.")
                Button("Upgrade to Meetball Pro") { showPaywall = true }.buttonStyle(.borderedProminent)
            }
            Button("Restore purchases") { Task { await subs.restore() } }
        }.sheet(isPresented: $showPaywall) { PaywallView() }
    }
}
