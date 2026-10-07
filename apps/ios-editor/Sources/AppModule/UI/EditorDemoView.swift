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

/// A named shorthand for a `V2Easing.cubicBezier` curve — see
/// `PresetBinding.easing`'s doc comment and CLAUDE.md's "Protocol V2 must
/// stay atomic" rule: the name lives only here, at the Editor tier.
enum EasingOption: String, CaseIterable, Identifiable {
    case linear, easeIn, easeOut, easeInOut
    var id: String { rawValue }
    var title: String {
        switch self {
        case .linear: return "Linear"
        case .easeIn: return "Ease In"
        case .easeOut: return "Ease Out"
        case .easeInOut: return "Ease In Out"
        }
    }
    /// `nil` for "linear" — `PresetBinding.easing` stores `nil` the same
    /// way for "no easing chosen", so there's one representation for
    /// linear, not two.
    var bindingValue: String? { self == .linear ? nil : rawValue }
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
    /// Shared by both in and out, to keep this demo's UI simple — a real
    /// editor would let each binding pick its own.
    @State private var easingOption: EasingOption = .linear

    @State private var project: V2Project = compile(EditorDemoView.makeDocument(media: .videoPortrait, inOption: .fade, outOption: .fade, effectOption: .none, easingOption: .linear))
    @State private var currentTimeMs: Double = 0
    @State private var isPlaying = false
    @State private var lastTick: Date = .init()
    @State private var lastSavedAt: Date?

    /// Proves the "Group layers compose transform/opacity by real view
    /// nesting" design (see CLAUDE.md): a continuous rotation the object
    /// would own *itself* (standing in for a future real custom-keyframe
    /// authoring UI, which doesn't exist yet — see `injectCustomRotation`),
    /// running the whole clip, at the same time as an in/out preset that
    /// now always wraps the object in a synthetic parent layer. If both
    /// animate correctly together — the preset's fade/slide/zoom on the
    /// wrapper, the spin on the object itself — the two never had to share
    /// one track list, proving the CapCut-style "object already has its own
    /// animation, effect still applies independently" scenario.
    @State private var customRotationEnabled = false
    @State private var motionPathEnabled = false
    /// Which JSON this demo shows below the controls — "protocol" (compiled
    /// output, where the wrapper/child split is visible) vs. "editor"
    /// (authored intent, which never mentions wrapping at all).
    @State private var jsonTab: String = "protocol"
    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    @State private var avPlayer: AVPlayer?
    @State private var timeObserver: Any?
    @State private var currentDocument: EditorDocument?

    private var maxDurationMs: Double {
        max(project.layers.map { $0.timing.start + $0.timing.duration }.max() ?? 1, 1)
    }

    var body: some View {
        // `ScrollView`-wrapped because the JSON panel below makes this
        // taller than one screen — without it, a plain `VStack` taller than
        // its proposed frame gets centered within the full window bounds
        // (ignoring the status bar/safe area) instead of just overflowing
        // off the bottom, which is what actually pushed the top controls up
        // behind the status bar. See CLAUDE.md if this regresses again.
        ScrollView {
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

            Labeled("Easing (in/out)") {
                Picker("Easing", selection: $easingOption) {
                    ForEach(EasingOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal)

            Toggle("Object's own animation (continuous spin)", isOn: $customRotationEnabled)
                .padding(.horizontal)

            Toggle("Motion path (travel around a square)", isOn: $motionPathEnabled)
                .padding(.horizontal)

            PreviewCanvas(
                composition: project.composition,
                assets: project.assets,
                layers: project.layers,
                atMs: currentTimeMs,
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

            // JSON side-by-side with the preview so the wrapper/child split
            // (or its absence, with no preset picked) is directly
            // inspectable — e.g. confirming the object's own id never
            // changes whether or not it's wrapped, and `parentLayerId`
            // appears exactly when a preset is present.
            Labeled("JSON (\(jsonTab == "protocol" ? "Protocol V2 — compiled" : "Editor Document — authored intent"))") {
                Picker("JSON", selection: $jsonTab) {
                    Text("Protocol V2").tag("protocol")
                    Text("Editor").tag("editor")
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal)

            ScrollView([.horizontal, .vertical]) {
                Text(jsonTab == "protocol" ? prettyJSON(project) : (currentDocument.map(prettyJSON) ?? ""))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white)
                    .fixedSize()
                    .padding(8)
            }
            .frame(height: 280)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.85))
            .padding(.horizontal)
            }
        }
        .onAppear { rebuild() }
        .onChange(of: selectedMedia) { _, _ in rebuild() }
        .onChange(of: inOption) { _, _ in rebuild() }
        .onChange(of: outOption) { _, _ in rebuild() }
        .onChange(of: effectOption) { _, _ in rebuild() }
        .onChange(of: easingOption) { _, _ in rebuild() }
        .onChange(of: customRotationEnabled) { _, _ in rebuild() }
        .onChange(of: motionPathEnabled) { _, _ in rebuild() }
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
        let document = Self.makeDocument(media: selectedMedia, inOption: inOption, outOption: outOption, effectOption: effectOption, easingOption: easingOption)
        currentDocument = document
        project = injectCustomRotation(compile(document))
        currentTimeMs = 0
        saveDocuments(editor: document, project: project)
        lastSavedAt = .init()
    }

    /// Stands in for a real custom-keyframe authoring UI (not built yet —
    /// `EditorLayer` only knows the 6 fixed in/out presets today) just
    /// enough to prove the wrapper/child composition handles an
    /// independently-animated object correctly, and to exercise
    /// `layer.motion` (no `PresetCompiler` support for it yet either — see
    /// CLAUDE.md's motion-path note). Mutates the *already* wrapper/child
    /// -split compiled output directly, finding the object's own layer by
    /// id (its id is stable whether or not it got wrapped — see
    /// `PresetCompiler.compile`) and adding tracks/`motion` straight onto
    /// it, same as any other layer's own data.
    private func injectCustomRotation(_ project: V2Project) -> V2Project {
        guard customRotationEnabled || motionPathEnabled else { return project }
        let layers = project.layers.map { layer -> V2Layer in
            guard layer.id == "demo-layer" else { return layer }
            var layer = layer
            var tracks = layer.tracks ?? []
            if customRotationEnabled {
                tracks.append(V2Track(
                    id: "demo-layer-custom-spin", path: "transform.rotate.z",
                    keyframes: [
                        V2Keyframe(time: .absolute(0), value: 0),
                        V2Keyframe(time: .absolute(layer.timing.duration), value: 360),
                    ],
                    animation: nil
                ))
            }
            if motionPathEnabled {
                // A 150x150 square, traced once over the clip's duration —
                // picked for a demo because the vertices make the "auto"
                // rotate-to-tangent behavior easy to see at a glance (a
                // clean 90° turn at each corner, unlike a circle's
                // continuously-changing tangent).
                layer.motion = V2MotionPath(
                    offsetPath: V2OffsetPath(contours: [
                        V2PathContour(
                            id: "square", start: V2PathPoint(x: 0, y: 0),
                            segments: [
                                .line(to: V2PathPoint(x: 150, y: 0)),
                                .line(to: V2PathPoint(x: 150, y: 150)),
                                .line(to: V2PathPoint(x: 0, y: 150)),
                            ],
                            closed: true
                        ),
                    ]),
                    offsetAnchor: V2OffsetAnchor(x: 20, y: 20)
                )
                tracks.append(V2Track(
                    id: "demo-layer-motion-travel", path: "motion.offsetDistance",
                    keyframes: [
                        V2Keyframe(time: .absolute(0), value: 0),
                        V2Keyframe(time: .absolute(layer.timing.duration), value: 1),
                    ],
                    animation: nil
                ))
            }
            layer.tracks = tracks
            return layer
        }
        return V2Project(
            id: project.id, composition: project.composition, assets: project.assets,
            markers: project.markers, clipPaths: project.clipPaths, masks: project.masks,
            filters: project.filters, paintServers: project.paintServers, layers: layers, audio: project.audio
        )
    }

    private func prettyJSON<T: Encodable>(_ value: T) -> String {
        guard let data = try? Self.jsonEncoder.encode(value), let string = String(data: data, encoding: .utf8) else {
            return "(encode failed)"
        }
        return string
    }

    static func makeDocument(media: DemoMedia, inOption: PresetOption, outOption: PresetOption, effectOption: EffectOption, easingOption: EasingOption) -> EditorDocument {
        let asset = media.asset
        let layer = EditorLayer(
            id: "demo-layer",
            kind: media.layerKind,
            assetId: asset.id,
            fill: nil,
            frame: V2Frame(width: 240, height: 320),
            timing: V2Timing(start: 0, duration: 2500),
            inPreset: inOption.kind.map { PresetBinding(kind: $0, durationMs: 500, easing: easingOption.bindingValue) },
            outPreset: outOption.kind.map { PresetBinding(kind: $0, durationMs: 500, easing: easingOption.bindingValue) },
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
