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

    private let sampleText = "The quick brown fox jumps over the lazy dog"
    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private var document: EditorDocument {
        let layer = EditorLayer(
            id: "headline",
            kind: "text",
            frame: V2Frame(width: frameWidth, height: 200),
            timing: V2Timing(start: 0, duration: 1000),
            text: EditorTextLayer(
                text: sampleText,
                fontFamily: "Helvetica",
                fontSize: 22,
                color: "#F5F5F5ff",
                layout: EditorTextLayoutIntent(textAlign: textAlign, wrap: wrap)
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
        let frames = project.layers.map { sampleLayer($0, atMs: 0) }

        ScrollView {
            VStack(spacing: 16) {
                PreviewCanvas(composition: project.composition, assets: project.assets, frames: frames)
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
        .onAppear { saveDocuments() }
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
