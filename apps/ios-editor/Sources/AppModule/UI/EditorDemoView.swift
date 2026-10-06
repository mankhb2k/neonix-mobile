import AVFoundation
import SwiftUI

enum DemoMedia: String, CaseIterable, Identifiable {
    case photo, videoPortrait, videoLandscape
    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo: return "Photo"
        case .videoPortrait: return "Video A (portrait)"
        case .videoLandscape: return "Video B (landscape)"
        }
    }

    var layerKind: String { self == .photo ? "image" : "video" }
    var isVideo: Bool { self != .photo }

    var asset: V2Asset {
        switch self {
        case .photo:
            return .image(V2ImageAsset(id: "photo", uri: "pexels-followingnyc-38428141.jpg", width: 3648, height: 5472))
        case .videoPortrait:
            return .video(V2VideoAsset(id: "video-a", uri: "13792197_1080_1920_30fps.mp4", width: 1080, height: 1920, duration: 31200))
        case .videoLandscape:
            return .video(V2VideoAsset(id: "video-b", uri: "12253998_1920_1080_30fps.mp4", width: 1920, height: 1080, duration: 12345))
        }
    }
}

/// Exercises the Editor-tier effect presets from `EffectPresets.swift` —
/// see CLAUDE.md's "Protocol V2 stays atomic" rule: picking one of these
/// compiles to a `V2Filter` primitive chain, never a named effect field on
/// the layer itself.
enum EffectOption: String, CaseIterable, Identifiable {
    case none, blur, outerGlow, sepia
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "None"
        case .blur: return "Blur"
        case .outerGlow: return "Outer glow"
        case .sepia: return "Sepia"
        }
    }
    var preset: EffectPresetKind? {
        switch self {
        case .none: return nil
        case .blur: return .blur(radius: 6)
        case .outerGlow: return .outerGlow(radius: 12, color: "#FFD60Aff", opacity: 0.9)
        case .sepia: return .sepia(amount: 0.8)
        }
    }
}

enum PresetOption: String, CaseIterable, Identifiable {
    case none, fade, slide, zoom
    var id: String { rawValue }
    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    var kind: PresetKind? {
        switch self {
        case .none: return nil
        case .fade: return .fade
        case .slide: return .slide
        case .zoom: return .zoom
        }
    }
}

/// Demonstrates the other half of the two-tier model in ARCHITECTURE.md:
/// an Editor Document (media + named in/out preset bindings) compiled by
/// `PresetCompiler.compile(_:)` into the same `V2Project`/Runtime/renderer
/// path the static fixtures use. Changing either preset picker rebuilds and
/// re-saves **both** documents, so the two-tier persistence is provable, not
/// just designed on paper.
///
/// Video playback is hybrid, by design (see the plan this was built from):
/// pressing Play on a video hands the clock to a real `AVPlayer` for smooth
/// decoded playback, with `currentTimeMs` following its periodic time
/// observer. Pausing or scrubbing the slider hands the clock back to the
/// shared `playbackTimer`/manual drag, rendering a `VideoFrameCache`
/// extracted still frame instead — precise instant feedback matters more
/// than smoothness while scrubbing.
struct EditorDemoView: View {
    @State private var selectedMedia: DemoMedia = .videoPortrait
    // Defaults to Fade/Fade on purpose: both touch `opacity`, exercising the
    // compiler's same-path merge (see `PresetCompiler.compile`).
    @State private var inOption: PresetOption = .fade
    @State private var outOption: PresetOption = .fade
    @State private var effectOption: EffectOption = .none

    @State private var project: V2Project = compile(EditorDemoView.makeDocument(media: .videoPortrait, inOption: .fade, outOption: .fade, effectOption: .none))
    @State private var currentTimeMs: Double = 0
    @State private var isPlaying = false
    @State private var lastTick: Date = .init()
    @State private var lastSavedAt: Date?

    @State private var avPlayer: AVPlayer?
    @State private var timeObserver: Any?

    private var maxDurationMs: Double {
        max(project.layers.map { $0.timing.start + $0.timing.duration }.max() ?? 1, 1)
    }

    var body: some View {
        VStack(spacing: 16) {
            Picker("Media", selection: $selectedMedia) {
                ForEach(DemoMedia.allCases) { media in
                    Text(media.title).tag(media)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            HStack {
                Labeled("In") {
                    Picker("In effect", selection: $inOption) {
                        ForEach(PresetOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Labeled("Out") {
                    Picker("Out effect", selection: $outOption) {
                        ForEach(PresetOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Labeled("Effect") {
                    Picker("Visual effect", selection: $effectOption) {
                        ForEach(EffectOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .padding(.horizontal)

            let frames = project.layers.map { sampleLayer($0, atMs: currentTimeMs) }
            PreviewCanvas(
                composition: project.composition,
                assets: project.assets,
                frames: frames,
                activePlayer: (isPlaying && selectedMedia.isVideo) ? avPlayer.map { (selectedMedia.asset.id, $0) } : nil
            )
            .aspectRatio(project.composition.width / project.composition.height, contentMode: .fit)
            .padding()

            HStack {
                Button(isPlaying ? "Pause" : "Play") {
                    isPlaying ? pausePlayback() : startPlayback()
                }
                Slider(value: $currentTimeMs, in: 0...maxDurationMs) { editing in
                    if editing { pausePlayback() }
                    lastTick = .init()
                }
                Text("\(Int(currentTimeMs)) ms")
                    .monospacedDigit()
                    .frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal)

            if let lastSavedAt {
                Text("Saved both documents at \(lastSavedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { rebuild() }
        .onChange(of: selectedMedia) { _, _ in rebuild() }
        .onChange(of: inOption) { _, _ in rebuild() }
        .onChange(of: outOption) { _, _ in rebuild() }
        .onChange(of: effectOption) { _, _ in rebuild() }
        .onReceive(playbackTimer) { now in
            // While a video is actively playing, the AVPlayer time observer
            // (started in `startPlayback`) is the clock instead — advancing
            // here too would fight it.
            guard isPlaying, !(selectedMedia.isVideo && avPlayer != nil) else { return }
            let deltaMs = now.timeIntervalSince(lastTick) * 1000
            lastTick = now
            currentTimeMs = (currentTimeMs + deltaMs).truncatingRemainder(dividingBy: maxDurationMs)
        }
    }

    private func startPlayback() {
        isPlaying = true
        lastTick = .init()
        guard selectedMedia.isVideo, let url = bundledURL(filename: selectedMedia.asset.uri) else { return }
        let player = avPlayer ?? AVPlayer(url: url)
        avPlayer = player
        player.seek(to: CMTime(seconds: currentTimeMs / 1000, preferredTimescale: 600))
        player.play()
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let ms = time.seconds * 1000
            if ms >= maxDurationMs {
                player.seek(to: .zero)
                currentTimeMs = 0
            } else {
                currentTimeMs = ms
            }
        }
    }

    private func pausePlayback() {
        isPlaying = false
        avPlayer?.pause()
        if let timeObserver {
            avPlayer?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    private func rebuild() {
        pausePlayback()
        avPlayer = nil
        let document = Self.makeDocument(media: selectedMedia, inOption: inOption, outOption: outOption, effectOption: effectOption)
        project = compile(document)
        currentTimeMs = 0
        saveDocuments(editor: document, project: project)
        lastSavedAt = .init()
    }

    static func makeDocument(media: DemoMedia, inOption: PresetOption, outOption: PresetOption, effectOption: EffectOption) -> EditorDocument {
        let asset = media.asset
        let layer = EditorLayer(
            id: "demo-layer",
            kind: media.layerKind,
            assetId: asset.id,
            fill: nil,
            frame: V2Frame(width: 240, height: 320),
            timing: V2Timing(start: 0, duration: 2500),
            inPreset: inOption.kind.map { PresetBinding(kind: $0, durationMs: 500) },
            outPreset: outOption.kind.map { PresetBinding(kind: $0, durationMs: 500) },
            effectPresets: effectOption.preset.map { [$0] }
        )
        return EditorDocument(
            id: "editor-demo",
            composition: V2Composition(width: 320, height: 320, fps: 30, background: "#101820"),
            assets: [asset],
            layers: [layer]
        )
    }

    private func saveDocuments(editor: EditorDocument, project: V2Project) {
        guard let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(editor) {
            try? data.write(to: docsURL.appendingPathComponent("editor-document.json"))
        }
        if let data = try? encoder.encode(project) {
            try? data.write(to: docsURL.appendingPathComponent("project-v2.json"))
        }
    }
}

struct Labeled<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content
        }
    }
}
