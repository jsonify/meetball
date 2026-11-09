import SwiftUI
import SK1Tokens
import SK1UI

/// The floating dock in the bottom corner, in place of a full-width row of keys: a rounded chassis plate holding the
/// screen key (the screen showing, its name and a chevron) and the orange Add key. The screen key opens the quick
/// menu above it; a sideways swipe on it steps straight to the next or previous screen.
struct PhoneDock: View {
    typealias Tab = PhoneRootView.Tab

    @Binding var tab: Tab
    /// The screens offered, Settings included, in menu order.
    let tabs: [Tab]
    @Binding var menuOpen: Bool
    let add: () -> Void

    /// Height of the plate: a large key and the plate's rim either side.
    static let height: CGFloat = SK1KeySize.large.height + 2 * rim
    /// How far scrolling content needs to clear the dock to be reached: the dock, its gap above the home indicator
    /// and a little air.
    static let clearance: CGFloat = height + 20
    private static let rim: CGFloat = 7
    private static let radius: CGFloat = height / 2

    var body: some View {
        SKPlate(radius: Self.radius) {
            HStack(spacing: 8) {
                screenKey
                Button {
                    menuOpen = false
                    add()
                } label: {
                    Image(systemName: "plus").font(.system(size: 22, weight: .bold))
                }
                .buttonStyle(.sk1Key(.orange, size: .large))
                .accessibilityLabel("Add an event")
            }
            .padding(Self.rim)
            .padding(.horizontal, 3)
            .fixedSize()
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .overlay(alignment: .bottomTrailing) {
            if menuOpen {
                PhoneQuickMenu(tab: tab, tabs: tabs) { picked in
                    tab = picked
                    menuOpen = false
                }
                .padding(.bottom, Self.height + 10)
                .transition(.scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: menuOpen)
    }

    private var screenKey: some View {
        Button {
            menuOpen.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: tab.symbol)
                Text(tab.title)
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .heavy))
                    .rotationEffect(.degrees(menuOpen ? 180 : 0))
                    .opacity(0.55)
            }
            .padding(.horizontal, 4)
        }
        .buttonStyle(.sk1Key(isOn: menuOpen, size: .large))
        .simultaneousGesture(swipe)
        .accessibilityLabel("Screens")
        .accessibilityValue(Text(tab.title))
        .accessibilityHint("Shows the screens to switch to.")
        .accessibilityAdjustableAction { direction in
            if direction == .increment { step(1) } else if direction == .decrement { step(-1) }
        }
    }

    /// Left and right along the dock's key step through the calendar screens (Settings stays in the menu).
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { g in
                let dx = g.translation.width
                guard abs(dx) > 40, abs(dx) > abs(g.translation.height) else { return }
                step(dx < 0 ? 1 : -1)
            }
    }

    private func step(_ by: Int) {
        let screens = tabs.filter { $0 != .settings }
        guard let i = screens.firstIndex(of: tab) else {
            if let first = screens.first { tab = first }
            return
        }
        let next = i + by
        guard screens.indices.contains(next) else { return }
        menuOpen = false
        tab = screens[next]
    }
}

/// The quick menu over the dock: the calendar screens in one sunken tray, Settings in another, the one showing
/// marked by its lamp, all on a rounded chassis plate.
struct PhoneQuickMenu: View {
    typealias Tab = PhoneRootView.Tab

    let tab: Tab
    let tabs: [Tab]
    let pick: (Tab) -> Void

    var body: some View {
        let screens = tabs.filter { $0 != .settings }
        SKPlate(radius: 24) {
            VStack(spacing: 8) {
                SKWell(radius: 16) {
                    VStack(spacing: 0) {
                        ForEach(Array(screens.enumerated()), id: \.element) { i, t in
                            if i > 0 { SKGroove().padding(.horizontal, 12) }
                            row(t)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                if tabs.contains(.settings) {
                    SKWell(radius: 16) {
                        row(.settings).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
            .padding(8)
        }
        .frame(width: 236)
        .shadow(color: .black.opacity(0.22), radius: 22, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Screens")
        .accessibilityAddTraits(.isModal)
    }

    private func row(_ t: Tab) -> some View {
        let current = t == tab
        return Button { pick(t) } label: {
            HStack(spacing: 12) {
                Image(systemName: t.symbol)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 24)
                Text(t.title)
                    .font(.body.weight(current ? .semibold : .regular))
                Spacer(minLength: 12)
                SKLamp(color: .red, lit: current, label: t.title)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(PhoneMenuRowStyle())
        .accessibilityLabel(Text(t.title))
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}

/// A quick-menu row: plain, darkening a touch while held.
private struct PhoneMenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(Color.primary.opacity(configuration.isPressed ? 0.07 : 0))
    }
}
