import SwiftUI

/// Demonstrates the Editor/Protocol V2 split for text layout (see CLAUDE.md's
/// "Text layout stays atomic" note): changing width/align/wrap re-runs the
/// real Core Text compiler (`TextLayoutCompiler`) and re-saves both
/// documents, the same two-tier persistence proof `EditorDemoView` uses for
/// animation/effect presets — `editor-document.json` keeps the wrap/align
/// *intent*, `project-v2.json` only ever contains already-shaped line
/// positions.
struct TextWrapDemoView: View {
    @State private var frameWidth: Double = 220
    @State private var textAlign: String = "center"
    @State private var wrap: String = "word"
    /// Which JSON this demo shows below the controls, for side-by-side
    /// comparison against the rendered preview while testing — "protocol"
    /// (compiled, atomic) vs. "editor" (authored intent).
    @State private var jsonTab: String = "protocol"

    /// Typewriter reveal demo — see CLAUDE.md's "`rangeSelectors` stays in
    /// Protocol V2" note: this is the one Editor intent that compiles into a
    /// compact, *unexpanded* Protocol V2 field rather than fully atomic
    /// per-character tracks, so it needs real time-based playback (unlike
    /// the static width/align/wrap preview above) to actually prove the
    /// Runtime interprets it correctly.
    @State private var typewriterEnabled = false
    @State private var perUnitDelayMs: Double = 60
    /// Defaults to "instant" (no fade) — this test is meant to show the
    /// stagger *mechanism* (timing + per-character position) truthfully,
    /// without a fade effect blending adjacent frames and making the
    /// timing/position harder to judge by eye. "fade" is still a real,
    /// available Editor choice — see `EditorTypewriterIntent.reveal`.
    @State private var reveal: String = "instant"
    @State private var currentTimeMs: Double = 0

    /// Per-character shape effects — exercise `V2TextChunk.dx`/`.dy`/
    /// `.rotate`, the other remaining unaudited Text fields (see CLAUDE.md).
    /// Both are static (no playback needed): the numbers are already fully
    /// resolved per character at compile time. "none" | "wave" | "path".
    @State private var shapeEffect: String = "none"
    @State private var waveAmplitude: Double = 10
    @State private var pathRadius: Double = 120
    @State private var pathStartOffset: Double = 0
    @State private var isPlaying = false
    @State private var lastTick: Date = .init()

    private let sampleText = "The quick brown fox jumps over the lazy dog"
    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    /// Long enough to let every character finish its own stagger delay plus
    /// the template track's own 300ms fade — otherwise the last characters
    /// would clamp mid-fade forever (`sampleLayer`/`resolveTextRuns` clamp
    /// local time to `layer.timing.duration`, same as every other track).
    private var maxDurationMs: Double {
        guard typewriterEnabled else { return 1000 }
        return Double(sampleText.utf16.count) * perUnitDelayMs + 500
    }

    private var document: EditorDocument {
        let layer = EditorLayer(
            id: "headline",
            kind: "text",
            frame: V2Frame(width: frameWidth, height: 200),
            timing: V2Timing(start: 0, duration: maxDurationMs),
            text: EditorTextLayer(
                text: sampleText,
                fontFamily: "Helvetica",
                fontSize: 22,
                color: "#F5F5F5ff",
                layout: EditorTextLayoutIntent(textAlign: textAlign, wrap: wrap),
                typewriter: typewriterEnabled ? EditorTypewriterIntent(perUnitDelayMs: perUnitDelayMs, direction: "forward", reveal: reveal) : nil,
                wave: shapeEffect == "wave" ? EditorTextWaveIntent(amplitude: waveAmplitude, rotationDegrees: 20, periodChars: 8) : nil,
                textPath: shapeEffect == "path" ? EditorTextPathIntent(radius: pathRadius, startOffset: pathStartOffset) : nil
            )
        )
        return EditorDocument(
            id: "text-wrap-demo",
            composition: V2Composition(width: 320, height: 240, fps: 30, background: "#101820"),
            assets: [],
            layers: [layer]
        )
    }

    private func prettyJSON<T: Encodable>(_ value: T) -> String {
        guard let data = try? Self.jsonEncoder.encode(value), let string = String(data: data, encoding: .utf8) else {
            return "(encode failed)"
        }
        return string
    }

    var body: some View {
        let project = compile(document)

        ScrollView {
            VStack(spacing: 16) {
                PreviewCanvas(composition: project.composition, assets: project.assets, layers: project.layers, atMs: currentTimeMs)
                    .aspectRatio(project.composition.width / project.composition.height, contentMode: .fit)
                    .padding()

                Labeled("Width: \(Int(frameWidth))px") {
                    Slider(value: $frameWidth, in: 120...320)
                }
                .padding(.horizontal)

                HStack {
                    Labeled("Align") {
                        Picker("Align", selection: $textAlign) {
                            Text("Left").tag("left")
                            Text("Center").tag("center")
                            Text("Right").tag("right")
                        }
                        .pickerStyle(.segmented)
                    }
                    Labeled("Wrap") {
                        Picker("Wrap", selection: $wrap) {
                            Text("None").tag("none")
                            Text("Word").tag("word")
                            Text("Char").tag("character")
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .padding(.horizontal)

                Toggle("Typewriter reveal (rangeSelectors)", isOn: $typewriterEnabled)
                    .padding(.horizontal)

                if typewriterEnabled {
                    Labeled("Per-character delay: \(Int(perUnitDelayMs))ms") {
                        Slider(value: $perUnitDelayMs, in: 20...150)
                    }
                    .padding(.horizontal)

                    Labeled("Reveal") {
                        Picker("Reveal", selection: $reveal) {
                            Text("Instant").tag("instant")
                            Text("Fade").tag("fade")
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.horizontal)

                    HStack {
                        Button(isPlaying ? "Pause" : "Play") {
                            isPlaying.toggle()
                            lastTick = .init()
                        }
                        Slider(value: $currentTimeMs, in: 0...maxDurationMs) { editing in
                            if editing { isPlaying = false }
                            lastTick = .init()
                        }
                        Text("\(Int(currentTimeMs)) ms")
                            .monospacedDigit()
                            .frame(width: 70, alignment: .trailing)
                    }
                    .padding(.horizontal)
                }

                Labeled("Shape effect (dx/dy/rotate)") {
                    Picker("Shape effect", selection: $shapeEffect) {
                        Text("None").tag("none")
                        Text("Wave").tag("wave")
                        Text("Path").tag("path")
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)

                if shapeEffect == "wave" {
                    Labeled("Amplitude: \(Int(waveAmplitude))pt") {
                        Slider(value: $waveAmplitude, in: 2...24)
                    }
                    .padding(.horizontal)
                } else if shapeEffect == "path" {
                    Labeled("Circle radius: \(Int(pathRadius))pt") {
                        Slider(value: $pathRadius, in: 40...140)
                    }
                    .padding(.horizontal)
                    Labeled("Start offset: \(Int(pathStartOffset))pt") {
                        Slider(value: $pathStartOffset, in: 0...200)
                    }
                    .padding(.horizontal)
                }

                // JSON side-by-side with the rendered preview above, so a
                // width/align/wrap change can be checked both visually and
                // structurally (e.g. confirming `layout` never grows a
                // `textAlign`/`wrap` key, and chunk count/x/y track the
                // picked combination) without pulling the file off the
                // simulator by hand.
                Labeled("JSON (\(jsonTab == "protocol" ? "Protocol V2 — compiled" : "Editor Document — authored intent"))") {
                    Picker("JSON", selection: $jsonTab) {
                        Text("Protocol V2").tag("protocol")
                        Text("Editor").tag("editor")
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)

                ScrollView([.horizontal, .vertical]) {
                    Text(jsonTab == "protocol" ? prettyJSON(project) : prettyJSON(document))
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
        .onChange(of: frameWidth) { _, _ in saveDocuments() }
        .onChange(of: textAlign) { _, _ in saveDocuments() }
        .onChange(of: wrap) { _, _ in saveDocuments() }
        .onChange(of: typewriterEnabled) { _, _ in resetPlayback() }
        .onChange(of: perUnitDelayMs) { _, _ in saveDocuments() }
        .onChange(of: reveal) { _, _ in saveDocuments() }
        .onChange(of: shapeEffect) { _, _ in saveDocuments() }
        .onChange(of: waveAmplitude) { _, _ in saveDocuments() }
        .onChange(of: pathRadius) { _, _ in saveDocuments() }
        .onChange(of: pathStartOffset) { _, _ in saveDocuments() }
        .onAppear { saveDocuments() }
        .onReceive(playbackTimer) { now in
            guard isPlaying else { return }
            let deltaMs = now.timeIntervalSince(lastTick) * 1000
            lastTick = now
            currentTimeMs = min(currentTimeMs + deltaMs, maxDurationMs)
            if currentTimeMs >= maxDurationMs { isPlaying = false }
        }
    }

    private func resetPlayback() {
        isPlaying = false
        currentTimeMs = 0
        lastTick = .init()
        saveDocuments()
    }

    private func saveDocuments() {
        guard let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        if let data = try? Self.jsonEncoder.encode(document) {
            try? data.write(to: docsURL.appendingPathComponent("text-editor-document.json"))
        }
        if let data = try? Self.jsonEncoder.encode(compile(document)) {
            try? data.write(to: docsURL.appendingPathComponent("text-project-v2.json"))
        }
    }
}
