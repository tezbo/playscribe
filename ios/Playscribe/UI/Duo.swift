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

    /// The name QA and the gate use for this pose (Closed, Open, Book, Tabletop), not the enum's own.
    var label: String {
        switch self {
        case .closed: "Closed"
        case .flat: "Open"
        case .book: "Book"
        case .tabletop: "Tabletop"
        }
    }
}

struct DuoContext: Equatable {
    var pose: Pose = .closed
    var size: CGSize = .zero
    /// The active fold, in the root container's coordinates.
    var division: CGRect?
    /// Active occlusions (cameras), in the root container's coordinates.
    var occlusions: [CGRect] = []
    /// The container's safe-area insets, as the system reports them (fold harness calibration).
    var safeArea = EdgeInsets()
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

/// Reserved regions a test supplies in place of the system's, in the root container's coordinates
/// (fold harness, docs/fold-harness.md). Nil in the app: the real regions are read from the proxy.
struct InjectedRegions: Equatable {
    var division: CGRect?
    var occlusions: [CGRect] = []
}

private struct InjectedRegionsKey: EnvironmentKey {
    static let defaultValue: InjectedRegions? = nil
}

extension EnvironmentValues {
    var injectedRegions: InjectedRegions? {
        get { self[InjectedRegionsKey.self] }
        set { self[InjectedRegionsKey.self] = newValue }
    }
}

/// QA (internal builds only): `-qaPose book` or `-qaPose tabletop` gives DuoReader a synthetic fold in the container it is
/// already in, so a pose can be set at launch with no Device Hub clicks and no focus change (docs/ci.md item 6). The fold
/// sits where the real one did in the Mac stills (its leading edge at 0.525 of the width for Book and its top edge at 0.447 of the height for Tabletop, 40 pt thick, the PoseCatalog numbers; the real device may differ by a few percent until the calibration pair is read).
/// Launch on the inner display, landscape for book and portrait for tabletop. Closed and Open need no fold, so they are not
/// arguments. Ignored in a distribution build, like `-qaRoute`.
enum QAPose {
    /// Tests only: stands in for the launch argument.
    nonisolated(unsafe) static var overrideName: String?

    static var name: String? {
        #if INTERNAL
        guard BuildChannel.showsInternalTools else { return nil }
        return overrideName ?? UserDefaults.standard.string(forKey: "qaPose")
        #else
        return nil
        #endif
    }

    static func injected(size: CGSize) -> InjectedRegions? {
        regions(named: name, size: size)
    }

    static func regions(named name: String?, size: CGSize) -> InjectedRegions? {
        switch name {
        case "book": InjectedRegions(division: CGRect(x: size.width * 0.525, y: 0, width: 40, height: size.height))
        case "tabletop": InjectedRegions(division: CGRect(x: 0, y: size.height * 0.447, width: size.width, height: 40))
        default: nil
        }
    }
}

/// Reads the scene-level container and its reserved regions, and publishes the pose.
struct DuoReader<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.injectedRegions) private var injected
    @ViewBuilder var content: (DuoContext) -> Content

    var body: some View {
        GeometryReader { proxy in
            let ctx = Self.context(proxy: proxy, compact: hSize == .compact, injected: injected)
            content(ctx)
                .environment(\.duo, ctx)
        }
    }

    static func context(proxy: GeometryProxy, compact: Bool, injected: InjectedRegions? = nil) -> DuoContext {
        var ctx: DuoContext
        if let injected {
            ctx = context(size: proxy.size, compact: compact, division: injected.division, occlusions: injected.occlusions)
        } else {
            if let qa = QAPose.injected(size: proxy.size) {
                var ctx = context(size: proxy.size, compact: compact, division: qa.division, occlusions: qa.occlusions)
                ctx.safeArea = proxy.safeAreaInsets
                return ctx
            }
            let divisions = proxy.reservedRegions(kind: .division).filter(\.isActive)
            let occlusions = proxy.reservedRegions(kind: .occlusion).filter(\.isActive).map(\.frame)
            ctx = context(size: proxy.size, compact: compact, division: divisions.first?.frame, occlusions: occlusions)
        }
        ctx.safeArea = proxy.safeAreaInsets
        return ctx
    }

    /// The pose from a container size and its active fold. Pure, so the whole pose catalog is unit-testable.
    static func context(size: CGSize, compact: Bool, division: CGRect?, occlusions: [CGRect]) -> DuoContext {
        var ctx = DuoContext(size: size, occlusions: occlusions)
        if let fold = division {
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

/// Frames of named containers (the Library deck, the toolbar) for the fold harness and its sim calibration.
struct NamedFrameKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Reports this view's frame (global coordinates) under a name. Audit builds only, like `tappableFrame`.
    @ViewBuilder func namedFrame(_ name: String) -> some View {
        if FoldAuditSwitch.enabled {
            background {
                GeometryReader { g in
                    Color.clear.preference(key: NamedFrameKey.self, value: [name: g.frame(in: .global)])
                }
            }
        } else {
            self
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
    var named: [String: CGRect] = [:]

    /// One JSON object with everything the fold harness needs to be compared with the simulator: the container, the
    /// safe area, the reserved regions, every tappable frame and the named frames, all relative to the container
    /// origin and rounded to 0.5 pt. `tools/qa/compare_harness.py` diffs it against the harness's own dump.
    static func probeJSON(frames: [CGRect], duo: DuoContext, named: [String: CGRect], origin: CGPoint) -> String {
        func r(_ x: CGFloat) -> Double { (Double(x) * 2).rounded() / 2 }
        func box(_ c: CGRect) -> [Double] { [r(c.minX), r(c.minY), r(c.width), r(c.height)] }
        let rel: (CGRect) -> CGRect = { $0.offsetBy(dx: -origin.x, dy: -origin.y) }
        var obj: [String: Any] = [
            "pose": duo.pose.rawValue,
            "size": [r(duo.size.width), r(duo.size.height)],
            "safeArea": [r(duo.safeArea.top), r(duo.safeArea.leading), r(duo.safeArea.bottom), r(duo.safeArea.trailing)],
            "occlusions": duo.occlusions.map(box),
            "frames": frames.map { box(rel($0)) }.sorted { ($0[1], $0[0]) < ($1[1], $1[0]) },
            "named": named.mapValues { box(rel($0)) },
        ]
        if let d = duo.division { obj["division"] = box(d) }
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            let crossing = duo.division.map { fold in
                frames.map { $0.offsetBy(dx: -origin.x, dy: -origin.y) }
                    .filter { $0.width > 1 && $0.height > 1 && $0.intersects(fold.insetBy(dx: 0.5, dy: 0.5)) }
            } ?? []
            let detail = crossing.prefix(3).map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" }.joined(separator: " | ")
            let fold = duo.division.map { "fold \(Int($0.minX))-\(Int($0.maxX))" } ?? ""
            let label = "fold-crossings: \(crossing.count); pose: \(duo.pose.rawValue); landscape: \(duo.isLandscape ? "yes" : "no"); \(fold) \(detail)"
            Text(label)
                .font(.system(size: 1))
                .opacity(0.01)
                .accessibilityIdentifier("foldAudit")
                .accessibilityLabel(label)
            Text("probe")
                .font(.system(size: 1))
                .opacity(0.01)
                .accessibilityIdentifier("poseProbe")
                .accessibilityLabel(Self.probeJSON(frames: frames, duo: duo, named: named, origin: origin))
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

private struct HarnessSplitKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Tests only (fold harness): lay out `SplitArrangement` by the injected division instead of the system's ArrangementView,
    /// which only splits against a real reserved region. Never set in the app. Triage, not a sign-off (r052-harness-book-split).
    var harnessSplit: Bool {
        get { self[HarnessSplitKey.self] }
        set { self[HarnessSplitKey.self] = newValue }
    }
}

/// `ArrangementView(.split)` in the app; under the harness a stand-in that gives the primary the area before the division and
/// the secondary the area after it, so a headless still can show the Book split.
struct SplitArrangement<Primary: View, Secondary: View>: View {
    @Environment(\.harnessSplit) private var standIn
    @Environment(\.injectedRegions) private var injected
    @ViewBuilder var primary: () -> Primary
    @ViewBuilder var secondary: () -> Secondary

    /// The Mac's right page is about 9 pt wider than the plain split gives (Quinn, KCD II Book AX5, e6fd747: the system reserves
    /// less for the side rail). Harness-only calibration; re-measure if the Mac still moves.
    private static var railReserveTrim: CGFloat { 9 }

    var body: some View {
        if standIn, let d = injected?.division {
            GeometryReader { proxy in
                if d.height > d.width { // vertical bar: primary left, secondary right (Book, Open landscape)
                    HStack(spacing: 0) {
                        primary().frame(width: max(0, d.minX))
                        Color.clear.frame(width: d.width)
                        secondary().frame(width: max(0, proxy.size.width - d.maxX + Self.railReserveTrim))
                    }
                } else { // horizontal bar: primary above, secondary below (Tabletop)
                    VStack(spacing: 0) {
                        primary().frame(height: max(0, d.minY))
                        Color.clear.frame(height: d.height)
                        secondary().frame(height: max(0, proxy.size.height - d.maxY))
                    }
                }
            }
        } else {
            ArrangementView { primary() } secondary: { secondary() }
                .arrangementViewStyle(.split)
        }
    }
}
