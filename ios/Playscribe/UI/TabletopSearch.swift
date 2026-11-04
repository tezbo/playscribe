import SwiftUI

/// First-letter filtering for Tabletop, where the keyboard never opens (Iris, 0.2.0 ruling): the
/// system keyboard would cover the whole lower half, and a field above it would sit in the hinge band.
enum LetterIndex {
    static let letters: [String] = (65...90).compactMap { UnicodeScalar($0).map { String($0) } } + ["#"]

    /// Does `name` start with `letter`? "#" is anything that does not start with A to Z.
    static func matches(_ name: String, _ letter: String) -> Bool {
        let first = PS5Index.fold(name).first.map { String($0).uppercased() } ?? "#"
        let isLetter = first.count == 1 && first >= "A" && first <= "Z"
        return letter == "#" ? !isLetter : first == letter
    }
}

/// The Tabletop stand-in for a search field: a read-only 44 pt button that explains itself, then an
/// A to Z and "#" strip of 44 pt chips. Tapping a letter filters; tapping it again clears.
struct TabletopSearch: View {
    @Binding var letter: String?
    var prompt = "Search"
    @State private var hintShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { hintShown.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    Text(letter.map { "Titles starting with \($0)" } ?? prompt).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(PlayscribeColor.ink700, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tabletopSearch")
            .accessibilityLabel(prompt)
            .accessibilityHint("Typing needs the flat screen")
            .tappableFrame()
            if hintShown {
                Text("Typing needs the flat screen. Pick a letter below, or open your Duo flat to type.")
                    .font(PlayscribeFont.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("tabletopSearchHint")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(LetterIndex.letters, id: \.self) { l in
                        let on = letter == l
                        Button { letter = on ? nil : l } label: {
                            Text(l).font(PlayscribeFont.headline)
                                .foregroundStyle(on ? PlayscribeColor.onAccent : PlayscribeColor.textPrimary)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(on ? PlayscribeColor.accent : PlayscribeColor.ink700))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("letter-\(l)")
                        .accessibilityLabel("Titles starting with \(l)")
                        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                        .tappableFrame()
                    }
                }
            }
        }
    }
}
