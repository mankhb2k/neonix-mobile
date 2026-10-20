import SwiftUI

/// The Sound FX picker (user 2026-10-17, Sound FX lab layout "B Waveform", system look like the other popups): the Stickers' sheet (340 pt, pull up for
/// all, category chips); a row per sound - round play button, the name over a mini waveform that fills while it plays, the length and a round +.
/// Playing a sound downloads it first, + puts it on the audio lane at the playhead.
/// The stage stays live at the small size. Files and catalogue come from the API / R2 through `SoundStore`.
struct SoundSheet: View {
    let store: SoundStore
    /// Adds the sound to the project at the playhead (copies the file into the project's media first).
    let onUse: (APISoundCatalogue.Sound) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var player = SoundPreviewPlayer()
    @State private var category: String?   // nil = All
    @State private var adding: Set<String> = []
    @State private var justAdded: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                if let catalogue = store.catalogue {
                    chips(catalogue)
                    list(catalogue)
                } else {
                    placeholder
                }
            }
            .padding(.top, 4)
            .navigationTitle("Sound FX")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("soundDone")
                }
            }
        }
        .presentationDetents([.height(340), .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .height(340)))
        .task { await store.load() }
        .onDisappear { player.stop() }
    }

    // MARK: Parts

    private func chips(_ catalogue: APISoundCatalogue) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", id: nil)
                ForEach(catalogue.categories) { chip($0.title, id: $0.id) }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ title: String, id: String?) -> some View {
        let on = category == id
        return Button { category = id } label: {
            Text(title).font(.subheadline.weight(.medium))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(on ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                .foregroundColor(on ? Color.white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("soundChip-\(id ?? "all")")
    }

    private func list(_ catalogue: APISoundCatalogue) -> some View {
        let sounds = catalogue.sounds.filter { category == nil || $0.category == category }
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sounds) { sound in
                    row(sound)
                    Divider().padding(.leading, 68)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .accessibilityIdentifier("soundList")
    }

    private func row(_ sound: APISoundCatalogue.Sound) -> some View {
        let isPlaying = player.playingId == sound.id
        let start = isPlaying ? player.start : nil
        return HStack(spacing: 12) {
            Button { player.toggle(sound, store: store) } label: {
                PlaybackProgress(start: start, durationMs: sound.durationMs) { progress in
                    PlayDisc(playing: isPlaying, loading: player.loadingId == sound.id, progress: progress)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("soundPlay-\(sound.id)")
            .accessibilityLabel("Play \(sound.name)")

            VStack(alignment: .leading, spacing: 4) {
                Text(sound.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                PlaybackProgress(start: start, durationMs: sound.durationMs) { progress in
                    MiniWave(peaks: sound.peaks, progress: progress)
                }
                .frame(height: 18)
            }
            Spacer(minLength: 4)
            Text(Self.seconds(sound.durationMs)).font(.caption.monospacedDigit()).foregroundColor(.secondary)
            addButton(sound)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { player.toggle(sound, store: store) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("soundRow-\(sound.id)")
    }

    /// The round + at the end of a row: puts the sound on the timeline; a spinner while it is copied, a check for a second after.
    private func addButton(_ sound: APISoundCatalogue.Sound) -> some View {
        let busy = adding.contains(sound.id)
        let done = justAdded == sound.id
        return Button {
            player.stop()
            adding.insert(sound.id)
            Task {
                let added = await onUse(sound)
                adding.remove(sound.id)
                guard added else { return }
                justAdded = sound.id
                try? await Task.sleep(for: .milliseconds(1200))
                if justAdded == sound.id { justAdded = nil }
            }
        } label: {
            Group {
                if busy { ProgressView().controlSize(.small).tint(Color.white) }
                else { Image(systemName: done ? "checkmark" : "plus").font(.system(size: 15, weight: .bold)) }
            }
            .frame(width: 34, height: 34)
            .background(Color.accentColor, in: Circle())
            .foregroundColor(Color.white)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityIdentifier("soundUse-\(sound.id)")
        .accessibilityLabel(done ? "Added" : "Add \(sound.name)")
    }

    @ViewBuilder private var placeholder: some View {
        Spacer()
        switch store.state {
        case .failed(let message):
            VStack(spacing: 10) {
                Image(systemName: "wifi.exclamationmark").font(.title2).foregroundColor(.secondary)
                Text("The sounds could not be loaded").font(.subheadline.weight(.semibold))
                Text(message).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
                Button("Try again") { Task { await store.load() } }.buttonStyle(.bordered).accessibilityIdentifier("soundRetry")
            }
        default:
            ProgressView().accessibilityIdentifier("soundLoading")
        }
        Spacer()
    }

    static func seconds(_ ms: Double) -> String { String(format: "%.1f s", ms / 1000) }
}

/// Gives its content the playback progress (0...1) of a sound that started at `start`, redrawn every frame only while one plays.
private struct PlaybackProgress<Content: View>: View {
    let start: Date?
    let durationMs: Double
    @ViewBuilder let content: (Double) -> Content

    var body: some View {
        if let start {
            SwiftUI.TimelineView(.animation) { context in
                content(min(context.date.timeIntervalSince(start) / (durationMs / 1000), 1))
            }
        } else {
            content(0)
        }
    }
}

private struct PlayDisc: View {
    let playing: Bool
    let loading: Bool
    let progress: Double

    var body: some View {
        ZStack {
            Circle().fill(Color(.secondarySystemBackground))
            Circle().trim(from: 0, to: progress).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
            if loading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: playing ? "stop.fill" : "play.fill").font(.system(size: 15)).foregroundColor(.accentColor)
            }
        }
        .frame(width: 44, height: 44)
    }
}

/// The sound's loudness bars; the played part is dark, the rest grey.
private struct MiniWave: View {
    let peaks: [Double]
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 1.5) {
                ForEach(Array(peaks.enumerated()), id: \.offset) { index, value in
                    Capsule()
                        .fill(Double(index) / Double(max(peaks.count, 1)) < progress ? Color.accentColor : Color(.systemGray4))
                        .frame(height: max(geo.size.height * value, 2))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
