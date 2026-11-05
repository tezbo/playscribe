import SwiftUI
import Speech
import AVFoundation

/// Say it: hold the button, say a few titles, release. Recognition runs on the device
/// (`requiresOnDeviceRecognition`), so nothing is sent anywhere.
@MainActor @Observable
final class SpeechCapture {
    var transcript = ""
    var listening = false
    var denied = false
    var unavailable = false

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() async {
        guard !listening else { return }
        guard await authorized() else { denied = true; return }
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { unavailable = true; return }
        denied = false; unavailable = false
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode
            Self.installTap(on: input, request: request)
            engine.prepare()
            try engine.start()
            listening = true
            Haptics.voiceEdge()
            task = recognizer.recognitionTask(with: request, resultHandler: Self.handler { [weak self] text, done in
                Task { @MainActor in self?.apply(text, done: done) }
            })
        } catch {
            stop()
            unavailable = true
        }
    }

    func stop() {
        guard listening || request != nil else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        if listening { Haptics.voiceEdge() }
        listening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func apply(_ text: String?, done: Bool) {
        if let text, !text.isEmpty { transcript = text }
        if done { task = nil }
    }

    private func authorized() async -> Bool {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    // The audio and recognition callbacks arrive on their own queues, so they are built outside
    // the main actor.
    nonisolated private static func installTap(on node: AVAudioInputNode, request: SFSpeechAudioBufferRecognitionRequest) {
        nonisolated(unsafe) let request = request
        node.installTap(onBus: 0, bufferSize: 1024, format: node.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func handler(_ report: @escaping @Sendable (String?, Bool) -> Void)
        -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            report(result?.bestTranscription.formattedString, result?.isFinal == true || error != nil)
        }
    }
}

struct SayItView: View {
    @State private var capture = SpeechCapture()
    var find: (String) -> Void
    var typeInstead: () -> Void
    /// The explainer comes before the system prompts, and only while neither is decided.
    @State private var explained = SFSpeechRecognizer.authorizationStatus() != .notDetermined

    var body: some View {
        VStack(spacing: 20) {
            if !explained {
                VStack(spacing: 12) {
                    Image(systemName: "mic.fill").font(.system(size: 44)).foregroundStyle(PlayscribeColor.accent)
                        .accessibilityHidden(true)
                    Text("Let Playscribe hear your list").font(PlayscribeFont.headline).multilineTextAlignment(.center)
                    Text("Playscribe turns your voice into game names on your phone. It only listens while you hold the button.")
                        .font(PlayscribeFont.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button { explained = true } label: {
                        Text("Continue").font(PlayscribeFont.headline).foregroundStyle(PlayscribeColor.onAccent)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(PlayscribeColor.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain).tappableFrame()
                    .accessibilityHint("Shows the system permission request")
                    Button("Not now", action: typeInstead).hitTarget()
                }
                .padding(.horizontal, 16).padding(.top, 24)
            } else if capture.denied || capture.unavailable {
                VStack(spacing: 12) {
                    Text(capture.denied ? "Say it is off" : "Speech isn't available on this device right now")
                        .font(PlayscribeFont.headline).multilineTextAlignment(.center)
                    if capture.denied {
                        Text("You can turn on the microphone and speech recognition for Playscribe in Settings.")
                            .font(PlayscribeFont.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    Button("Type it", action: typeInstead).hitTarget()
                    if capture.denied {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }.hitTarget()
                    }
                }
                .padding(.top, 24)
            } else {
                Text(capture.transcript.isEmpty ? "Hold the button and say a few titles, like Elden Ring and Astro Bot."
                     : capture.transcript)
                    .font(capture.transcript.isEmpty ? PlayscribeFont.subheadline : PlayscribeFont.title3)
                    .foregroundStyle(capture.transcript.isEmpty ? PlayscribeColor.textSecondary : PlayscribeColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .padding(.horizontal, 20)
                    .accessibilityLabel(capture.transcript.isEmpty ? "No titles heard yet" : capture.transcript)
            }
            Spacer(minLength: 0)
            if explained && !capture.denied && !capture.unavailable {
                Image(systemName: capture.listening ? "waveform" : "mic.fill")
                    .font(.title)
                    .foregroundStyle(PlayscribeColor.onAccent)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(capture.listening ? PlayscribeColor.accentPressed : PlayscribeColor.accent))
                    .scaleEffect(capture.listening ? 1.08 : 1)
                    .contentShape(Circle())
                    .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 60, pressing: { pressing in
                        if pressing { Task { await capture.start() } } else { capture.stop() }
                    }, perform: {})
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Hold to talk")
                    .accessibilityHint("Hold, say game titles, then release")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(named: capture.listening ? "Stop" : "Start") {
                        if capture.listening { capture.stop() } else { Task { await capture.start() } }
                    }
                    .tappableFrame()
                Button {
                    capture.stop()
                    find(capture.transcript)
                } label: {
                    Text("Find these games").font(PlayscribeFont.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
                .disabled(capture.transcript.isEmpty)
                .padding(.horizontal, 16)
                .tappableFrame()
            }
        }
        .padding(.bottom, 12)
        .onDisappear { capture.stop() }
    }
}
