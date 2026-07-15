import AVFoundation
import Speech

/// Speech in and out, fully local so the scaffold works with zero cloud keys.
///
/// STT: Apple Speech (SFSpeechRecognizer) streaming from AVAudioEngine —
/// the same fallback provider Clicky ships. TTS: AVSpeechSynthesizer.
/// Both sit behind small surfaces so cloud providers (AssemblyAI streaming,
/// ElevenLabs) can replace them without touching the turn pipeline.
@MainActor
final class SpeechService: NSObject, ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var isSpeaking = false
    /// Smoothed mic input level in 0...1, for the voice indicator waveform.
    @Published private(set) var micLevel: Double = 0

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var latestTranscript = ""
    private var receivedFinalResult = false
    private let synthesizer = AVSpeechSynthesizer()

    /// Best installed system voice: premium beats enhanced beats compact.
    /// Users can add premium voices in System Settings > Accessibility >
    /// Spoken Content > System Voice > Manage Voices.
    private static let preferredVoice: AVSpeechSynthesisVoice? = {
        let english = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
        func pick(_ quality: AVSpeechSynthesisVoiceQuality) -> AVSpeechSynthesisVoice? {
            english.first { $0.quality == quality && $0.language == "en-US" }
                ?? english.first { $0.quality == quality }
        }
        return pick(.premium) ?? pick(.enhanced) ?? AVSpeechSynthesisVoice(language: "en-US")
    }()

    override init() {
        super.init()
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        synthesizer.delegate = self
    }

    // MARK: - Push-to-talk STT

    func startListening() throws {
        guard !isListening else { return }
        latestTranscript = ""
        receivedFinalResult = false

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On-device recognition skips the server round-trip: faster finalize
        // and works offline.
        if recognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        if #available(macOS 13, *) {
            request.addsPunctuation = true
        }
        recognitionRequest = request

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, _ in
            guard let result else { return }
            let transcript = result.bestTranscription.formattedString
            let isFinal = result.isFinal
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.latestTranscript = transcript
                if isFinal { self.receivedFinalResult = true }
            }
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let level = Self.normalizedLevel(buffer: buffer)
            Task { @MainActor [weak self] in
                guard let self, self.isListening else { return }
                // Fast attack, slow release keeps the bars lively but smooth.
                self.micLevel = max(level, self.micLevel * 0.82)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true
    }

    /// Stops the mic and returns the final transcript for the turn.
    func stopListening() async -> String {
        guard isListening else { return "" }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        isListening = false
        micLevel = 0

        // Wait for the recognizer's final result, returning early the moment
        // it lands (350ms is the fallback cap for slow finalizes).
        for _ in 0..<7 where !receivedFinalResult {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        return latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - TTS

    /// Speak from scratch: cuts off anything in progress first.
    func speak(_ text: String) {
        stopSpeaking()
        enqueue(text)
    }

    /// Queue a chunk behind whatever is already speaking. This is the
    /// streaming path: each completed sentence is enqueued as it arrives,
    /// so speech starts on the first sentence of a reply.
    func enqueue(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = Self.preferredVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        // A small breath between queued sentences reads as natural cadence.
        utterance.postUtteranceDelay = 0.08
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    /// RMS of one mic buffer mapped through dB into a UI-friendly 0...1 range.
    private nonisolated static func normalizedLevel(buffer: AVAudioPCMBuffer) -> Double {
        guard let samples = buffer.floatChannelData?[0] else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }
        var sumOfSquares: Float = 0
        for i in 0..<frameCount {
            sumOfSquares += samples[i] * samples[i]
        }
        let rms = sqrt(sumOfSquares / Float(frameCount))
        let decibels = 20 * log10(max(rms, 0.00001))
        // Speech typically lands between -50dB (quiet) and -10dB (loud).
        return Double(min(max((decibels + 50) / 40, 0), 1))
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // With queued utterances, only go quiet once the queue drains.
            if !self.synthesizer.isSpeaking { self.isSpeaking = false }
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if !self.synthesizer.isSpeaking { self.isSpeaking = false }
        }
    }
}
