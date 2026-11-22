import SwiftUI
import Speech
import AVFoundation

/// Say it: tap the microphone, say a few titles, and it stops by itself when you stop talking (tap again to stop
/// early). Terry, 22 Nov: hold-to-talk was an odd choice. Recognition runs on the device
/// (`requiresOnDeviceRecognition`), so nothing is sent anywhere.
@MainActor @Observable
final class SpeechCapture {
    var transcript = ""
    var listening = false
    var denied = false
    var unavailable = false
    /// Between the tap and the microphone opening (permission prompts included), so a second tap stops it.
    var starting = false

    @ObservationIgnored private lazy var silence = SilenceWatch { [weak self] in self?.stop() }
    @ObservationIgnored private var longest: Task<Void, Never>?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// The microphone button: starts listening, or stops it early.
    func toggle() async {
        if listening || starting { starting = false; stop() } else { await start() }
    }

    func start() async {
        guard !listening, !starting else { return }
        starting = true
        defer { starting = false }
        guard await authorized() else { denied = true; return }
        guard starting else { return } // tapped again while the permission prompts were up
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
            silence.arm(heard: false)
            longest = Task { [weak self] in
                try? await Task.sleep(for: SilenceWatch.longest)
                if !Task.isCancelled { self?.stop() }
            }
            task = recognizer.recognitionTask(with: request, resultHandler: Self.handler { [weak self] text, done in
                Task { @MainActor in self?.apply(text, done: done) }
            })
        } catch {
            stop()
            unavailable = true
        }
    }

    func stop() {
        silence.cancel()
        longest?.cancel(); longest = nil
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
        if let text, !text.isEmpty, text != transcript {
            transcript = text
            if listening { silence.arm(heard: true) } // every new word restarts the pause timer
        }
        if done { task = nil; stop() }
    }

    private func authorized() async -> Bool {
        guard await Self.speechAuthorized() else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    /// #570 (build 16 crashed on Say it): Speech calls the authorization handler on its own queue. A closure written inside
    /// this main-actor class is main-actor isolated under Swift 6, so the runtime's isolation check stopped the app the
    /// moment the handler ran. The request is made from a nonisolated function with a @Sendable handler instead.
    nonisolated static func speechAuthorized(
        request: @Sendable (@escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void) -> Void = { handler in
            SFSpeechRecognizer.requestAuthorization(handler)
        }
    ) async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            request { @Sendable status in c.resume(returning: status == .authorized) }
        }
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

/// Stops Say it after a pause: 1.8 s after the last new word, or 8 s when nothing has been heard yet, so a slow
/// start isn't cut off. Every `arm` replaces the pending timer. The sleep is injectable for tests.
@MainActor
final class SilenceWatch {
    static let afterSpeech: Duration = .milliseconds(1800)
    static let beforeSpeech: Duration = .seconds(8)
    static let longest: Duration = .seconds(60)

    private let sleep: @Sendable (Duration) async throws -> Void
    private let fire: @MainActor () -> Void
    private var pending: Task<Void, Never>?

    init(sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         fire: @escaping @MainActor () -> Void) {
        self.sleep = sleep
        self.fire = fire
    }

    func arm(heard: Bool) {
        pending?.cancel()
        let delay = heard ? Self.afterSpeech : Self.beforeSpeech
        pending = Task { [sleep, fire] in
            do { try await sleep(delay) } catch { return }
            guard !Task.isCancelled else { return }
            fire()
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
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
                    Image(systemName: "mic.fill").font(.system(size: 44)).foregroundStyle(PlayscribeRole.action)
                        .accessibilityHidden(true)
                    Text("Let Playscribe hear your list").font(PlayscribeFont.headline).multilineTextAlignment(.center)
                    Text("Playscribe turns your voice into game names on your phone. It listens after you tap the microphone and stops when you stop talking.")
                        .font(PlayscribeFont.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button { explained = true } label: {
                        Text("Continue").font(PlayscribeFont.headline).foregroundStyle(PlayscribeRole.onAction)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(PlayscribeRole.action, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain).tappableFrame()
                    .accessibilityHint("Shows the system permission request")
                    Button("Not now", action: typeInstead).hitTarget()
                }
                .padding(.horizontal, 16).padding(.top, 24)
            } else if capture.denied || capture.unavailable {
                VStack(spacing: 12) {
                    Text(capture.denied ? "Say it is off" : "Speech isn’t available on this device right now")
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
                Text(capture.transcript.isEmpty
                     ? (capture.listening ? "Listening…" : "Tap the microphone and say a few titles, like Elden Ring and Astro Bot.")
                     : capture.transcript)
                    .font(capture.transcript.isEmpty ? PlayscribeFont.subheadline : PlayscribeFont.title3)
                    .foregroundStyle(capture.transcript.isEmpty ? PlayscribeRole.textSecondary : PlayscribeRole.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .padding(.horizontal, 20)
                    .accessibilityLabel(capture.transcript.isEmpty
                                        ? (capture.listening ? "Listening" : "No titles heard yet") : capture.transcript)
            }
            Spacer(minLength: 0)
            if explained && !capture.denied && !capture.unavailable {
                Button {
                    Task { await capture.toggle() }
                } label: {
                    Image(systemName: capture.listening ? "stop.fill" : "mic.fill")
                        .font(.title)
                        .foregroundStyle(PlayscribeRole.onAction)
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(capture.listening ? PlayscribeColor.accentPressed : PlayscribeRole.action))
                        .scaleEffect(capture.listening ? 1.08 : 1)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(capture.listening ? "Stop listening" : "Start listening")
                .accessibilityHint(capture.listening ? "Stops now. It also stops by itself when you stop talking"
                                   : "Say game titles. It stops by itself when you stop talking")
                .tappableFrame()
                Button {
                    capture.stop()
                    find(capture.transcript)
                } label: {
                    Text("Find these games").font(PlayscribeFont.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
                .controlBorder(.outlinedButton, in: Capsule())
                .disabled(capture.transcript.isEmpty)
                .padding(.horizontal, 16)
                .tappableFrame()
            }
        }
        .padding(.bottom, 12)
        .onDisappear { capture.stop() }
    }
}
