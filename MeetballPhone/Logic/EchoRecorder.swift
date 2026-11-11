import AVFoundation
import Foundation
import Speech

/// Records from the microphone for as long as you talk (up to `Echo.maxDuration`, a safety stop) and transcribes it as
/// you speak, on the iPhone itself (Speech framework, on-device recognition only), so nothing you say leaves the phone.
///
/// On-device recognition ends a request on its own after a minute or so, or after a long pause. When that happens
/// mid-recording, the words so far are kept and a fresh request carries on from the same microphone tap, so the note
/// never starts over.
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
    /// The request the microphone tap feeds; swapped for a new one when recognition ends a segment.
    private let feed = RequestFeed()
    /// Words from segments recognition has already finished, this recording.
    private var committed = ""
    /// The latest words of the segment under way.
    private var partial = ""
    private var segmentStarted = Date()
    private var task: SFSpeechRecognitionTask?
    private var limit: Task<Void, Never>?
    private var finish: CheckedContinuation<Void, Never>?

    var isRecording: Bool { if case .recording = state { return true } else { return false } }

    /// Asks for the microphone and speech recognition the first time, then starts recording.
    func start() async {
        guard !isRecording, state != .finishing else { return }
        transcript = ""
        committed = ""
        partial = ""
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

            self.recognizer = recognizer

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            let feed = self.feed
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                feed.append(buffer)
                let level = Self.level(of: buffer)
                Task { @MainActor in self?.level = level }
            }
            engine.prepare()
            try engine.start()
            beginSegment()
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
        feed.current?.endAudio()
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

    /// Starts a recognition request on the words still to come.
    private func beginSegment() {
        guard let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        feed.current = request
        partial = ""
        segmentStarted = Date()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = (result?.isFinal ?? false) || error != nil
            Task { @MainActor in self?.heard(text, final: final, from: request) }
        }
    }

    private func heard(_ text: String?, final: Bool, from request: SFSpeechAudioBufferRecognitionRequest) {
        // Late words from a segment already handed over.
        guard request === feed.current else { return }
        if let text, !text.isEmpty { partial = text }
        transcript = Echo.joined(committed, partial)
        guard final else { return }
        if isRecording {
            // Recognition stopped by itself (its time limit or a long pause): keep the words and carry on.
            committed = transcript
            // A segment that ends as soon as it starts means recognition has given up; stop rather than spin.
            if Date().timeIntervalSince(segmentStarted) < 1 && partial.isEmpty {
                Task { await stop() }
            } else {
                beginSegment()
            }
        } else {
            resumeFinish()
        }
    }

    private func resumeFinish() {
        finish?.resume()
        finish = nil
    }

    private func teardown() {
        task = nil
        recognizer = nil
        feed.current = nil
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

/// The recognition request the audio tap appends to, swapped from the main actor while the tap runs on the audio
/// thread.
private final class RequestFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    var current: SFSpeechAudioBufferRecognitionRequest? {
        get { lock.withLock { request } }
        set { lock.withLock { request = newValue } }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        current?.append(buffer)
    }
}
