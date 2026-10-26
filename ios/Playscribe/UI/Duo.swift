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
private struct TappableFrameReporter: ViewModifier {
    @Environment(\.auditActive) private var active
    func body(content: Content) -> some View {
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
                Text("\(duo.pose.rawValue) · \(Int(duo.size.width))×\(Int(duo.size.height)) pt")
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
