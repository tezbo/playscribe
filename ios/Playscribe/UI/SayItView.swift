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
    /// The last listen ended with no words: "Didn’t catch that" (Iris, #578).
    var heardNothing = false

    @ObservationIgnored private lazy var silence = SilenceWatch { [weak self] in self?.stop() }
    @ObservationIgnored private var longest: Task<Void, Never>?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// The microphone button: starts listening, or stops it early.
    func toggle() async {
        if listening || starting { startToken += 1; starting = false; stop() } else { await start() }
    }

    /// Each start takes a token; a stop tap or a newer start retires it, so a start that was waiting on the permission
    /// prompts never opens the microphone twice (Quinn, #578: tap, tap to stop, tap again before the prompt answers).
    @ObservationIgnored private var startToken = 0

    func start() async {
        guard !listening, !starting else { return }
        startToken += 1
        let token = startToken
        starting = true
        defer { if token == startToken { starting = false } }
        let allowed = await authorize()
        guard token == startToken, !listening else { return } // stopped, or started again, while the prompts were up
        guard allowed else { denied = true; return }
        heardNothing = false
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
            // The Mac sim aborted in AURemoteIO::Initialize the moment `engine.inputNode` was first touched (#578: 4 of 4 at
            // 39a0bd8a, again at 1d5491af). Ask the session for a live input first; only then touch the engine's input, and
            // still refuse a route that reports 0 Hz or 0 channels.
            guard Self.hasLiveInput(session) else {
                request.endAudio(); self.request = nil
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                unavailable = true
                return
            }
            let input = engine.inputNode
            let format = input.inputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                request.endAudio(); self.request = nil
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                unavailable = true
                return
            }
            Self.installTap(on: input, format: format, request: request)
            engine.prepare()
            try engine.start()
            listening = true
            Haptics.voiceEdge()
            Self.announce("Listening")
            if Self.autoStops { silence.arm(heard: false) }
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
        let wasListening = listening
        if request != nil {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            request?.endAudio()
            request = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        listening = false
        guard wasListening else { return }
        Haptics.voiceEdge()
        heardNothing = transcript.isEmpty
        Self.announce(heardNothing ? "Stopped listening. Didn’t catch that" : "Stopped listening. Heard \(transcript)")
    }

    /// With VoiceOver or Switch Control on there is no pause stop: a slow speaker would lose words (Iris, #578). Tap to
    /// stop, or the 60 s limit. Titles are announced when listening stops, not while it runs, so VoiceOver's own voice
    /// never goes into the microphone.
    static var autoStops: Bool { !(UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning) }

    private static func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }

    #if INTERNAL
    /// `-qaRoute add/say/<state>`: the screen in that state for stills, with no microphone.
    func simulate(_ state: String) {
        let heard = "Elden Ring and Astro Bot"
        switch state {
        case "listening": listening = true
        case "heard": listening = true; transcript = heard
        case "stopped": transcript = heard
        case "nothing": heardNothing = true
        case "denied": denied = true
        default: break
        }
    }
    #endif

    private func apply(_ text: String?, done: Bool) {
        if let text, !text.isEmpty, text != transcript {
            transcript = text
            if listening && Self.autoStops { silence.arm(heard: true) } // every new word restarts the pause timer
        }
        if done { task = nil; stop() }
    }

    /// A microphone the session can record from right now, judged without touching the engine's input node.
    nonisolated static func hasLiveInput(_ session: AVAudioSession) -> Bool {
        session.isInputAvailable && !session.currentRoute.inputs.isEmpty && session.sampleRate > 0
    }

    /// The permission step; tests replace it to hold a start at the prompt.
    @ObservationIgnored var authorize: @MainActor () async -> Bool = { await SpeechCapture.authorized() }

    private static func authorized() async -> Bool {
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
    nonisolated private static func installTap(on node: AVAudioInputNode, format: AVAudioFormat,
                                               request: SFSpeechAudioBufferRecognitionRequest) {
        nonisolated(unsafe) let request = request
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
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
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var capture = SpeechCapture()
    @State private var pulse = false
    var find: (String) -> Void
    var typeInstead: () -> Void
    /// The explainer comes before the system prompts, and only while neither is decided.
    @State private var explained = SFSpeechRecognizer.authorizationStatus() != .notDetermined

    var body: some View {
        VStack(spacing: 20) {
            // At AX5 in a short panel (Closed landscape, 466 pt) the words need more height than there is. They scroll
            // and wrap; nothing is cut to one line (Mac stills at 61bc6dcb). The microphone and Find stay below.
            ScrollView {
                words.frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            if explained && !capture.denied && !capture.unavailable {
                Button {
                    Task { await capture.toggle() }
                } label: {
                    Image(systemName: capture.listening ? "stop.fill" : "mic.fill")
                        .font(.title)
                        .foregroundStyle(PlayscribeRole.onAction)
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(capture.listening ? PlayscribeColor.accentPressed : PlayscribeRole.action))
                        .contentShape(Circle())
                        // Listening is shown by shape too, not colour alone: a ring that breathes, or holds still
                        // under Reduce Motion (Iris, #578).
                        .background {
                            if capture.listening {
                                Circle().stroke(PlayscribeRole.action, lineWidth: 3)
                                    .frame(width: 80, height: 80)
                                    .scaleEffect(reduceMotion ? 1 : (pulse ? 1.12 : 0.94))
                                    .opacity(reduceMotion ? 1 : (pulse ? 0.45 : 1))
                                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                                               value: pulse)
                                    .onAppear { pulse = true }
                                    .onDisappear { pulse = false }
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(width: 88, height: 88)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(capture.listening ? "Stop listening" : "Start listening")
                .accessibilityHint(capture.listening ? "Stops now. It also stops by itself when you stop talking"
                                   : "Say game titles. It stops by itself when you stop talking")
                .tappableFrame()
                // Once listening has stopped with titles heard, Find is the one next step: the filled primary (Iris,
                // #578). While listening it stays outlined; with nothing heard it is disabled.
                if !capture.listening && !capture.transcript.isEmpty {
                    Button { find(capture.transcript) } label: { primaryLabel("Find these games") }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .tappableFrame()
                } else {
                    Button {
                        capture.stop()
                        find(capture.transcript)
                    } label: { secondaryLabel("Find these games") }
                    .buttonStyle(.bordered)
                    .controlBorder(.outlinedButton, in: Capsule())
                    .disabled(capture.transcript.isEmpty)
                    .padding(.horizontal, 16)
                    .tappableFrame()
                }
            }
        }
        .padding(.bottom, 12)
        .onDisappear { capture.stop() }
        #if INTERNAL
        .onAppear {
            if let state = model.simulatedSay { explained = true; capture.simulate(state) }
        }
        #endif
    }

    /// The explainer, the off state, or what was heard: the part that scrolls.
    @ViewBuilder private var words: some View {
        if !explained {
            VStack(spacing: 12) {
                Image(systemName: "mic.fill").font(.system(size: 44)).foregroundStyle(PlayscribeRole.action)
                    .accessibilityHidden(true)
                Text("Let Playscribe hear your list").font(PlayscribeFont.headline).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Playscribe turns your voice into game names on your phone. It listens after you tap the microphone and stops when you stop talking.")
                    .font(PlayscribeFont.subheadline).foregroundStyle(PlayscribeRole.textSecondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
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
                Text(capture.denied ? "Say it can’t listen yet" : "Speech isn’t available on this device right now")
                    .font(PlayscribeFont.headline).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if capture.denied {
                    Text("Allow the microphone and speech recognition in Settings to add games by voice.")
                        .font(PlayscribeFont.subheadline).foregroundStyle(PlayscribeRole.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Real buttons, not bare text (Iris, #578): Open Settings leads when it can fix this; Type it is the way on.
                if capture.denied {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: { primaryLabel("Open Settings") }
                    .buttonStyle(.plain).tappableFrame()
                    Button(action: typeInstead) { secondaryLabel("Type it") }
                        .buttonStyle(.bordered)
                        .controlBorder(.outlinedButton, in: Capsule())
                        .tappableFrame()
                } else {
                    Button(action: typeInstead) { primaryLabel("Type it") }
                        .buttonStyle(.plain).tappableFrame()
                }
            }
            .padding(.horizontal, 16).padding(.top, 24)
        } else {
            Text(capture.transcript.isEmpty ? emptyLine : capture.transcript)
                .font(capture.transcript.isEmpty ? PlayscribeFont.subheadline : PlayscribeFont.title3)
                .foregroundStyle(capture.transcript.isEmpty ? PlayscribeRole.textSecondary : PlayscribeRole.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 80)
                .padding(.horizontal, 20)
                .accessibilityLabel(capture.transcript.isEmpty
                                    ? (capture.listening ? "Listening" : capture.heardNothing ? emptyLine : "No titles heard yet")
                                    : capture.transcript)
        }
    }

    private func primaryLabel(_ title: String) -> some View {
        Text(title).font(PlayscribeFont.headline).foregroundStyle(PlayscribeRole.onAction)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(PlayscribeRole.action, in: Capsule())
    }

    private func secondaryLabel(_ title: String) -> some View {
        Text(title).font(PlayscribeFont.headline).frame(maxWidth: .infinity, minHeight: 50)
    }

    private var emptyLine: String {
        if capture.listening { return "Listening…" }
        if capture.heardNothing { return "Didn’t catch that. Tap the microphone to try again." }
        return "Tap the microphone and say a few titles, like Elden Ring and Astro Bot."
    }
}
