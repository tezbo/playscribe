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

    var body: some View {
        VStack(spacing: 16) {
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
