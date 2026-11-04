import SwiftUI

/// Share an update as a card (0.5.0 item 20): a 4:5 picture of the game's art, name, update and
/// three top changes, rendered on the device and handed to the system share sheet. No source names,
/// no addresses on the card.
struct ShareCard: View {
    var gameName: String
    var updateName: String
    var version: String?
    var changes: [String]
    var art: UIImage

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
            Image(uiImage: art).resizable().scaledToFill()
                .frame(width: 1080, height: 1350).clipped()
            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.55), .black.opacity(0.92)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 20) {
                Text(gameName).font(.custom("Literata24pt-SemiBold", size: 76)).lineLimit(3)
                Text([updateName, version].compactMap { $0 }.joined(separator: " ")).font(.custom("Literata24pt-SemiBold", size: 44))
                    .foregroundStyle(PlayscribeColor.ember300)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(changes.prefix(3), id: \.self) { Text($0).font(.system(size: 36)).lineLimit(2) }
                }
                .padding(.top, 8)
                Text("The story of every update").font(.custom("Literata24pt-SemiBold", size: 30))
                    .foregroundStyle(PlayscribeColor.textSecondary).padding(.top, 16)
            }
            .foregroundStyle(PlayscribeColor.textPrimary)
            .padding(72)
        }
        .frame(width: 1080, height: 1350)
    }
}

extension AppModel {
    /// Up to three lines: the release's key changes, else the first lines of its PS5 notes.
    func shareChanges(_ r: Release) -> [String] {
        if let top = r.digest?.topNew, !top.isEmpty { return Array(top.prefix(3)) }
        if let k = r.keyChanges, !k.isEmpty { return Array(k.prefix(3).map { LinkedText.clean($0) }) }
        return Array(r.notes.flatMap(\.items).filter { !$0.isPCOnly }.map { LinkedText.clean($0.text) }
            .filter { !$0.isEmpty && $0.count <= 120 }.prefix(3))
    }

    @MainActor func shareCardImage(for r: Release) -> UIImage? {
        let game = game(r.gameID)
        let art = game?.keyArtAsset.flatMap { UIImage(named: $0) } ?? UIImage(named: "default-header-tall")
        guard let art else { return nil }
        let card = ShareCard(gameName: game?.name ?? "", updateName: r.displayName, version: r.ps5Version,
                             changes: shareChanges(r), art: art)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        return renderer.uiImage
    }

    func shareText(_ r: Release) -> String {
        let name = game(r.gameID)?.name ?? ""
        let first = shareChanges(r).first.map { ": \($0)." } ?? "."
        return "\(name) \(r.ps5Version ?? r.displayName)\(first)"
    }
}

struct ShareUpdateButton: View {
    @Environment(AppModel.self) private var model
    var release: Release
    @State private var image: Image?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                ShareLink(item: image, message: Text(model.shareText(release)),
                          preview: SharePreview(model.game(release.gameID)?.name ?? "Update", image: image)) {
                    Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                }
            } else if failed {
                Button("Retry") { render() }.font(PlayscribeFont.footnote).frame(minHeight: 44)
                    .accessibilityHint("Couldn't make the card. Try again.")
            } else {
                ProgressView().frame(width: 44, height: 44).accessibilityLabel("Making your card")
            }
        }
        .tappableFrame()
        .accessibilityLabel("Share update")
        .accessibilityHint("Opens the share sheet with a card")
        .task(id: release.id) { render() }
    }

    private func render() {
        failed = false
        if let ui = model.shareCardImage(for: release) { image = Image(uiImage: ui) } else { failed = true }
    }
}
