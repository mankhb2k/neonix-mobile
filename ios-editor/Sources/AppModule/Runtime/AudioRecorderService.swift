import AVFoundation
import Combine

/// Ghi âm — the last of the 4-part audio roadmap (Thêm nhạc, Hiệu ứng âm
/// thanh, Trích xuất, **Ghi âm**). Records straight to a temp file, not into
/// `MediaImportService.importedMediaDirectory` — the finished recording is
/// handed to `MediaImportService.importAudio(from:)` exactly the way
/// `AudioFilePicker`'s own pick result already is (`EditorShellView
/// .addAudio(from:)`), so a mic recording and a Files-app pick are, from
/// that point on, the identical flow: no separate command, no separate
/// asset-minting path.
@MainActor
final class AudioRecorderService: ObservableObject {
    @Published private(set) var isRecording = false
    /// Surfaced so the UI can show *why* tapping "Ghi âm" did nothing,
    /// instead of silently failing — the only concession to error UI this
    /// app makes for Ghi âm; everything else stays the established
    /// "fail closed, no-op" convention.
    @Published private(set) var permissionDenied = false
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    /// Loudness (0...1) sampled `levelsPerSecond` times a second while recording; kept after `stopRecording()` so the review can draw the whole take.
    @Published private(set) var levels: [Double] = []
    /// Length of the last finished take.
    private(set) var recordedDuration: TimeInterval = 0
    static let levelsPerSecond = 15.0

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var elapsedTimer: Timer?

    func startRecording() async {
        guard await requestPermission() else {
            permissionDenied = true
            return
        }
        permissionDenied = false

        let session = AVAudioSession.sharedInstance()
        guard (try? session.setCategory(.playAndRecord, options: [.defaultToSpeaker])) != nil,
              (try? session.setActive(true)) != nil
        else { return }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else { return }
        recorder.isMeteringEnabled = true
        guard recorder.record() else { return }

        self.recorder = recorder
        recordingURL = url
        isRecording = true
        elapsedSeconds = 0
        levels = []
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1 / Self.levelsPerSecond, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    /// Returns the finished recording's temp URL — `nil` if nothing was
    /// actually recording (a stray stop tap, e.g.).
    @discardableResult
    func stopRecording() -> URL? {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        recordedDuration = recorder?.currentTime ?? 0
        elapsedSeconds = recordedDuration
        recorder?.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
        isRecording = false
        let url = recordingURL
        recorder = nil
        recordingURL = nil
        return url
    }

    /// Throws the last take away: its file and its levels.
    func discard(_ url: URL? = nil) {
        if let url { try? FileManager.default.removeItem(at: url) }
        levels = []
        elapsedSeconds = 0
        recordedDuration = 0
    }

    /// One meter reading: the average power in dB (-160...0) mapped so speech fills most of the height (-50 dB and below is flat).
    private func sample() {
        guard let recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let decibels = Double(recorder.averagePower(forChannel: 0))
        levels.append(min(max((decibels + 50) / 50, 0.02), 1))
        elapsedSeconds = recorder.currentTime
    }

    private func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
