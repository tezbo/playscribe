import SwiftUI

/// 0.5.6 (Mac walk at 1c5ebfc, steps 5 and 6): a pose change rebuilds the page with a different width and different parts
/// (Closed stacks All updates into the page; side by side puts it in the other pane), so a saved pixel offset lands somewhere
/// else, or at the top. The reading place is saved as the section the reader is in instead, and restored to that section's top.
enum ReadingPlace {
    /// Where each marked section's top sits in the scroll view's visible coordinates, updated as the reader scrolls.
    /// A plain reference box, not observed state: writing state every frame re-rendered the page (Terry, 0.2.0).
    final class Marks { var tops: [String: CGFloat] = [:] }

    /// The section the reader is in: of the sections whose top is at or above the top of the view, the lowest one.
    /// None when the reader is above the first marked section.
    static func current(_ tops: [String: CGFloat], slack: CGFloat = 1) -> String? {
        nil
    }

    /// The anchor string kept in `nav.anchors`.
    static func encode(_ mark: String) -> String { "mark:" + mark }

    /// The section an anchor names, or nil for an older pixel offset.
    static func mark(_ anchor: String?) -> String? {
        nil
    }
}

private struct ReadingMarksKey: EnvironmentKey { static let defaultValue: ReadingPlace.Marks? = nil }
extension EnvironmentValues {
    var readingMarks: ReadingPlace.Marks? {
        get { self[ReadingMarksKey.self] }
        set { self[ReadingMarksKey.self] = newValue }
    }
}

extension View {
    /// A section the reading place can return to. Inside a page that keeps a reading place it reports where its top is;
    /// elsewhere it is only an id.
    func readingMark(_ id: String) -> some View { modifier(ReadingMark(id: id)) }
}

private struct ReadingMark: ViewModifier {
    @Environment(\.readingMarks) private var marks
    var id: String
    func body(content: Content) -> some View {
        content
            .id(id)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .scrollView(axis: .vertical)).minY } action: { marks?.tops[id] = $0 }
    }
}
