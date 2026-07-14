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

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var latestTranscript = ""
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        synthesizer.delegate = self
    }

    // MARK: - Push-to-talk STT

    func startListening() throws {
        guard !isListening else { return }
        latestTranscript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, _ in
            guard let result else { return }
            Task { @MainActor [weak self] in
                self?.latestTranscript = result.bestTranscription.formattedString
            }
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
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

        // Give the recognizer a beat to finalize the last words.
        try? await Task.sleep(nanoseconds: 350_000_000)
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        return latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - TTS

    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        stopSpeaking()
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.isSpeaking = false
        }
    }
}
