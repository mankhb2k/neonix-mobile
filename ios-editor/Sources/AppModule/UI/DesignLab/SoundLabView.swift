import SwiftUI

/// Design lab for the Sound FX picker. The question is how to browse a library you listen to before you use it: plain rows with a play button (A),
/// rows with a waveform that fills while the sound plays (B), or a grid of tiles with a "Use" bar for the picked one (C). Fake data - the 20
/// starter sounds' names and lengths - and a pretend playback and download, so the flow (listen, download once, put on the timeline at the
/// playhead) can be judged on the device. Same sheet as the Stickers: 340 pt, pull up for all.
struct SoundLabView: View {
    @Environment(\.dismiss) private var dismiss

    enum Variant: String, CaseIterable, Identifiable {
        case list = "A List", wave = "B Waveform", grid = "C Grid"
        var id: String { rawValue }

        var summary: String {
            switch self {
            case .list: return "A row per sound: round play button with a progress ring, name, category and length, and a Use button"
            case .wave: return "Like A, with a mini waveform that fills while the sound plays - tells the shape of a sound before you hear it"
            case .grid: return "3-column tiles; a tap plays and picks, the Use bar at the bottom adds the picked one - denser, one more tap"
            }
        }
    }

    private struct Playing { let id: String; let start: Date }
    private struct Added: Identifiable { let id = UUID(); let sound: LabSound; let startMs: Int }

    @State private var variant: Variant = .list
    @State private var category: LabSoundCategory?   // nil = All
    @State private var sheetOpen = false
    @State private var playing: Playing?
    @State private var picked: LabSound?              // grid: the tile whose Use bar shows
    @State private var downloaded: Set<String> = ["sfx-pop", "sfx-whoosh-soft", "sfx-boom"]
    @State private var downloading: Set<String> = []
    @State private var added: [Added] = []
    @State private var toast: String?
    @State private var showsDownloadBadge = true

    private let playheadMs = 2_000

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Picker("Layout", selection: $variant) {
                ForEach(Variant.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .accessibilityIdentifier("soundVariantPicker")
            Text(variant.summary).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal).padding(.top, 4)

            mockTimeline
                .padding(.horizontal, 16).padding(.top, 12)
                .frame(maxHeight: .infinity, alignment: .top)

            mockMainRow
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .onChange(of: variant) { _, _ in sheetOpen = false; playing = nil; picked = nil }
        .sheet(isPresented: $sheetOpen, onDismiss: { playing = nil }) { soundSheet }
    }

    // MARK: Top + mock editor

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.title3).frame(width: 44, height: 44) }
                .accessibilityIdentifier("soundClose")
            Spacer()
            Text("Sound FX lab").font(.headline)
            Spacer()
            Menu {
                Toggle("Download badge on rows", isOn: $showsDownloadBadge)
                Button("Forget downloads") { downloaded = [] }
                Button("Clear the timeline", role: .destructive) { added = [] }
            } label: { Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44) }
        }
        .padding(.horizontal, 8)
    }

    /// A ten-second timeline with the playhead at 2 s; every Use puts a cyan clip on its own row there, so the result is visible.
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
                    ForEach(Array(added.suffix(5).enumerated()), id: \.element.id) { _, clip in
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.cyan.opacity(0.55))
                            .overlay(alignment: .leading) { Text(clip.sound.name).font(.caption2.weight(.semibold)).padding(.leading, 4).lineLimit(1) }
                            .frame(width: max(CGFloat(clip.sound.durationMs) * perMs, 26), height: 26)
                            .offset(x: CGFloat(clip.startMs) * perMs)
                            .accessibilityIdentifier("soundAdded")
                    }
                    if added.isEmpty {
                        Text("Nothing on the timeline yet - a sound you use lands at the playhead.").font(.footnote).foregroundColor(.secondary)
                            .padding(.top, 6)
                    }
                }
                Rectangle().fill(Color.primary).frame(width: 2).offset(x: CGFloat(playheadMs) * perMs - 1)
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast).font(.footnote.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.black.opacity(0.75), in: Capsule()).foregroundColor(.white)
                        .transition(.opacity)
                        .accessibilityIdentifier("soundToast")
                }
            }
            .animation(.easeOut(duration: 0.2), value: toast)
        }
        .frame(height: 220)
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var mockMainRow: some View {
        HStack(spacing: 8) {
            ForEach([("music.note", "Music"), ("waveform", "Sound FX"), ("mic", "Record")], id: \.1) { symbol, title in
                Button { if title == "Sound FX" { sheetOpen = true } } label: {
                    VStack(spacing: 4) {
                        Image(systemName: symbol).font(.title3)
                        Text(title).font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(title == "Sound FX" ? .primary : .secondary)
                }
                .accessibilityIdentifier(title == "Sound FX" ? "soundOpen" : "soundMock-\(title)")
            }
        }
        .padding(.horizontal, 16).frame(height: 56)
        .background(Color(.systemBackground))
    }

    // MARK: The sheet

    private var soundSheet: some View {
        NavigationStack {
            VStack(spacing: 10) {
                chips
                switch variant {
                case .list, .wave: rows
                case .grid: grid
                }
            }
            .padding(.top, 4)
            .navigationTitle("Sound FX")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { sheetOpen = false }.accessibilityIdentifier("soundDone") } }
        }
        .presentationDetents([.height(340), .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .height(340)))
    }

    private var visible: [LabSound] { LabSound.all.filter { category == nil || $0.category == category } }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", on: category == nil, id: "all") { category = nil }
                ForEach(LabSoundCategory.allCases) { c in chip(c.title, on: category == c, id: c.rawValue) { category = c } }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ title: String, on: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.medium))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(on ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                .foregroundColor(on ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("soundChip-\(id)")
    }

    // MARK: A / B rows

    private var rows: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(visible) { sound in
                    row(sound)
                    Divider().padding(.leading, 68)
                }
            }
            .padding(.horizontal, 16)
            Text("Starter sounds made by Neonix").font(.caption2).foregroundColor(.secondary).padding(.vertical, 12)
        }
        .accessibilityIdentifier("soundList")
    }

    private func row(_ sound: LabSound) -> some View {
        let isPlaying = playing?.id == sound.id
        return HStack(spacing: 12) {
            Button { toggle(sound) } label: {
                PlaybackProgress(start: isPlaying ? playing?.start : nil, durationMs: sound.durationMs) { progress in
                    PlayDisc(color: sound.category.color, playing: isPlaying, progress: progress)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("soundPlay-\(sound.id)")
            .accessibilityLabel("Play \(sound.name)")

            VStack(alignment: .leading, spacing: 3) {
                Text(sound.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                HStack(spacing: 5) {
                    Text("\(sound.category.title) · \(sound.seconds)").font(.caption).foregroundColor(.secondary)
                    if showsDownloadBadge, !downloaded.contains(sound.id) {
                        Image(systemName: "icloud.and.arrow.down").font(.caption2).foregroundColor(.secondary)
                    }
                }
                if variant == .wave {
                    PlaybackProgress(start: isPlaying ? playing?.start : nil, durationMs: sound.durationMs) { progress in
                        MiniWave(bars: sound.bars(40), progress: progress, color: sound.category.color)
                    }
                    .frame(height: 18)
                }
            }
            Spacer(minLength: 4)
            useButton(sound)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { toggle(sound) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("soundRow-\(sound.id)")
    }

    private func useButton(_ sound: LabSound) -> some View {
        Button { use(sound) } label: {
            Group {
                if downloading.contains(sound.id) { ProgressView().controlSize(.small) } else { Text("Use").font(.subheadline.weight(.semibold)) }
            }
            .frame(width: 52, height: 30)
            .background(Color.accentColor, in: Capsule())
            .foregroundColor(.white)
        }
        .buttonStyle(.plain)
        .disabled(downloading.contains(sound.id))
        .accessibilityIdentifier("soundUse-\(sound.id)")
    }

    // MARK: C grid

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(visible) { sound in tile(sound) }
            }
            .padding(.horizontal, 16).padding(.bottom, 12)
        }
        .accessibilityIdentifier("soundGrid")
        .safeAreaInset(edge: .bottom, spacing: 0) { if let picked { useBar(picked) } }
    }

    private func tile(_ sound: LabSound) -> some View {
        let isPlaying = playing?.id == sound.id
        let isPicked = picked == sound
        return Button { picked = sound; toggle(sound, forcePlay: true) } label: {
            VStack(spacing: 4) {
                PlaybackProgress(start: isPlaying ? playing?.start : nil, durationMs: sound.durationMs) { progress in
                    ZStack {
                        Circle().stroke(sound.category.color.opacity(0.25), lineWidth: 3)
                        Circle().trim(from: 0, to: progress).stroke(sound.category.color, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                        Image(systemName: sound.category.symbol).font(.title3).foregroundColor(sound.category.color)
                    }
                }
                .frame(width: 44, height: 44)
                Text(sound.name).font(.caption.weight(.medium)).lineLimit(1).foregroundColor(.primary)
                HStack(spacing: 3) {
                    Text(sound.seconds).font(.caption2).foregroundColor(.secondary)
                    if showsDownloadBadge, !downloaded.contains(sound.id) { Image(systemName: "icloud.and.arrow.down").font(.system(size: 9)).foregroundColor(.secondary) }
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.accentColor, lineWidth: isPicked ? 2 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("soundTile-\(sound.id)")
    }

    private func useBar(_ sound: LabSound) -> some View {
        HStack(spacing: 12) {
            Image(systemName: sound.category.symbol).foregroundColor(sound.category.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(sound.name).font(.subheadline.weight(.semibold))
                Text(sound.seconds).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            useButton(sound)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: Behaviour (all pretend)

    /// Tap on a row / play button: play that sound, or stop it when it is the one playing. The sound ends by itself after its length.
    private func toggle(_ sound: LabSound, forcePlay: Bool = false) {
        if playing?.id == sound.id, !forcePlay { playing = nil; return }
        let now = Playing(id: sound.id, start: Date())
        playing = now
        Task {
            try? await Task.sleep(for: .milliseconds(sound.durationMs))
            if playing?.id == now.id, playing?.start == now.start { playing = nil }
        }
    }

    /// Use: download first when it is not on the phone yet (a pretend second), then put it on the timeline at the playhead.
    private func use(_ sound: LabSound) {
        playing = nil
        guard downloaded.contains(sound.id) else {
            downloading.insert(sound.id)
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                downloading.remove(sound.id)
                downloaded.insert(sound.id)
                place(sound)
            }
            return
        }
        place(sound)
    }

    private func place(_ sound: LabSound) {
        added.append(Added(sound: sound, startMs: playheadMs))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        toast = "Added \(sound.name)"
        Task {
            try? await Task.sleep(for: .milliseconds(1600))
            toast = nil
        }
    }
}

// MARK: Pieces

/// Gives its content the playback progress (0...1) of a sound that started at `start`, redrawn every frame only while one plays.
private struct PlaybackProgress<Content: View>: View {
    let start: Date?
    let durationMs: Int
    @ViewBuilder let content: (Double) -> Content

    var body: some View {
        if let start {
            SwiftUI.TimelineView(.animation) { context in
                content(min(context.date.timeIntervalSince(start) / (Double(durationMs) / 1000), 1))
            }
        } else {
            content(0)
        }
    }
}

private struct PlayDisc: View {
    let color: Color
    let playing: Bool
    let progress: Double

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.14))
            Circle().trim(from: 0, to: progress).stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
            Image(systemName: playing ? "stop.fill" : "play.fill").font(.system(size: 15)).foregroundColor(color)
        }
        .frame(width: 44, height: 44)
    }
}

/// Fake loudness bars; the played part is coloured.
private struct MiniWave: View {
    let bars: [Double]
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 1.5) {
                ForEach(Array(bars.enumerated()), id: \.offset) { index, value in
                    Capsule()
                        .fill(Double(index) / Double(bars.count) < progress ? color : color.opacity(0.28))
                        .frame(height: max(geo.size.height * value, 2))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: Fake data

enum LabSoundCategory: String, CaseIterable, Identifiable {
    case transitions, ui, impacts, fun, game
    var id: String { rawValue }

    var title: String {
        switch self {
        case .transitions: return "Transitions"
        case .ui: return "UI"
        case .impacts: return "Impacts"
        case .fun: return "Fun"
        case .game: return "Game & Magic"
        }
    }

    var symbol: String {
        switch self {
        case .transitions: return "wind"
        case .ui: return "bell.fill"
        case .impacts: return "burst.fill"
        case .fun: return "face.smiling.fill"
        case .game: return "gamecontroller.fill"
        }
    }

    var color: Color {
        switch self {
        case .transitions: return .blue
        case .ui: return .green
        case .impacts: return .orange
        case .fun: return .pink
        case .game: return .purple
        }
    }
}

struct LabSound: Identifiable, Hashable {
    let id: String
    let name: String
    let category: LabSoundCategory
    let durationMs: Int

    var seconds: String { String(format: "%.1f s", Double(durationMs) / 1000) }

    /// Loudness bars seeded by the id (stable between draws): a swell for risers, a bell for whooshes, a fast decay for hits.
    func bars(_ count: Int) -> [Double] {
        var seed = id.utf8.reduce(UInt64(17)) { ($0 &* 31) &+ UInt64($1) }
        return (0..<count).map { index in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let jitter = 0.55 + 0.45 * Double((seed >> 33) % 1000) / 1000
            let x = Double(index) / Double(count - 1)
            let shape: Double
            switch (category, id) {
            case (_, "sfx-riser"), (_, "sfx-reverse-sweep"): shape = pow(x, 1.4)
            case (.transitions, _): shape = sin(.pi * x)
            default: shape = exp(-3.2 * x)
            }
            return max(0.08, min(1, shape * jitter))
        }
    }

    static let all: [LabSound] = [
        LabSound(id: "sfx-whoosh-soft", name: "Whoosh Soft", category: .transitions, durationMs: 750),
        LabSound(id: "sfx-whoosh-fast", name: "Whoosh Fast", category: .transitions, durationMs: 400),
        LabSound(id: "sfx-riser", name: "Riser", category: .transitions, durationMs: 2000),
        LabSound(id: "sfx-reverse-sweep", name: "Reverse Sweep", category: .transitions, durationMs: 1100),
        LabSound(id: "sfx-pop", name: "Pop", category: .ui, durationMs: 180),
        LabSound(id: "sfx-click", name: "Click", category: .ui, durationMs: 50),
        LabSound(id: "sfx-notification", name: "Notification", category: .ui, durationMs: 900),
        LabSound(id: "sfx-success", name: "Success", category: .ui, durationMs: 1200),
        LabSound(id: "sfx-error", name: "Error", category: .ui, durationMs: 400),
        LabSound(id: "sfx-boom", name: "Boom", category: .impacts, durationMs: 2200),
        LabSound(id: "sfx-punch", name: "Punch", category: .impacts, durationMs: 300),
        LabSound(id: "sfx-kick", name: "Kick Drum", category: .impacts, durationMs: 450),
        LabSound(id: "sfx-boing", name: "Boing", category: .fun, durationMs: 900),
        LabSound(id: "sfx-slide-up", name: "Slide Whistle Up", category: .fun, durationMs: 850),
        LabSound(id: "sfx-slide-down", name: "Slide Whistle Down", category: .fun, durationMs: 850),
        LabSound(id: "sfx-bonk", name: "Bonk", category: .fun, durationMs: 300),
        LabSound(id: "sfx-coin", name: "Coin", category: .game, durationMs: 500),
        LabSound(id: "sfx-power-up", name: "Power Up", category: .game, durationMs: 900),
        LabSound(id: "sfx-laser", name: "Laser", category: .game, durationMs: 400),
        LabSound(id: "sfx-sparkle", name: "Sparkle", category: .game, durationMs: 1300),
    ]
}
