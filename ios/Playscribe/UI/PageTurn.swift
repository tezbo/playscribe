import SwiftUI

/// r050-page-turn: in Book, a newly chosen update slides in from the spine over 0.35 s
/// (ease-out) with a soft spine-side shadow that fades. Reduce Motion: 0.2 s crossfade in
/// every pose. Other poses keep their current transition. Transform on the content only;
/// taps are ignored until it ends.
struct PageTurn: ViewModifier {
    @Environment(\.duo) private var duo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var key: String
    @State private var progress: Double = 1   // 0 = just arrived, 1 = settled
    @State private var busy = false

    private var active: Bool { reduceMotion || duo.pose == .book }

    func body(content: Content) -> some View {
        let p = progress
        let still = reduceMotion
        return content
            .visualEffect { view, proxy in
                view.offset(x: still ? 0 : -proxy.size.width * (1 - p))
            }
            .opacity(still ? p : 1)
            .overlay(alignment: .leading) {
                if !still {
                    LinearGradient(colors: [.black.opacity(0.35), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 28)
                        .opacity(1 - p)
                        .allowsHitTesting(false)
                }
            }
            .allowsHitTesting(!busy)
        .onChange(of: key) { old, _ in
            guard active, !old.isEmpty else { return }
            busy = true
            progress = 0
            let duration = reduceMotion ? 0.2 : 0.35
            withAnimation(.easeOut(duration: duration)) { progress = 1 }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(duration))
                busy = false
            }
        }
    }
}

extension View {
    func pageTurn(key: String) -> some View { modifier(PageTurn(key: key)) }
}
