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
/// Add game composes the pieces itself so the button shares the "Add as" row (0.2.0 gate: three rows).
struct TabletopSearch: View {
    @Binding var letter: String?
    var prompt = "Search"
    @State private var hintShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TabletopSearchButton(letter: letter, prompt: prompt, hintShown: $hintShown)
            TabletopSearchHint(shown: hintShown)
            TabletopLetterStrip(letter: $letter)
        }
    }
}

struct TabletopSearchButton: View {
    var letter: String?
    var prompt: String
    @Binding var hintShown: Bool

    var body: some View {
        Button { hintShown.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text(letter.map { "Starting with \($0)" } ?? prompt).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(PlayscribeRole.chipFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tabletopSearch")
        .accessibilityLabel(prompt)
        .accessibilityHint("Typing needs the flat screen")
        .tappableFrame()
    }
}

struct TabletopSearchHint: View {
    var shown: Bool
    var body: some View {
        if shown {
            Text("Typing needs the flat screen. Pick a letter below, or open your Duo flat to type.")
                .font(PlayscribeFont.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("tabletopSearchHint")
        }
    }
}

struct TabletopLetterStrip: View {
    @Binding var letter: String?
    /// The chip grows with the text size, so a letter at AX5 sits inside its own circle instead of running into the next one.
    @ScaledMetric(relativeTo: .headline) private var chip: CGFloat = 44

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(LetterIndex.letters, id: \.self) { l in
                    let on = letter == l
                    Button { letter = on ? nil : l } label: {
                        Text(l).font(PlayscribeFont.headline)
                            .foregroundStyle(on ? PlayscribeRole.onAction : PlayscribeRole.textPrimary)
                            .frame(width: chip, height: chip)
                            .background(Circle().fill(on ? PlayscribeRole.action : PlayscribeRole.chipFill))
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
