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
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings), recorder.record() else { return }

        self.recorder = recorder
        recordingURL = url
        isRecording = true
        elapsedSeconds = 0
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsedSeconds = self?.recorder?.currentTime ?? 0 }
        }
    }

    /// Returns the finished recording's temp URL — `nil` if nothing was
    /// actually recording (a stray stop tap, e.g.).
    @discardableResult
    func stopRecording() -> URL? {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        recorder?.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
        isRecording = false
        let url = recordingURL
        recorder = nil
        recordingURL = nil
        return url
    }

    private func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
