import SwiftUI
import AVFoundation
import VisionKit

/// Scan with camera: live text recognition (VisionKit, on device) over game cases or a shelf.
/// Titles collect as they are seen; "Find these games" hands them to the shared results list.
/// Camera access is asked for only when this row is chosen, after saying why.
struct CameraAddView: View {
    @Environment(AppModel.self) private var model
    var find: ([String]) -> Void
    var typeInstead: () -> Void
    /// Off state (offline/empty/error copy 8): "From a photo" beside "Type it".
    var photoInstead: (() -> Void)?
    @State private var seen: [String] = []
    @State private var access: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    private var simulated: Bool { model.simulatedScan }
    private var supported: Bool { simulated || (DataScannerViewController.isSupported && DataScannerViewController.isAvailable) }

    var body: some View {
        VStack(spacing: 12) {
            if !supported || (!simulated && (access == .denied || access == .restricted)) {
                unavailable.onAppear { Haptics.warning() }
            } else if !simulated && access == .notDetermined {
                VStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder").font(.system(size: 44)).foregroundStyle(PlayscribeRole.action)
                        .accessibilityHidden(true)
                    Text("Let Playscribe see your games").font(PlayscribeFont.headline).multilineTextAlignment(.center)
                    Text("Playscribe reads the titles on boxes and shelf spines on your phone, then asks you which ones to add.")
                        .font(PlayscribeFont.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button {
                        Task { _ = await AVCaptureDevice.requestAccess(for: .video); access = AVCaptureDevice.authorizationStatus(for: .video) }
                    } label: {
                        Text("Continue").font(PlayscribeFont.headline).foregroundStyle(PlayscribeRole.onAction)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(PlayscribeRole.action, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain).tappableFrame()
                    .accessibilityHint("Shows the system permission request")
                    Button("Not now", action: typeInstead).hitTarget()
                    Spacer()
                }
                .padding(16)
            } else {
                // J-20b: the preview takes the height that is left (4:3 at most), so the hint and the
                // button below always fit the panel, whatever the size class or text size.
                Group {
                    if simulated {
                        // QA route add/scan: simulators have no camera, so a fixed feed stands in.
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(PlayscribeRole.surface)
                            .overlay { Image(systemName: "camera.viewfinder").font(.largeTitle).foregroundStyle(.secondary) }
                            .onAppear { seen = ["Hades", "Celeste", "Blue Prince"] }
                    } else {
                        ScannerView { seen = $0 } onNew: { Haptics.recognisedTitle() }.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .aspectRatio(4 / 3, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 96)
                .padding(.horizontal, 16)
                .accessibilityLabel("Camera view")
                Text(seen.isEmpty ? "Looking for titles" : "Seen \(seen.count) line\(seen.count == 1 ? "" : "s") of text")
                    .font(PlayscribeFont.subheadline).foregroundStyle(.secondary)
                Button { find(seen) } label: {
                    Text("Find these games").font(PlayscribeFont.headline).foregroundStyle(PlayscribeRole.onAction)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(PlayscribeRole.action.opacity(seen.isEmpty ? 0.4 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain).disabled(seen.isEmpty).tappableFrame().padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
        .padding(.top, 8)
    }

    private var unavailable: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill").font(.system(size: 44)).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(supported ? "Scan with camera is off" : "This device can't scan titles.")
                .font(PlayscribeFont.headline).multilineTextAlignment(.center)
            if supported {
                Text("You can turn on the camera for Playscribe in Settings, or pick a photo instead.")
                    .font(PlayscribeFont.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Button("Type it", action: typeInstead).hitTarget()
            if supported, let photoInstead { Button("From a photo", action: photoInstead).hitTarget() }
            if supported {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }.hitTarget()
            }
            Spacer()
        }
        .padding(16)
    }
}

private struct ScannerView: UIViewControllerRepresentable {
    var onChange: ([String]) -> Void
    var onNew: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange, onNew: onNew) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.text()], qualityLevel: .balanced,
                                           recognizesMultipleItems: true, isHighFrameRateTrackingEnabled: false,
                                           isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) { vc.stopScanning() }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onChange: ([String]) -> Void
        var onNew: () -> Void
        private var lines: [String] = []
        init(onChange: @escaping ([String]) -> Void, onNew: @escaping () -> Void) { self.onChange = onChange; self.onNew = onNew }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .text(let t) in addedItems {
                let line = t.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.count >= 3, line.count <= 60, !lines.contains(line) { lines.append(line); onNew() }
            }
            onChange(lines)
        }
    }
}
