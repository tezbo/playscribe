import SwiftUI

/// The branded splash, first launch only (§2): 0.8 s plus a 0.3 s fade; under Reduce Motion a
/// 0.3 s fade with no movement. The composition follows the pose:
///   closed   → mark and name stacked
///   flat     → the mark's pages open, name beneath
///   book     → the mark splits across the hinge: "Play" on the left page, "scribe" on the right
///   tabletop → the mark in the upper region, the name in the lower one
struct SplashView: View {
    var duo: DuoContext
    /// s-06-brand-swap: the spark glows when there is an unread update, rests dim when caught up.
    var lit = true
    var onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var opened = false
    @State private var opacity = 1.0
    @State private var progress = 0.0

    var body: some View {
        ZStack {
            // Follows the appearance, so the hand-off to the first Library frame never flashes dark to cream.
            (scheme == .dark ? PlayscribeColor.ink950 : PlayscribeColor.vellum100).ignoresSafeArea()
            content
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            if !reduceMotion {
                withAnimation(.spring(duration: 0.6)) { opened = true }
                withAnimation(.easeInOut(duration: 0.8)) { progress = 1 }
            } else {
                opened = true
                progress = 1
            }
            // QA: `-qaSplashHold <seconds>` keeps the splash up so stills are not a race with the fade.
            let hold = UserDefaults.standard.double(forKey: "qaSplashHold")
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 800) + .seconds(hold))
            // A pose change at launch (the Duo settling into Book or Tabletop) rebuilds this view and cancels its task:
            // `try?` would swallow that and dismiss the splash at once. The rebuilt view runs its own timer instead.
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.3)) { opacity = 0 }
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            onDone()
        }
    }

    private var markSize: CGFloat { min(duo.size.width, duo.size.height) * (duo.pose == .closed ? 0.26 : 0.2) }

    @ViewBuilder private var content: some View {
        let size = markSize
        switch duo.pose {
        case .book where duo.division != nil:
            if let fold = duo.division {
                HStack(spacing: 0) {
                    HStack(spacing: 12) {
                        SplashWord(text: split.0)
                        MarkPageView(side: .left, height: size * 1.4, onLight: scheme == .light).rotation3DEffect(.degrees(opened ? 0 : 60), axis: (0, 1, 0), anchor: .trailing)
                    }
                    .frame(width: fold.minX, alignment: .trailing)
                    Color.clear.frame(width: fold.width)
                    HStack(spacing: 12) {
                        MarkPageView(side: .right, height: size * 1.4, onLight: scheme == .light).overlay(alignment: .topLeading) { MarkRightPageLit(height: size * 1.4) }.rotation3DEffect(.degrees(opened ? 0 : -60), axis: (0, 1, 0), anchor: .leading)
                        SplashWord(text: split.1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .tabletop where duo.division != nil:
            if let fold = duo.division {
                VStack(spacing: 0) {
                    BrandMark(size: size * 1.3, lit: true, onLight: scheme == .light).frame(height: fold.minY).scaleEffect(opened ? 1 : 0.9)
                    Color.clear.frame(height: fold.height)
                    VStack(spacing: 6) { name }.frame(maxHeight: .infinity)
                }
            }
        case .closed, .flat, .book, .tabletop:
            // Book and Tabletop fall back to the stacked layout until the division is known.
            VStack(spacing: 16) {
                BrandMark(size: size, lit: true, onLight: scheme == .light).scaleEffect(opened ? 1 : 0.9)
                name
            }
        }
    }

    private var name: some View {
        VStack(spacing: 6) {
            SplashWord(text: Brand.name)
            UpdateBar(progress: progress, track: scheme == .dark ? PlayscribeColor.ink600 : PlayscribeColor.vellum300).padding(.top, 10)
        }
    }

    /// The name split across the hinge.
    private var split: (String, String) {
        let n = Brand.name
        if n == "Playscribe" { return ("Play", "scribe") }
        let mid = n.index(n.startIndex, offsetBy: n.count / 2)
        return (String(n[..<mid]), String(n[mid...]))
    }
}

/// Brand v2: an update bar, ember on an ink 600 track, filling during the hold.
struct UpdateBar: View {
    var progress: Double
    var track = PlayscribeColor.ink600
    var body: some View {
        Capsule().fill(track)
            .frame(width: 120, height: 4)
            .overlay(alignment: .leading) {
                Capsule().fill(PlayscribeColor.ember500).frame(width: 120 * progress, height: 4)
            }
    }
}

/// The splash name in Instrument Sans Bold (wordmark-on-light / -on-dark): the ember spark takes the place of the i's dot.
struct SplashWord: View {
    var text: String
    @Environment(\.colorScheme) private var scheme
    private static let size: CGFloat = 40
    private var ink: Color { scheme == .dark ? PlayscribeColor.textPrimary : PlayscribeColor.ink900 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                if ch == "i" {
                    Text("\u{0131}").foregroundStyle(ink).overlay(alignment: .top) {
                        SparkShape().fill(BrandMark.emberSpark).frame(width: 13, height: 13).offset(y: -2)
                    }
                } else {
                    Text(String(ch)).foregroundStyle(ink)
                }
            }
        }
        .font(.custom("InstrumentSans-Bold", size: Self.size, relativeTo: .largeTitle))
        .fixedSize()
        .accessibilityHidden(true)
    }
}
