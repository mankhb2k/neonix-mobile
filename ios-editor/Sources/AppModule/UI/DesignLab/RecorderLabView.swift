import SwiftUI

/// Design lab for the Record popup, after iPhone's Voice Memos recorder (user's reference 2026-10-18): a small sheet with the recording's name and
/// a running time (hundredths), a red waveform that scrolls in from the right while it records, and one big round button (red dot to start, red square
/// to stop). When it stops the same sheet turns into a review - the whole waveform with a play head, Delete, Play and Add - and Add puts the take
/// on the audio lane at the playhead. Fake data: the levels are simulated, nothing is recorded; "Simulate no mic access" shows that state.
struct RecorderLabView: View {
    @Environment(\.dismiss) private var dismiss

    typealias Phase = RecorderPhase

    private struct Take: Identifiable { let id = UUID(); let name: String; let startMs: Int; let durationMs: Int }

    @State private var phase: Phase = .ready
    @State private var sheetOpen = false
    @State private var levels: [Double] = []
    @State private var elapsed: TimeInterval = 0
    @State private var reviewPlayStart: Date?
    @State private var takes: [Take] = []
    @State private var toast: String?
    @State private var micDenied = false
    @State private var recordingTask: Task<Void, Never>?

    private let playheadMs = 2_000
    private let samplesPerSecond = 15.0

    private var name: String { "Recording \(takes.count + 1)" }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Text("The Record label opens the popup. Start, stop, then Add puts the take at the playhead; Delete throws it away.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal).padding(.top, 4)
            mockTimeline
                .padding(.horizontal, 16).padding(.top, 12)
                .frame(maxHeight: .infinity, alignment: .top)
            mockMainRow
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .sheet(isPresented: $sheetOpen, onDismiss: reset) { recorderSheet }
    }

    // MARK: Mock editor

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.title3).frame(width: 44, height: 44) }
                .accessibilityIdentifier("recorderClose")
            Spacer()
            Text("Recorder lab").font(.headline)
            Spacer()
            Menu {
                Toggle("Simulate no mic access", isOn: $micDenied)
                Button("Clear the timeline", role: .destructive) { takes = [] }
            } label: { Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44) }
                .accessibilityIdentifier("recorderMenu")
        }
        .padding(.horizontal, 8)
    }

    private var mockTimeline: some View {
        GeometryReader { geo in
            let perMs = geo.size.width / 10_000
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 0) {
                        ForEach(0..<10) { second in
                            Text("0:\(String(format: "%02d", second))").font(.caption2).foregroundColor(.secondary)
                                .frame(width: geo.size.width / 10, alignment: .leading)
                        }
                    }
                    ForEach(takes.suffix(5)) { take in
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.cyan.opacity(0.55))
                            .overlay(alignment: .leading) { Text(take.name).font(.caption2.weight(.semibold)).padding(.leading, 4).lineLimit(1) }
                            .frame(width: max(min(CGFloat(take.durationMs) * perMs, geo.size.width - CGFloat(take.startMs) * perMs), 26), height: 26)
                            .offset(x: CGFloat(take.startMs) * perMs)
                            .accessibilityIdentifier("recorderTake")
                    }
                    if takes.isEmpty {
                        Text("Nothing on the timeline yet.").font(.footnote).foregroundColor(.secondary).padding(.top, 6)
                    }
                }
                Rectangle().fill(Color.primary).frame(width: 2).offset(x: CGFloat(playheadMs) * perMs - 1)
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast).font(.footnote.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.black.opacity(0.75), in: Capsule()).foregroundColor(.white)
                        .accessibilityIdentifier("recorderToast")
                }
            }
        }
        .frame(height: 200)
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var mockMainRow: some View {
        HStack(spacing: 8) {
            ForEach([("film.stack", "Extract"), ("music.note", "Music"), ("speaker.wave.3.fill", "Sound FX"), ("mic.fill", "Record")], id: \.1) { symbol, title in
                Button { if title == "Record" { sheetOpen = true } } label: {
                    VStack(spacing: 4) {
                        Image(systemName: symbol).font(.title3)
                        Text(title).font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(title == "Record" ? .primary : .secondary)
                }
                .accessibilityIdentifier(title == "Record" ? "recorderOpen" : "recorderMock-\(title)")
            }
        }
        .padding(.horizontal, 16).frame(height: 56)
    }

    // MARK: The popup

    private var recorderSheet: some View {
        VStack(spacing: 4) {
            Text(name).font(.subheadline.weight(.semibold)).padding(.top, 16)
            Text(timeString(phase == .review ? elapsed : elapsed))
                .font(.footnote.monospacedDigit()).foregroundColor(.secondary)
                .accessibilityIdentifier("recorderTime")

            Group {
                if micDenied {
                    deniedNote
                } else {
                    PlaybackClock(start: reviewPlayStart, duration: elapsed) { progress in
                        LiveWaveform(levels: levels, phase: phase, progress: reviewPlayStart == nil ? nil : progress)
                    }
                }
            }
            .frame(height: 78)
            .padding(.top, 6)

            controls
                .padding(.top, 8).padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(250)])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled)
        .interactiveDismissDisabled(phase == .recording)
    }

    private var deniedNote: some View {
        VStack(spacing: 8) {
            Image(systemName: "mic.slash.fill").font(.title).foregroundColor(.secondary)
            Text("Microphone access is off").font(.subheadline.weight(.semibold))
            Text("Allow it in Settings to record.").font(.caption).foregroundColor(.secondary)
            Button("Open Settings") {}.buttonStyle(.bordered).accessibilityIdentifier("recorderSettings")
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
                reviewButton("trash", title: "Delete", tint: .red, filled: false, id: "recorderDelete") { reset(); phase = .ready }
                Button { togglePlay() } label: {
                    ZStack {
                        Circle().strokeBorder(Color(.systemGray3), lineWidth: 2).background(Circle().fill(Color(.systemBackground)))
                        Image(systemName: reviewPlayStart == nil ? "play.fill" : "stop.fill").font(.system(size: 16)).foregroundColor(.accentColor)
                    }
                    .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("recorderPlay")
                reviewButton("checkmark", title: "Add", tint: .accentColor, filled: true, id: "recorderAdd") { add() }
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

    // MARK: Behaviour (all pretend)

    private func start() {
        levels = []
        elapsed = 0
        phase = .recording
        let began = Date()
        recordingTask = Task {
            var level = 0.1
            var speaking = false
            var untilSwitch = 0.0
            while !Task.isCancelled, phase == .recording {
                try? await Task.sleep(for: .milliseconds(Int(1000 / samplesPerSecond)))
                elapsed = Date().timeIntervalSince(began)
                if elapsed >= untilSwitch { speaking.toggle(); untilSwitch = elapsed + Double.random(in: 0.25...0.9) }
                let target = speaking ? Double.random(in: 0.35...1.0) : Double.random(in: 0.04...0.14)
                level = level * 0.45 + target * 0.55
                levels.append(level)
            }
        }
    }

    private func stop() {
        recordingTask?.cancel()
        recordingTask = nil
        phase = .review
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func togglePlay() {
        if reviewPlayStart != nil { reviewPlayStart = nil; return }
        let started = Date()
        reviewPlayStart = started
        Task {
            try? await Task.sleep(for: .seconds(elapsed))
            if reviewPlayStart == started { reviewPlayStart = nil }
        }
    }

    private func add() {
        takes.append(Take(name: name, startMs: playheadMs, durationMs: Int(elapsed * 1000)))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        toast = "Added \(takes.last?.name ?? "")"
        phase = .ready
        sheetOpen = false
        Task {
            try? await Task.sleep(for: .milliseconds(1600))
            toast = nil
        }
    }

    /// Back to a clean popup (also when it is swiped away: an unsaved take is dropped).
    private func reset() {
        recordingTask?.cancel()
        recordingTask = nil
        reviewPlayStart = nil
        levels = []
        elapsed = 0
        phase = .ready
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        let hundredths = Int((seconds * 100).rounded(.down))
        return String(format: "%02d:%02d.%02d", hundredths / 6000, (hundredths / 100) % 60, hundredths % 100)
    }
}
