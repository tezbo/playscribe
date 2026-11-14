import SwiftUI

/// What a verification tag means (0.5.0, Iris): name, one plain sentence, and the ladder in order of
/// confidence with the current one marked. No source names, URLs or links. Copy is Ezra's; the strings
/// here are placeholders until handoff/0.5.0 lands.
extension Verification {
    /// The tags a reader can ever see; pending and assumed never show a tag.
    static let ladder: [Verification] = [.official, .reported, .pending]

    var tagName: String {
        switch self {
        case .official: "Official"
        case .reported: "Reported"
        case .pending: "Pending"
        case .assumed: "Pending" // never shown as a tag; "Assumed" has no copy
        }
    }

    var meaning: String {
        switch self {
        case .official: "This comes from the people who make the game or the console, in their own announcement."
        case .reported: "Independent outlets reported this. It did not come from the game’s makers."
        case .pending, .assumed: "Not confirmed yet. Playscribe will update this when it is."
        }
    }
}

/// A verification tag that opens the explainer. 44 pt tap target (G-7).
struct VerificationTag: View {
    @Environment(AppModel.self) private var model
    var kind: Verification

    var body: some View {
        Button { model.tagExplainer = kind } label: {
            Tag(text: kind.tagName).frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(kind.tagName)
        .accessibilityHint("Double tap to learn what this means")
        .tappableFrame()
    }
}

struct VerificationExplainer: View {
    @Environment(\.panelClose) private var panelClose
    @Environment(\.dismiss) private var systemDismiss
    var kind: Verification

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("What this tag means").font(PlayscribeFont.title3)
                Spacer()
                // The 44 pt frame and its hit shape sit inside the label, so the button's own frame is 44 pt tall.
                Button { if let panelClose { panelClose() } else { systemDismiss() } } label: {
                    Text("Done").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityHint("Closes the explainer").accessibilityIdentifier("close").tappableFrame()
            }
            .frame(minHeight: 52)
            Text(kind.tagName).font(PlayscribeFont.headline)
            Text(kind.meaning).font(PlayscribeFont.body)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Verification.ladder, id: \.self) { v in
                    HStack(spacing: 8) {
                        Image(systemName: v == kind ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(v == kind ? PlayscribeColor.accent : .secondary)
                        Text(v.tagName).font(PlayscribeFont.subheadline.weight(v == kind ? .semibold : .regular))
                        if v == kind { Text("This one").font(PlayscribeFont.footnote).foregroundStyle(.secondary) }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(v == kind ? .isSelected : [])
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .accessibilityIdentifier("verificationExplainer")
    }
}

extension Verification: Identifiable { var id: String { rawValue } }
