import AVFoundation
import Foundation
import Speech

/// Records up to `Echo.maxDuration` seconds from the microphone and transcribes it as you speak, on the iPhone itself
/// (Speech framework, on-device recognition only), so nothing you say leaves the phone.
@MainActor
final class EchoRecorder: ObservableObject {
    enum State: Equatable {
        case idle
        case recording(started: Date)
        case finishing
        case done
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript = ""
    /// Microphone level, 0…1, for the meter.
    @Published private(set) var level: Double = 0

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var limit: Task<Void, Never>?
    private var finish: CheckedContinuation<Void, Never>?

    var isRecording: Bool { if case .recording = state { return true } else { return false } }

    /// Asks for the microphone and speech recognition the first time, then starts recording.
    func start() async {
        guard !isRecording, state != .finishing else { return }
        transcript = ""
        guard await Self.speechAllowed() else {
            return fail("Speech recognition is off for Meetball. Turn it on in Settings › Meetball, or type the note.")
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            return fail("Meetball can't use the microphone. Turn it on in Settings › Meetball, or type the note.")
        }
        guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(), recognizer.isAvailable else {
            return fail("Dictation isn't available right now. Type the note instead.")
        }
        guard recognizer.supportsOnDeviceRecognition else {
            return fail("On-device dictation isn't available for \(recognizer.locale.localizedString(forIdentifier: recognizer.locale.identifier) ?? "your language"). Type the note instead.")
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            request.taskHint = .dictation
            self.request = request
            self.recognizer = recognizer

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                let level = Self.level(of: buffer)
                Task { @MainActor in self?.level = level }
            }
            engine.prepare()
            try engine.start()

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let final = (result?.isFinal ?? false) || error != nil
                Task { @MainActor in self?.heard(text, final: final) }
            }
            state = .recording(started: Date())
            limit = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Echo.maxDuration))
                guard !Task.isCancelled else { return }
                await self?.stop()
            }
        } catch {
            teardown()
            fail("Couldn't start recording: \(error.localizedDescription)")
        }
    }

    /// Stops recording and waits (briefly) for the last words to be transcribed.
    func stop() async {
        guard isRecording else { return }
        limit?.cancel()
        state = .finishing
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        level = 0
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            finish = c
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.resumeFinish()
            }
        }
        teardown()
        state = .done
    }

    /// Stops without keeping anything (the sheet closed).
    func cancel() {
        limit?.cancel()
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        task?.cancel()
        resumeFinish()
        teardown()
        state = .idle
    }

    private func heard(_ text: String?, final: Bool) {
        if let text, !text.isEmpty { transcript = text }
        if final { resumeFinish() }
    }

    private func resumeFinish() {
        finish?.resume()
        finish = nil
    }

    private func teardown() {
        task = nil
        recognizer = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func fail(_ message: String) {
        state = .failed(message)
    }

    private static func speechAllowed() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { c in
                SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
            }
        default: return false
        }
    }

    /// Root-mean-square level of the first channel, scaled so speech fills most of the meter.
    nonisolated private static func level(of buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        let rms = sqrt(sum / Float(n))
        return min(1, Double(rms) * 8)
    }
}
