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
    /// False when the game has no key art of its own: the card gets a designed ground and a centred
    /// title block instead of an empty top half.
    var hasArt = true

    var body: some View {
        ZStack(alignment: hasArt ? .bottomLeading : .leading) {
            Color.black
            Image(uiImage: art).resizable().scaledToFill()
                .frame(width: 1080, height: 1350).clipped()
            if !hasArt {
                RadialGradient(colors: [PlayscribeColor.ember300.opacity(0.28), .clear],
                               center: .center, startRadius: 0, endRadius: 900)
            }
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
        let raw: [String]
        if let top = r.digest?.topNew, !top.isEmpty { raw = top }
        else if let k = r.keyChanges, !k.isEmpty { raw = k }
        else {
            raw = r.notes.flatMap(\.items).filter { !$0.isPCOnly }.map(\.text)
                .filter { ShareText.line($0).count <= 120 }
        }
        return Array(raw.map(ShareText.line).filter { !$0.isEmpty }.prefix(3))
    }

    @MainActor func shareCardImage(for r: Release) -> UIImage? {
        let game = game(r.gameID)
        let own = game?.keyArtAsset.flatMap { UIImage(named: $0) }
        guard let art = own ?? UIImage(named: "default-header-tall") else { return nil }
        let card = ShareCard(gameName: gameDisplayName(r.gameID), updateName: r.displayName, version: r.ps5Version,
                             changes: shareChanges(r), art: art, hasArt: own != nil)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        return renderer.uiImage
    }

    /// Message beside the card: one title line, the top change, then a link that opens this update in
    /// Playscribe (universal link, with a web fallback page). No blank gaps, no doubled full stops.
    func shareText(_ r: Release) -> String {
        let name = gameDisplayName(r.gameID)
        var lines = ["\(name) \(r.ps5Version ?? r.displayName)".trimmingCharacters(in: .whitespaces)]
        if let first = shareChanges(r).first { lines.append(first.hasSuffix(".") || first.hasSuffix("!") || first.hasSuffix("?") ? first : first + ".") }
        if let url = ShareText.link(gameID: r.gameID, releaseID: r.id) { lines.append(url.absoluteString) }
        return lines.joined(separator: "\n")
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
                          preview: SharePreview(model.gameDisplayName(release.gameID).nonEmpty ?? "Update", image: image)) {
                    // Same disc and weight as the rail's other buttons (Quinn: it looked paler, as if disabled).
                    Image(systemName: "square.and.arrow.up")
                        // Fixed 22 pt glyph inside the 44 pt disc: it never scales past the rail icons at AX (Iris).
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Color.primary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(PlayscribeColor.ink800).overlay(Circle().fill(.regularMaterial)).overlay(Circle().strokeBorder(Color.primary.opacity(0.5), lineWidth: 1.5)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(RailPressStyle())
            } else if failed {
                Button { render() } label: { Text("Retry").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }.font(PlayscribeFont.footnote)
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

/// Share wording helpers (kept pure so they are unit-testable).
extension String { fileprivate var nonEmpty: String? { isEmpty ? nil : self } }

enum ShareText {
    static let host = "playscribe.codeconnectors.co"

    /// One tidy line: markup stripped, whitespace and newlines collapsed, no doubled full stops.
    static func line(_ raw: String) -> String {
        var s = LinkedText.clean(raw)
        s = s.replacingOccurrences(of: #"\[/?[A-Za-z*][^\]]*\]"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"([.!?])\.+"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\.{2,}"#, with: ".", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func link(gameID: String, releaseID: String) -> URL? {
        var c = URLComponents()
        c.scheme = "https"; c.host = host
        c.percentEncodedPath = "/r/" + [gameID, releaseID].map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? $0 }.joined(separator: "/")
        return c.url
    }
}
