import SwiftUI

/// What a verification tag means (0.5.0, Iris): name, one plain sentence, and the ladder in order of
/// confidence with the current one marked. No source names, URLs or links. Copy is Ezra's; the strings
/// here are placeholders until handoff/0.5.0 lands.
extension Verification {
    /// The tags a reader can ever see; pending and assumed never show a tag.
    static let ladder: [Verification] = [.official, .reported, .pending, .assumed]

    var tagName: String {
        switch self {
        case .official: "Official"
        case .reported: "Reported"
        case .pending: "Not confirmed yet"
        case .assumed: "Taken as out"
        }
    }

    var meaning: String {
        switch self {
        case .official: "Confirmed against an official post that names this platform."
        case .reported: "Reported by the press, not yet confirmed by an official post."
        case .pending: "Found automatically and waiting for someone to confirm it."
        case .assumed: "No word on PS5 yet, so it is treated as out on PS5 too."
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
                Text(kind.tagName).font(PlayscribeFont.title3)
                Spacer()
                Button("Done") { if let panelClose { panelClose() } else { systemDismiss() } }
                    .frame(minHeight: 44).accessibilityIdentifier("close").tappableFrame()
            }
            .frame(minHeight: 52)
            Text(kind.meaning).font(PlayscribeFont.body)
            Text("From most to least sure").font(PlayscribeFont.footnote).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Verification.ladder, id: \.self) { v in
                    HStack(spacing: 8) {
                        Image(systemName: v == kind ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(v == kind ? PlayscribeColor.accent : .secondary)
                        Text(v.tagName).font(PlayscribeFont.subheadline.weight(v == kind ? .semibold : .regular))
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
