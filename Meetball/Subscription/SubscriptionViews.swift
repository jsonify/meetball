import SwiftUI
import StoreKit
import SK1Tokens
import SK1UI

public struct ProBadge: View {
    public init() {}
    public var body: some View {
        Text("PRO").font(.system(size: 9, weight: .bold)).padding(.horizontal, 5).padding(.vertical, 2)
            .background(LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing), in: Capsule())
            .foregroundStyle(.white)
    }
}

/// The upgrade sheet on the chassis: what Pro adds, each plan as a key with its price on a chip, and Restore / Not now.
public struct PaywallView: View {
    @EnvironmentObject var subs: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    public init() {}
    public var body: some View {
        VStack(alignment: .leading, spacing: SK1.Metrics.groupSpacing) {
            Text("Upgrade to Meetball Pro").font(.title.bold())
            SKGroup(caption: "Pro adds") {
                SKRow(title: "Hard alerts") { BulletRow("Full screen, on every display") }
                SKRow(title: "Smart follow-ups") { BulletRow("\u{201C}Are you still joining?\u{201D}") }
                SKRow(title: "Per-calendar rules") { BulletRow("Alert strength for each calendar") }
                SKRow(title: "More timings") { BulletRow("Reminders up to 15 minutes before") }
            }
            SKGroup(caption: "Plans") {
                if subs.isLoadingOfferings {
                    SKRow(title: "Loading plans") { SKLamp(color: .warning, lit: true, label: "Loading", blinking: true) }
                } else if subs.offerings.isEmpty {
                    SKRow(title: "No plans available", subtitle: "Check PRO_PRODUCT_IDS and your StoreKit configuration.") {
                        SKLamp(color: .danger, lit: true, label: "Unavailable")
                    }
                }
                ForEach(subs.offerings) { p in
                    SKRow(title: p.displayName) {
                        HStack(spacing: 8) {
                            SKChip(p.displayPrice)
                            Button("Buy") { Task { await subs.purchase(p) } }.buttonStyle(.sk1Key())
                        }
                    }
                }
            }
            if let e = subs.lastErrorMessage { Text(e).sk1Hint() }
            SKGroove()
            HStack {
                Button("Restore purchases") { Task { await subs.restore() } }.buttonStyle(.sk1Key())
                Spacer()
                Button("Not now") { dismiss() }.buttonStyle(.sk1Key())
            }
        }
        .padding(SK1.Metrics.paneMargin)
        .frame(width: 460)
        .sk1Chassis()
        .onChange(of: subs.isPremiumActive) { _, new in if new { dismiss() } }
    }
}

/// Settings › Pro: whether Pro is on (a lamp), when it renews, and Upgrade / Restore.
public struct SubscriptionStatusView: View {
    @EnvironmentObject var subs: SubscriptionManager
    @State private var showPaywall = false
    public init() {}
    public var body: some View {
        SKGroup(caption: "Meetball Pro", note: subs.isPremiumActive ? nil : "Soft reminders are free; heads-up and hard alerts, per-calendar rules and more timings are Pro.") {
            SKRow(title: subs.isPremiumActive ? "Pro is active" : "You're on the free plan", subtitle: renewal) {
                SKLamp(color: subs.isPremiumActive ? .success : .warning, lit: true, size: 8,
                       label: subs.isPremiumActive ? "Pro active" : "Free plan")
            }
            if !subs.isPremiumActive {
                SKRow(title: "Upgrade") {
                    Button("Upgrade to Pro") { showPaywall = true }.buttonStyle(.sk1Key(.orange))
                }
            }
            SKRow(title: "Restore purchases", subtitle: "Bought Pro on another Mac? Restore it here.") {
                Button("Restore") { Task { await subs.restore() } }.buttonStyle(.sk1Key())
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    private var renewal: String? {
        guard subs.isPremiumActive, let d = subs.latestExpirationDate else { return nil }
        let day = d.formatted(date: .abbreviated, time: .omitted)
        return subs.isAutoRenewing ? "Renews \(day)" : "Expires \(day)"
    }
}
