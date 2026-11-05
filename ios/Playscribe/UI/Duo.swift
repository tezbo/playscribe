import SwiftUI

/// The pose the app is presented in, derived from the container and its reserved regions rather
/// than device or screen checks (Preparing your app for iPhone Duo: base layout on the scene's
/// or containing view's bounds; never use userInterfaceIdiom or interface orientation).
enum Pose: String {
    /// Outer display, or any compact-width container.
    case closed
    /// Inner display, no active fold.
    case flat
    /// Partly folded with a vertical division: left page, right page.
    case book
    /// Partly folded with a horizontal division: upper stage, lower controls.
    case tabletop
}

struct DuoContext: Equatable {
    var pose: Pose = .closed
    var size: CGSize = .zero
    /// The active fold, in the root container's coordinates.
    var division: CGRect?
    /// Active occlusions (cameras), in the root container's coordinates.
    var occlusions: [CGRect] = []
    var isLandscape: Bool { size.width > size.height }
    var isFolded: Bool { division != nil }

    /// Tabletop: how far content whose bottom edge is at `bottom` (screen coordinates) must be
    /// lifted so it ends `gap` pt above the division band. Zero in every other pose.
    func clearance(forBottom bottom: CGFloat, gap: CGFloat = 24) -> CGFloat {
        guard pose == .tabletop, let d = division, bottom > 0 else { return 0 }
        return max(0, bottom - (d.minY - gap))
    }
}

private struct DuoKey: EnvironmentKey {
    static let defaultValue = DuoContext()
}

extension EnvironmentValues {
    var duo: DuoContext {
        get { self[DuoKey.self] }
        set { self[DuoKey.self] = newValue }
    }
}

/// Reads the scene-level container and its reserved regions, and publishes the pose.
struct DuoReader<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @ViewBuilder var content: (DuoContext) -> Content

    var body: some View {
        GeometryReader { proxy in
            let ctx = Self.context(proxy: proxy, compact: hSize == .compact)
            content(ctx)
                .environment(\.duo, ctx)
        }
    }

    static func context(proxy: GeometryProxy, compact: Bool) -> DuoContext {
        #if DEBUG
        // CI only (docs/ci.md): `-qaPose` stands in for the hinge so pose-sensitive tests can run without Device Hub.
        if let forced = QAPose.forced { return forced.context(size: proxy.size) }
        #endif
        let divisions = proxy.reservedRegions(kind: .division).filter(\.isActive)
        let occlusions = proxy.reservedRegions(kind: .occlusion).filter(\.isActive).map(\.frame)
        var ctx = DuoContext(size: proxy.size, occlusions: occlusions)
        if let fold = divisions.first?.frame {
            ctx.division = fold
            ctx.pose = fold.height > fold.width ? .book : .tabletop
        } else {
            ctx.pose = compact ? .closed : .flat
        }
        return ctx
    }
}

// MARK: - Debug overlay (internal builds): tappable frames and reserved regions (QA method §9)

struct TappableFrameKey: PreferenceKey {
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}

extension View {
    /// Reports this control's frame to the debug overlay. Apply to tappable elements.
    func tappableFrame() -> some View { modifier(TappableFrameReporter()) }
}

/// False for screens that are in the hierarchy but not on screen: a tab not selected, the Library
/// under a pushed game book, everything under a sheet. Their frames aren't tappable.
private struct AuditActiveKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var auditActive: Bool {
        get { self[AuditActiveKey.self] }
        set { self[AuditActiveKey.self] = newValue }
    }
}

extension View {
    func auditActive(_ active: Bool) -> some View { transformEnvironment(\.auditActive) { $0 = $0 && active } }
}

/// Reports the part of a control that can be touched: clipped to the nearest scroll view, so a
/// chip scrolled out of sight doesn't count.
/// Frame tracking for the fold audit and debug overlay. Off in normal use: a geometry reader on
/// every control, reporting up to the root on each scroll frame, made long pages lag (0.2.0).
enum FoldAuditSwitch {
    nonisolated(unsafe) static var enabled = ProcessInfo.processInfo.arguments.contains("-qaRoute")
}

private struct TappableFrameReporter: ViewModifier {
    @Environment(\.auditActive) private var active
    func body(content: Content) -> some View {
        if FoldAuditSwitch.enabled { tracked(content) } else { content }
    }

    private func tracked(_ content: Content) -> some View {
        content.background {
            GeometryReader { g in
                let local = CGRect(origin: .zero, size: g.size)
                let visible = g.bounds(of: .scrollView).map { local.intersection($0) } ?? local
                let global = g.frame(in: .global)
                Color.clear.preference(key: TappableFrameKey.self,
                                       value: active && !visible.isNull && !visible.isEmpty
                                           ? [visible.offsetBy(dx: global.minX, dy: global.minY)] : [])
            }
        }
    }
}

extension View {
    /// Reports a layout container's frame to the fold audit (TT-0), without marking it tappable.
    func foldAudited() -> some View { tappableFrame() }
}

/// TT-0: counts reported frames that intersect the active division. Always present (internal
/// builds) as a hidden element the UI test reads: "fold-crossings: N".
struct FoldAudit: View {
    var frames: [CGRect]
    var duo: DuoContext
    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            let crossing = duo.division.map { fold in
                frames.map { $0.offsetBy(dx: -origin.x, dy: -origin.y) }
                    .filter { $0.width > 1 && $0.height > 1 && $0.intersects(fold.insetBy(dx: 0.5, dy: 0.5)) }
            } ?? []
            let detail = crossing.prefix(3).map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" }.joined(separator: " | ")
            let fold = duo.division.map { "fold \(Int($0.minX))-\(Int($0.maxX))" } ?? ""
            let label = "fold-crossings: \(crossing.count); pose: \(duo.pose.rawValue); \(fold) \(detail)"
            Text(label)
                .font(.system(size: 1))
                .opacity(0.01)
                .accessibilityIdentifier("foldAudit")
                .accessibilityLabel(label)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

struct DebugOverlay: View {
    var frames: [CGRect]
    var duo: DuoContext

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            ZStack(alignment: .topLeading) {
                if let fold = duo.division {
                    Rectangle().fill(.red.opacity(0.25))
                        .frame(width: fold.width, height: fold.height)
                        .offset(x: fold.minX, y: fold.minY)
                }
                ForEach(Array(duo.occlusions.enumerated()), id: \.offset) { _, r in
                    Rectangle().fill(.orange.opacity(0.3)).frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                }
                ForEach(Array(frames.enumerated()), id: \.offset) { _, r in
                    let bad = duo.division.map { fold in
                        r.offsetBy(dx: -origin.x, dy: -origin.y).intersects(fold) || (duo.pose == .tabletop && r.minY - origin.y < fold.minY)
                    } ?? false
                    Rectangle().strokeBorder(bad ? .red : .green, lineWidth: 1)
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX - origin.x, y: r.minY - origin.y)
                }
                Text("\(duo.pose.rawValue), \(Int(duo.size.width))×\(Int(duo.size.height)) pt")
                    .font(PlayscribeFont.caption2.monospaced())
                    .padding(4)
                    .background(.black.opacity(0.7))
                    .offset(x: 8, y: 8)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}


#if DEBUG
/// A launch argument that stands in for the hinge, so the layout and fold-audit tests can run headless and in
/// parallel on hosted runners (docs/ci.md). Debug builds only: it is compiled out of Release, so TestFlight builds
/// cannot be forced into a pose. It replaces the reserved regions, not the container, so it is only as realistic
/// as the simulator's panel size: the real-hinge gate (tools/qa/gate.sh, TIER=full) still signs off a release.
///
///     -qaPose closed | flat | book | tabletop   (or the qaPose default)
enum QAPose {
    /// The hinge band's thickness, in points. An assumption until calibrated against a real Device Hub run
    /// (compare with the "fold a-b" range in the fold-audit label from a real gate run).
    static let hinge: CGFloat = 24

    /// Read from UserDefaults, so it works as a launch argument (`-qaPose book`, which the argument domain feeds in)
    /// and as `simctl spawn <udid> defaults write <bundle id> qaPose book`, which reaches every launch a test makes.
    static var forced: Pose? { UserDefaults.standard.string(forKey: "qaPose").flatMap(Pose.init(rawValue:)) }
}

extension Pose {
    func context(size: CGSize) -> DuoContext {
        var ctx = DuoContext(size: size)
        ctx.pose = self
        switch self {
        case .book:
            ctx.division = CGRect(x: (size.width - QAPose.hinge) / 2, y: 0, width: QAPose.hinge, height: size.height)
        case .tabletop:
            ctx.division = CGRect(x: 0, y: (size.height - QAPose.hinge) / 2, width: size.width, height: QAPose.hinge)
        case .closed, .flat:
            break
        }
        return ctx
    }
}
#endif
