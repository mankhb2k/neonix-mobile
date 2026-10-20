import AVFoundation
import SwiftUI

/// The Record popup (Recorder lab, after iPhone's Voice Memos; user 2026-10-18): a small sheet with the take's name and a running time, a red
/// waveform scrolling in while it records and one big round button (red dot to start, red square to stop). Stopping turns the same sheet into a
/// review - the whole waveform with a play head, Delete, Play and Add; Add hands the file to `onAdd` (the shell imports it and puts it on the audio
/// lane at the playhead) and closes. Swiping the sheet away drops an unsaved take and is blocked while recording.
struct RecorderSheet: View {
    /// The finished take's temp file. The shell copies it into the project and deletes it.
    let onAdd: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = AudioRecorderService()
    @State private var phase: RecorderPhase = .ready
    @State private var takeURL: URL?
    @State private var takeDuration: TimeInterval = 0
    @State private var player: AVAudioPlayer?
    @State private var playStart: Date?
    @State private var micDenied = false
    /// Only to number the takes ("Recording 3"); it is not a name stored with the clip.
    @AppStorage("recorderTakeCount") private var takeCount = 0

    private var name: String { "Recording \(takeCount + 1)" }

    var body: some View {
        VStack(spacing: 4) {
            Text(name).font(.subheadline.weight(.semibold)).padding(.top, 16)
            Text(Self.timeString(phase == .review ? takeDuration : recorder.elapsedSeconds))
                .font(.footnote.monospacedDigit()).foregroundColor(.secondary)
                .accessibilityIdentifier("recorderTime")

            Group {
                if micDenied {
                    deniedNote
                } else {
                    PlaybackClock(start: playStart, duration: takeDuration) { progress in
                        LiveWaveform(levels: recorder.levels, phase: phase, progress: playStart == nil ? nil : progress)
                    }
                }
            }
            .frame(height: 78)
            .padding(.top, 6)

            controls.padding(.top, 8).padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(250)])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled)
        .interactiveDismissDisabled(phase == .recording)
        .onAppear { micDenied = AVAudioApplication.shared.recordPermission == .denied }
        .onDisappear(perform: cleanUp)
    }

    // MARK: Parts

    private var deniedNote: some View {
        VStack(spacing: 8) {
            Image(systemName: "mic.slash.fill").font(.title).foregroundColor(.secondary)
            Text("Microphone access is off").font(.subheadline.weight(.semibold))
            Text("Allow it in Settings to record.").font(.caption).foregroundColor(.secondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.bordered).accessibilityIdentifier("recorderSettings")
        }
    }

    @ViewBuilder private var controls: some View {
        switch phase {
        case .ready, .recording:
            Button(action: phase == .ready ? start : stop) {
                ZStack {
                    Circle().strokeBorder(Color(.systemGray3), lineWidth: 2).background(Circle().fill(Color(.systemBackground)))
                    if phase == .ready {
                        Circle().fill(micDenied ? Color(.systemGray3) : Color.red).frame(width: 34, height: 34)
                    } else {
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.red).frame(width: 18, height: 18)
                    }
                }
                .frame(width: 48, height: 48)
                .animation(.easeOut(duration: 0.15), value: phase)
            }
            .buttonStyle(.plain)
            .disabled(micDenied)
            .accessibilityIdentifier("recorderButton")
            .accessibilityLabel(phase == .ready ? "Start recording" : "Stop recording")
        case .review:
            HStack(alignment: .center, spacing: 32) {
                reviewButton("trash", title: "Delete", tint: .red, filled: false, id: "recorderDelete", action: deleteTake)
                Button(action: togglePlay) {
                    ZStack {
                        Circle().strokeBorder(Color(.systemGray3), lineWidth: 2).background(Circle().fill(Color(.systemBackground)))
                        Image(systemName: playStart == nil ? "play.fill" : "stop.fill").font(.system(size: 16)).foregroundColor(.accentColor)
                    }
                    .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("recorderPlay")
                .accessibilityLabel(playStart == nil ? "Play" : "Stop")
                reviewButton("checkmark", title: "Add", tint: .accentColor, filled: true, id: "recorderAdd", action: add)
            }
        }
    }

    private func reviewButton(_ symbol: String, title: String, tint: Color, filled: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(filled ? tint : Color(.secondarySystemBackground), in: Circle())
                .foregroundColor(filled ? .white : tint)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityLabel(title)
    }

    // MARK: Behaviour

    private func start() {
        Task {
            await recorder.startRecording()
            if recorder.isRecording {
                phase = .recording
            } else {
                micDenied = recorder.permissionDenied
            }
        }
    }

    private func stop() {
        takeURL = recorder.stopRecording()
        takeDuration = recorder.recordedDuration
        phase = takeURL == nil ? .ready : .review
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func togglePlay() {
        if playStart != nil { stopPlayback(); return }
        guard let takeURL, let next = try? AVAudioPlayer(contentsOf: takeURL) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player = next
        next.play()
        let started = Date()
        playStart = started
        Task {
            try? await Task.sleep(for: .seconds(takeDuration))
            if playStart == started { stopPlayback() }
        }
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        playStart = nil
    }

    private func deleteTake() {
        stopPlayback()
        recorder.discard(takeURL)
        takeURL = nil
        phase = .ready
    }

    private func add() {
        guard let url = takeURL else { return }
        stopPlayback()
        takeURL = nil   // the shell owns the file now (it copies it, then deletes it)
        takeCount += 1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onAdd(url)
        dismiss()
    }

    /// The sheet is gone: an unsaved take or a recording in progress is dropped.
    private func cleanUp() {
        stopPlayback()
        if recorder.isRecording { recorder.stopRecording().map { recorder.discard($0) } }
        if let takeURL { recorder.discard(takeURL) }
    }

    /// 00:04.53 - minutes, seconds, hundredths.
    static func timeString(_ seconds: TimeInterval) -> String {
        let hundredths = Int((seconds * 100).rounded(.down))
        return String(format: "%02d:%02d.%02d", hundredths / 6000, (hundredths / 100) % 60, hundredths % 100)
    }
}
