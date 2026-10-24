import SwiftUI

/// The branded splash, first launch only (§2): 0.8 s plus a 0.3 s fade; under Reduce Motion a
/// 0.3 s fade with no movement. The composition follows the pose:
///   closed   → mark and name stacked
///   flat     → the mark's pages open, name beneath
///   book     → the mark splits across the hinge: "Play" on the left page, "scribe" on the right
///   tabletop → the mark in the upper region, the name in the lower one
struct SplashView: View {
    var duo: DuoContext
    var onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opened = false
    @State private var opacity = 1.0

    var body: some View {
        ZStack {
            Color.ink0.ignoresSafeArea()
            content
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            if !reduceMotion { withAnimation(.spring(duration: 0.6)) { opened = true } } else { opened = true }
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 800))
            withAnimation(.easeOut(duration: 0.3)) { opacity = 0 }
            try? await Task.sleep(for: .milliseconds(300))
            onDone()
        }
    }

    private var markSize: CGFloat { min(duo.size.width, duo.size.height) * (duo.pose == .closed ? 0.26 : 0.2) }

    @ViewBuilder private var content: some View {
        let size = markSize
        switch duo.pose {
        case .book:
            if let fold = duo.division {
                HStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text(split.0).font(.largeTitle.bold()).fontDesign(.serif)
                        MarkPageView(side: .left, height: size * 1.4).rotation3DEffect(.degrees(opened ? 0 : 60), axis: (0, 1, 0), anchor: .trailing)
                    }
                    .frame(width: fold.minX, alignment: .trailing)
                    Color.clear.frame(width: fold.width)
                    HStack(spacing: 12) {
                        MarkPageView(side: .right, height: size * 1.4).rotation3DEffect(.degrees(opened ? 0 : -60), axis: (0, 1, 0), anchor: .leading)
                        Text(split.1).font(.largeTitle.bold()).fontDesign(.serif)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .tabletop:
            if let fold = duo.division {
                VStack(spacing: 0) {
                    BrandMark(size: size * 1.3).frame(height: fold.minY).scaleEffect(opened ? 1 : 0.9)
                    Color.clear.frame(height: fold.height)
                    VStack(spacing: 6) { name }.frame(maxHeight: .infinity)
                }
            }
        case .closed, .flat:
            VStack(spacing: 16) {
                BrandMark(size: size).scaleEffect(opened ? 1 : 0.9)
                name
            }
        }
    }

    private var name: some View {
        VStack(spacing: 6) {
            Text(Brand.name).font(.largeTitle.bold()).fontDesign(.serif)
            Text(Brand.tagline).font(.subheadline).foregroundStyle(.secondary)
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
