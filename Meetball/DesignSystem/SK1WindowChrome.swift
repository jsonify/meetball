import SwiftUI
import AppKit
import SK1Tokens
import SK1UI

// Skreener's window chrome (`RetroUI.useChassis`, `SpeakerGrille`, the editor's and Settings' title strips): no stock
// title bar or toolbar, the chassis running up behind the window buttons, a small tracked caption in the title bar's
// strip and a speaker grille at its right end.

/// Meetball's SK-1 nickname, as Skreener is the SK-1: on the LCDs and in the title bars.
enum SK1Nickname {
    static let meetball = "MB-1"
}

extension View {
    /// Puts the view under an SK-1 title strip: the window's title bar made transparent (the title hidden, the content
    /// running under it), `title` in the strip, either after the window buttons or centred, and a grille of `grille`
    /// holes at the right. `groove` draws a groove under the strip (Settings has one; the editor doesn't).
    func sk1WindowChrome<Title: View>(centered: Bool = false, grille: (columns: Int, rows: Int) = (7, 1),
                                      groove: Bool = false, @ViewBuilder title: () -> Title) -> some View {
        modifier(SK1WindowChromeModifier(centered: centered, grille: grille, groove: groove, title: title()))
    }
}

private struct SK1WindowChromeModifier<Title: View>: ViewModifier {
    let centered: Bool
    let grille: (columns: Int, rows: Int)
    let groove: Bool
    let title: Title

    func body(content: Content) -> some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                SK1TitleStrip(centered: centered, grille: grille, title: title)
                    .frame(height: max(geo.safeAreaInsets.top, 28))
                if groove { SKGroove() }
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .toolbar(.hidden, for: .windowToolbar)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(SK1WindowConfigurator())
    }
}

/// The title bar's strip: the caption 84 pt in (after the window buttons) or centred, and the grille 16 pt from the
/// right, both centred in the strip.
private struct SK1TitleStrip<Title: View>: View {
    let centered: Bool
    let grille: (columns: Int, rows: Int)
    let title: Title

    var body: some View {
        ZStack {
            if centered {
                title.padding(.horizontal, 90)
            } else {
                HStack { title; Spacer(minLength: 0) }.padding(.leading, 84)
            }
            HStack {
                Spacer()
                SKGrille(columns: grille.columns, rows: grille.rows).padding(.trailing, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

/// "MB-1  CALENDAR — NOVEMBER 2026", as Skreener's "SK-1  EDITOR — …": the nickname in heavy ink, the rest in the
/// soft ink, 9.5 pt upper case tracked as a caption.
struct SK1WindowTitle: View {
    let text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = SK1.palette(for: scheme)
        (Text(SK1Nickname.meetball).font(.system(size: 9.5, weight: .heavy)).foregroundStyle(Color(sk1Hex: p.ink))
         + Text("  " + text.uppercased()).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Color(sk1Hex: p.inkSoft)))
            .tracking(SK1.TypeScale.caption.kern)
            .lineLimit(1)
            .truncationMode(.middle)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A speaker grille (Skreener's `SpeakerGrille`): `columns` × `rows` round holes 4 pt across, 3 pt apart, shaded from
/// the palette's light grille colour at the top to its dark one, with a light lip under each.
struct SKGrille: View {
    var columns = 7
    var rows = 1
    private static let hole: CGFloat = 4, gap: CGFloat = 3
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = SK1.palette(for: scheme)
        let step = Self.hole + Self.gap
        Canvas { ctx, _ in
            for row in 0..<rows {
                for col in 0..<columns {
                    let rect = CGRect(x: CGFloat(col) * step, y: CGFloat(row) * step, width: Self.hole, height: Self.hole)
                    ctx.fill(Path(ellipseIn: rect.offsetBy(dx: 0, dy: 0.5)), with: .color(.white.opacity(p.dark ? 0.06 : 0.8)))
                    ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
                        Gradient(colors: [Color(sk1Hex: p.grilleLight), Color(sk1Hex: p.grilleDark)]),
                        center: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.35), startRadius: 0,
                        endRadius: Self.hole * 0.75))
                }
            }
        }
        .frame(width: CGFloat(columns) * step - Self.gap, height: CGFloat(rows) * step - Self.gap + 1)
        .accessibilityHidden(true)
    }
}

/// Makes the hosting window's title bar transparent with its title hidden and the content running under it
/// (`RetroUI.useChassis`). The title stays set, for the Window menu and Mission Control.
private struct SK1WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ConfiguringView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ConfiguringView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let w = window else { return }
            w.styleMask.insert(.fullSizeContentView)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
        }
    }
}
