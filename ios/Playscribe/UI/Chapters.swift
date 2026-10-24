import SwiftUI

struct EntriesChapter: View {
    @Environment(AppModel.self) private var model
    var gameID: String
    var chapter: Chapter

    var body: some View {
        let entries = model.fixtures.book.filter { $0.gameID == gameID && $0.chapter.rawValue == chapter.rawValue }
        var sections: [String] = []
        for e in entries where !sections.contains(e.section) { sections.append(e.section) }
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(sections, id: \.self) { sec in
                SectionHeader(title: sec).id("sec-\(sec)")
                ForEach(entries.filter { $0.section == sec }) { EntryCard(entry: $0).id("entry-\($0.id)") }
            }
        }
    }
}

struct EntryCard: View {
    @Environment(AppModel.self) private var model
    var entry: BookEntry

    var body: some View {
        let marked = model.isBookmarked(kind: .entry, id: entry.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.title).font(PlayscribeFont.headline)
                if entry.verification == "illustrative" { Tag(text: "Illustrative", tint: .ember) }
                Spacer()
                Button { model.toggleBookmark(kind: .entry, id: entry.id, gameID: entry.gameID) } label: {
                    Image(systemName: marked ? "bookmark.fill" : "bookmark").hitTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(marked ? "Remove bookmark: \(entry.title)" : "Bookmark \(entry.title)")
                .tappableFrame()
            }
            if entry.spoiler {
                SpoilerText(text: entry.body, gameID: entry.gameID, key: "entry:\(entry.id)")
            } else {
                Text(entry.body)
            }
        }
        .padding(14)
        .background(Color.ink2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct GalleryChapter: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    var gameID: String

    var body: some View {
        let items = model.gallery(gameID)
        let art = items.filter { $0.kind == .artwork }
        let videos = items.filter { $0.kind == .video }
        let picked = model.data.selectedArtwork[gameID]
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose a picture to use as this game's backdrop.").font(PlayscribeFont.footnote).foregroundStyle(.secondary)
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
                    Button { if let s = v.href, let u = URL(string: s) { openURL(u) } } label: {
                        HStack(spacing: 12) {
                            Image(v.asset).resizable().scaledToFill().frame(width: 96, height: 54).clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading) {
                                Text(v.title).font(PlayscribeFont.subheadline.weight(.semibold))
                                Text("Opens in YouTube").font(PlayscribeFont.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tappableFrame()
                }
            }
        }
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
                        else if let e = model.fixtures.book.first(where: { $0.id == b.id }) {
                            let ch: Chapter = e.chapter == .world ? .world : .companion
                            model.nav.chapter = ch
                            model.nav.anchors[AppModel.bookKey(gameID, ch)] = "entry-\(e.id)"
                        }
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
            .buttonStyle(.borderedProminent).foregroundStyle(PlayscribeColor.onAccent)
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
                            .buttonStyle(.borderedProminent).foregroundStyle(PlayscribeColor.onAccent).hitTarget()
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
                .background(Color.ink2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .id("note-\(n.id)")
            }
        }
    }
}
