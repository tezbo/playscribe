import SwiftUI
import PhotosUI
import Vision

/// From a photo: pick a picture of a shelf, a store page or a screen, read the text on the device
/// (Vision, no network) and hand the lines to the shared results list. Picking needs no permission.
enum PhotoReader {
    /// Text lines in reading order, longest noise filtered out. Throws only on a decode failure.
    static func lines(in data: Data) async throws -> [String] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: data)
        return observations
            .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 && $0.count <= 60 }
    }
}

struct PhotoAddView: View {
    var find: ([String]) -> Void
    var typeInstead: () -> Void
    @State private var item: PhotosPickerItem?
    @State private var working = false
    @State private var failed = false
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            #if INTERNAL
            if BuildChannel.showsInternalTools, model.qaStoreSet {
                PhotoSampleResult(titles: ["Pale Harbour Lanterns", "Tin Orchard Road", "Quiet Kite Season"], add: find)
            }
            #endif
            Spacer(minLength: 0)   // centred in the sheet, so a tall screen does not leave its lower half empty
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 44)).foregroundStyle(PlayscribeColor.accent)
                .accessibilityHidden(true)
            Text("Choose a photo with game titles on it.")
                .font(PlayscribeFont.headline).multilineTextAlignment(.center)
            Text("The text is read on your device. The photo is never uploaded.")
                .font(PlayscribeFont.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            PhotosPicker(selection: $item, matching: .images) {
                Text(working ? "Reading" : "Choose photo")
                    .font(PlayscribeFont.headline)
                    .foregroundStyle(PlayscribeColor.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(PlayscribeColor.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(working)
            .tappableFrame()
            if failed {
                Text("No game titles found in that photo.").font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
                Button("Type it", action: typeInstead).hitTarget()
            }
            Spacer()
        }
        .padding(16)
        .onChange(of: item) { _, new in
            guard let new else { return }
            Task { await read(new) }
        }
    }

    private func read(_ new: PhotosPickerItem) async {
        working = true; failed = false
        defer { working = false; item = nil }
        guard let data = try? await new.loadTransferable(type: Data.self),
              let lines = try? await PhotoReader.lines(in: data), !lines.isEmpty else { failed = true; return }
        find(lines)
    }
}

#if INTERNAL
/// Store-set capture only: a sample photo with the titles read from it, so the From a photo shot fills the page.
/// Invented titles; the real flow shows results in the shared list after a photo is picked.
private struct PhotoSampleResult: View {
    var titles: [String]
    var add: ([String]) -> Void
    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<9, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(LinearGradient(colors: [Color.ink0.opacity(0.4), PlayscribeColor.accent.opacity(0.35 + 0.05 * Double(i % 4))], startPoint: .top, endPoint: .bottom))
                        .frame(height: 70 + CGFloat((i * 13) % 34))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .bottom)
            .background(Color.ink0.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityHidden(true)
            Text("Found \(titles.count) titles").font(PlayscribeFont.headline)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(titles, id: \.self) { t in
                    Label(t, systemImage: "checkmark.circle.fill").font(PlayscribeFont.body)
                        .foregroundStyle(PlayscribeColor.textPrimary).symbolRenderingMode(.hierarchical)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { add(titles) } label: {
                Text("Add \(titles.count) games").font(PlayscribeFont.headline).foregroundStyle(PlayscribeColor.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(PlayscribeColor.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .tappableFrame()
        }
    }
}
#endif
