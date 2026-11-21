import SwiftUI
import UIKit

/// bug-064 (Iris's rule): in light mode the status bar content is light wherever art or the player is under it, and dark only
/// over the cream page. Dark mode is untouched: there the bar is always light and none of this is set up.
///
/// The app's window belongs to SwiftUI, whose root controller cannot be told a status bar style, and setting a dark style on that
/// window recolours the page (Mac at 867d42d5: preferredColorScheme leaked to the window and left it half dark). So the style comes
/// from a separate, clear window above the app's that takes no touches and is hidden from VoiceOver: iOS asks the frontmost
/// full-screen window's root controller for the status bar style, and that controller answers from the state here. The app's own
/// window, its colours and its presentations are never touched.
@MainActor
final class StatusBarTone {
    static let shared = StatusBarTone()

    /// Off in dark mode: the system's own light bar is already right there.
    static var active: Bool { PlayscribeApp.colorScheme == .light }

    /// How far the art's bottom edge must come back past the bar's bottom before the bar turns light again (Iris: 8 pt).
    nonisolated static let hysteresis: CGFloat = 8

    private var window: ToneWindow?
    private let controller = ToneController()
    private var art: [UUID: CGRect] = [:]
    private var coverUp = false
    private(set) var light = false

    /// The status bar's bottom edge in window coordinates.
    var barBottom: CGFloat {
        window?.windowScene?.statusBarManager?.statusBarFrame.maxY ?? 0
    }

    func attach(to scene: UIWindowScene) {
        guard Self.active, window?.windowScene !== scene else { return }
        let w = ToneWindow(windowScene: scene)
        w.windowLevel = UIWindow.Level(UIWindow.Level.normal.rawValue + 1)
        w.backgroundColor = .clear
        w.overrideUserInterfaceStyle = .light
        w.rootViewController = controller
        w.accessibilityElementsHidden = true
        w.isHidden = false
        window = w
        recompute()
    }

    /// A full-screen cover (the update player or a trailer) is up: always light over the player.
    func setCover(_ up: Bool) {
        guard coverUp != up else { return }
        coverUp = up
        recompute()
    }

    /// Wide art reports its frame in window coordinates; nil when it leaves the screen.
    func report(_ id: UUID, frame: CGRect?) {
        guard Self.active else { return }
        if let frame { art[id] = frame } else { art[id] = nil }
        recompute()
    }

    /// The window's width, for telling wide art from a tile.
    var width: CGFloat { window?.bounds.width ?? 0 }

    /// Art is under the bar when its top edge is above the bar's bottom (a header that starts part way down the bar counts: Mac at
    /// d7656024, Closed portrait: art starting under the clock drew dark glyphs at 3.4:1) and its bottom edge is below the bar's bottom. Going dark needs the edge
    /// above the bar's bottom; coming back to light needs it a further 8 pt down, so a scroll resting on the edge never flickers.
    nonisolated static func isLight(current: Bool, barBottom bar: CGFloat, art: [CGRect], coverUp: Bool) -> Bool {
        if coverUp { return true }
        guard bar > 0 else { return false }
        let needed = current ? bar : bar + hysteresis
        return art.contains { $0.minY < bar && $0.maxY > needed }
    }

    private func recompute() {
        let next = Self.isLight(current: light, barBottom: barBottom, art: Array(art.values), coverUp: coverUp)
        guard next != light else { return }
        light = next
        controller.light = next
    }
}

private final class ToneWindow: UIWindow {
    /// Never takes a touch: every touch goes on to the app's window below.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

private final class ToneController: UIViewController {
    var light = false {
        didSet { setNeedsStatusBarAppearanceUpdate() }
    }
    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
    }
    override var preferredStatusBarStyle: UIStatusBarStyle { light ? .lightContent : .darkContent }
    override var prefersStatusBarHidden: Bool { false }
}

/// Reports wide art to `StatusBarTone`, and where the art runs under the status bar in light mode, lays a scrim over that part so
/// the light clock holds 4.5:1 and the glyphs 3:1 over bright art too (Iris, bug-064).
private struct StatusBarArt: ViewModifier {
    @State private var id = UUID()
    @State private var scrim: CGFloat = 0

    func body(content: Content) -> some View {
        if StatusBarTone.active {
            content
                .overlay(alignment: .top) {
                    if scrim > 0 {
                        LinearGradient(stops: [.init(color: .black.opacity(0.55), location: 0),
                                               .init(color: .black.opacity(0.45), location: 0.6),
                                               .init(color: .black.opacity(0), location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: scrim)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                    let tone = StatusBarTone.shared
                    // Only art that spans most of the bar counts: a tile or thumbnail scrolled under it does not.
                    let wide = tone.width > 0 && frame.width >= tone.width * 0.6
                    tone.report(id, frame: wide ? frame : nil)
                    let bar = tone.barBottom
                    let next = wide && frame.minY < bar && frame.maxY > bar ? max(0, bar - frame.minY + 24) : 0
                    if abs(next - scrim) > 0.5 { scrim = next }
                }
                .onDisappear { StatusBarTone.shared.report(id, frame: nil) }
        } else {
            content
        }
    }
}

extension View {
    /// Marks art that can sit under the status bar (bug-064). Does nothing in dark mode.
    func statusBarArt() -> some View { modifier(StatusBarArt()) }
}

/// Puts the tone window on this view's scene. Used once, at the root.
struct StatusBarToneAnchor: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) {}

    final class Probe: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            isUserInteractionEnabled = false
            if let scene = window?.windowScene { StatusBarTone.shared.attach(to: scene) }
        }
    }
}
