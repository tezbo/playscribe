import SwiftUI

/// R-7 (0.5.6): Companion, the World and Tips entries in one section, with a World / Tips filter only when the game has both
/// kinds. In Tabletop the section sits on the view-only standing half (G-4), so the filter is in the lower half under the
/// section bar (ContentsView) and drives what the stage shows.
struct EntriesChapter: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    var gameID: String

    var body: some View {
        let entries = model.companionEntries(gameID)
        var sections: [String] = []
        for e in entries where !sections.contains(e.section) { sections.append(e.section) }
        return VStack(alignment: .leading, spacing: 14) {
            if duo.pose != .tabletop { CompanionFilter(gameID: gameID) }
            ForEach(sections, id: \.self) { sec in
                SectionHeader(title: sec).id("sec-\(sec)")
                ForEach(entries.filter { $0.section == sec }) { EntryCard(entry: $0).id("entry-\($0.id)") }
            }
        }
    }
}

struct EntryCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.viewOnlyStage) private var viewOnly
    var entry: BookEntry

    var body: some View {
        let marked = model.isBookmarked(kind: .entry, id: entry.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.title).font(PlayscribeFont.headline)
                if entry.verification == "illustrative" { Tag(text: "Illustrative", tint: .ember) }
                Spacer()
                // Tabletop's stage is view only: no glyph at all here; the rail's Bookmarks menu does it (design, #521).
                if !viewOnly {
                    Button { model.toggleBookmark(kind: .entry, id: entry.id, gameID: entry.gameID) } label: {
                        Image(systemName: marked ? "bookmark.fill" : "bookmark").hitTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(marked ? "Remove bookmark: \(entry.title)" : "Bookmark \(entry.title)")
                    .tappableFrame()
                }
            }
            if entry.spoiler {
                SpoilerText(text: entry.body, gameID: entry.gameID, key: "entry:\(entry.id)")
            } else {
                Text(entry.body)
            }
        }
        .padding(14)
        .background(PlayscribeRole.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// One Official videos row: the thumbnail, with a play badge when it plays in the app (Iris on #551), and the title.
struct GalleryVideoRow: View {
    var item: GalleryItem
    var playable: Bool
    var body: some View {
        HStack(spacing: 12) {
            Image(item.asset).resizable().scaledToFill().frame(width: 96, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    if playable {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(.black.opacity(0.6), in: Circle())
                            .accessibilityHidden(true)
                    }
                }
            Text(item.title).font(PlayscribeFont.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}

struct GalleryChapter: View {
    @Environment(AppModel.self) private var model
    @Environment(\.viewOnlyStage) private var viewOnly
    var gameID: String

    var body: some View {
        let items = model.gallery(gameID)
        let art = items.filter { $0.kind == .artwork }
        let videos = items.filter { $0.kind == .video }
        let picked = model.data.selectedArtwork[gameID]
        if viewOnly, !items.isEmpty {
            // Tabletop (Terry's Duo, 21 Nov: the stage was a dead copy of the list below it). The play rows are in the lower
            // half, so the stage shows the game's art and name (GalleryStage).
            GalleryStage(gameID: gameID)
        } else {
            list(items: items, art: art, videos: videos, picked: picked)
        }
    }

    private func list(items: [GalleryItem], art: [GalleryItem], videos: [GalleryItem], picked: String?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if items.isEmpty { GalleryEmpty(gameID: gameID) }
            if !art.isEmpty { Text("Choose a picture to use as this game’s backdrop.").font(PlayscribeFont.footnote).foregroundStyle(.secondary) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(art) { item in
                    Button { model.selectArtwork(gameID, item.id) } label: {
                        Image(item.asset).resizable().scaledToFill()
                            .frame(height: 96).frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(alignment: .bottomLeading) {
                                Label(item.title, systemImage: picked == item.id ? "checkmark.circle.fill" : "")
                                    .labelStyle(.titleAndIcon)
                                    .font(PlayscribeFont.caption2.weight(.semibold))
                                    .padding(6).background(.ultraThinMaterial, in: Capsule()).padding(6)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.alt)
                    .accessibilityAddTraits(picked == item.id ? .isSelected : [])
                    .tappableFrame()
                    .id("gal-\(item.id)")
                }
            }
            if !videos.isEmpty {
                SectionHeader(title: "Official videos")
                ForEach(videos) { v in
                    if v.youtubeID != nil {
                        // Plays in the app's own player (R-11), never handed to YouTube (Terry, 19 Nov).
                        Button { model.playGalleryVideo(v) } label: { GalleryVideoRow(item: v, playable: true) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(v.title), video")
                            // The same id as Tabletop's lower-panel row, so QA finds a Gallery video in every pose (Iris on #554).
                            // Not on Tabletop's view-only stage, where the lower panel's row carries it.
                            .accessibilityIdentifier(viewOnly ? "" : "galleryPlay-\(v.id)")
                            .tappableFrame()
                    } else {
                        // Nothing to play: not a button (Iris on #551), so a tap never does nothing.
                        GalleryVideoRow(item: v, playable: false)
                    }
                }
            }
        }
    }
}

/// TT-1, R-10 and R-11: the Gallery on Tabletop's view-only stage (Iris, reflection-0.6 spec section 6; Terry's Duo, 21 Nov: the
/// stage was a list that looked tappable and wasn't, and the same videos were listed again below). The stage is a picture: the
/// game's art at 16:9 with its name, never a list. Every video and picture is a row in the lower half (`TabletopGalleryList`).
struct GalleryStage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    /// The card's top edge in the container's space, where the division is reported.
    @State private var top: CGFloat = 0
    @State private var width: CGFloat = 0
    var gameID: String

    /// Clear of the fold under the card.
    static let foldGap: CGFloat = 12

    /// The tallest the card may be so it ends above the fold; never under 90 pt.
    static func maxHeight(top: CGFloat, foldTop: CGFloat?) -> CGFloat {
        guard let foldTop else { return .infinity }
        return max(90, foldTop - top - foldGap)
    }

    var body: some View {
        let game = model.game(gameID)
        // One card, the name on it (Mac at 7f61fac9: a name under the card was cut by the fold at std and gone at AX5). The card
        // is 16:9, made smaller when the stage is short, so it always ends above the fold.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: min(width * 9 / 16, Self.maxHeight(top: top, foldTop: duo.division?.minY)))
            .overlay { ArtView(asset: model.backdrop(gameID, chapter: .gallery, tall: false), game: game) }
            .overlay(alignment: .bottomLeading) {
                if let game {
                    Text(game.name.gluingTrailingNumeral)
                        .font(PlayscribeFont.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient(colors: [.black.opacity(0), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(DuoContext.space)).minY } action: { top = $0 }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(game?.name ?? "")
            .allowsHitTesting(false)
    }
}

/// A game with no pictures or videos (Terry, 0.2.0 build 5, Fortnite): say so, and offer the official website when there is one.
/// No "Find trailers online" (0.6.0, Iris and Nadia): it was a YouTube search, and every video now plays in our own player
/// (Terry, 20 Nov), so a game with no trailer simply has no trailer row.
struct GalleryEmpty: View {
    @Environment(AppModel.self) private var model
    @Environment(\.duo) private var duo
    var gameID: String

    var body: some View {
        let game = model.game(gameID)
        let links = game?.igdbID.flatMap { GameInfoStore.shared.basics[$0] }?.links
        VStack(alignment: .leading, spacing: 8) {
            if duo.pose == .tabletop {
                // The stage is view-only and cannot scroll: one sentence, no headline and no grey stand-in rows that look like
                // buttons, so it fits in three lines at AX5 (Mac, 0a7830d). The controls are on the Links panel; the rail shows an
                // ellipsis, not the word "More", so the line names what the person sees (Iris, 12 Nov).
                Text("No pictures or videos here yet.").font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
            } else {
                Text("No pictures or videos here yet").font(PlayscribeFont.headline)
                if let url = links?.official {
                    Link(destination: url) { Label("Official website", systemImage: "arrow.up.right.square").frame(minHeight: 44).contentShape(Rectangle()) }
                        .tappableFrame()
                        .font(PlayscribeFont.subheadline).foregroundStyle(PlayscribeRole.action)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct MyBookChapter: View {
    @Environment(AppModel.self) private var model
    var gameID: String
    @State private var editing: String?
    @State private var editText = ""

    var body: some View {
        let marks = model.data.bookmarks.filter { $0.gameID == gameID }
        let notes = model.data.notes.filter { $0.gameID == gameID }
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Bookmarks").id("mybook-marks")
            if marks.isEmpty { Text("Bookmark an update or an entry and it appears here.").foregroundStyle(.secondary) }
            ForEach(marks, id: \.id) { b in
                let title = b.kind == .release ? model.release(gameID, b.id)?.displayName : model.fixtures.book.first { $0.id == b.id }?.title
                HStack {
                    Button {
                        if b.kind == .release { model.openGame(gameID, chapter: .updates, releaseID: b.id) }
                        else if let e = model.fixtures.book.first(where: { $0.id == b.id }) { model.openEntry(e) }
                    } label: {
                        Label(title ?? "Removed item", systemImage: b.kind == .release ? "list.bullet.rectangle.portrait" : "bookmark")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tappableFrame()
                    Button { model.toggleBookmark(kind: b.kind, id: b.id, gameID: gameID) } label: { Image(systemName: "xmark").hitTarget() }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove bookmark: \(title ?? "item")")
                }
            }

            SectionHeader(title: "Notes").id("mybook-notes")
            TextField("Write a note: a build to try, where you left off…",
                      text: Binding(get: { model.nav.noteDraft[gameID] ?? "" }, set: { model.nav.noteDraft[gameID] = $0 }),
                      axis: .vertical)
                .lineLimit(3...8)
                .textFieldStyle(.roundedBorder)
            Button("Save note") {
                let text = (model.nav.noteDraft[gameID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                model.saveNote(Note(id: "n-\(Int(Date.now.timeIntervalSince1970 * 1000))", gameID: gameID, text: text, updatedAt: .now))
                model.nav.noteDraft[gameID] = ""
            }
            .buttonStyle(.borderedProminent).foregroundStyle(PlayscribeRole.onAction)
            .disabled((model.nav.noteDraft[gameID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .hitTarget()

            ForEach(notes) { n in
                VStack(alignment: .leading, spacing: 8) {
                    if editing == n.id {
                        TextField("Edit note", text: $editText, axis: .vertical).textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Cancel") { editing = nil }.hitTarget()
                            Button("Save") {
                                var copy = n
                                copy.text = editText.isEmpty ? n.text : editText
                                copy.updatedAt = .now
                                model.saveNote(copy)
                                editing = nil
                            }
                            .buttonStyle(.borderedProminent).foregroundStyle(PlayscribeRole.onAction).hitTarget()
                        }
                    } else {
                        Text(n.text)
                        HStack {
                            Text(n.updatedAt.formatted(date: .abbreviated, time: .shortened)).font(PlayscribeFont.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button { editing = n.id; editText = n.text } label: { Image(systemName: "pencil").hitTarget() }
                                .accessibilityLabel("Edit note")
                            Button { model.deleteNote(n.id) } label: { Image(systemName: "trash").hitTarget() }
                                .accessibilityLabel("Delete note")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(PlayscribeRole.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .id("note-\(n.id)")
            }
        }
    }
}
