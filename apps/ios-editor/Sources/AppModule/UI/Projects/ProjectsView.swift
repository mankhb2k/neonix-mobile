import SwiftUI

/// Placeholder sample data — no persisted-project store exists yet. Each
/// sample's own aspect ratio exercises a different Stage shape; see
/// `ui-design-note.md` (repo root).
struct ProjectSample: Identifiable {
    let id = UUID()
    let name: String
    let lastEdited: String
    let gradient: [Color]
    let compositionWidth: Double
    let compositionHeight: Double
}

private struct ProjectRow: View {
    let project: ProjectSample

    var body: some View {
        HStack(spacing: 12) {
            LinearGradient(colors: project.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name).font(.body.weight(.medium))
                Text("Edited \(project.lastEdited)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

struct ProjectsView: View {
    @State private var projects: [ProjectSample] = [
        ProjectSample(name: "Trip to Paris", lastEdited: "2 hours ago", gradient: [.blue, .teal], compositionWidth: 360, compositionHeight: 640), // 9:16
        ProjectSample(name: "Product Launch", lastEdited: "Yesterday", gradient: [.pink, .purple], compositionWidth: 640, compositionHeight: 360), // 16:9
        ProjectSample(name: "Birthday Recap", lastEdited: "3 days ago", gradient: [.orange, .yellow], compositionWidth: 480, compositionHeight: 480), // 1:1
    ]
    // `fullScreenCover`, not `NavigationLink` — a pushed page inside a
    // `TabView` leaves this tab's own tab bar showing underneath it.
    @State private var openedProject: ProjectSample?

    var body: some View {
        List {
            ForEach(projects) { project in
                Button {
                    openedProject = project
                } label: {
                    ProjectRow(project: project)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    projects.insert(ProjectSample(name: "New Project", lastEdited: "Just now", gradient: [.gray, .black], compositionWidth: 360, compositionHeight: 640), at: 0)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .fullScreenCover(item: $openedProject) { project in
            EditorShellView(project: Self.openEditorProject(for: project))
        }
    }

    /// "Trip to Paris" (the 9:16 sample) gets extra demo content — a
    /// standalone audio track + a text lane — so the Timeline's lane UI
    /// (video lane, text lane, audio lane) has something real to show,
    /// per the user's own request 2026-10-08. The other 2 samples are
    /// untouched (still just the plain compiled video). See `CLAUDE.md`'s
    /// audio design note and "Timeline lanes" note for the model this
    /// follows.
    private static func openEditorProject(for project: ProjectSample) -> V2Project {
        let videoProject = compile(EditorDemoView.makeDocument(
            media: .videoPortrait, inOption: .none, outOption: .none,
            effectOption: .none, easingOption: .linear,
            composition: V2Composition(width: project.compositionWidth, height: project.compositionHeight, fps: 30, background: "#101820"),
            frame: V2Frame(width: project.compositionWidth, height: project.compositionHeight)
        ))
        guard project.name == "Trip to Paris" else { return videoProject }

        // Stretched from the demo's own default 2500ms so there's enough
        // room to see the text lane and audio lane overlap/diverge from
        // the main video lane.
        var videoLayers = videoProject.layers
        for index in videoLayers.indices {
            videoLayers[index].timing = V2Timing(start: videoLayers[index].timing.start, duration: 8000)
        }

        // A text lane — compiled separately (its own `EditorDocument`,
        // through the real `TextLayoutCompiler`/`PresetCompiler` pipeline,
        // not a hand-built `V2TextLayerPayload`) then merged in with its
        // own lane `order`, since `compile(_:)` itself has no lane concept
        // (every compiled layer defaults to `order: 0`).
        let textProject = compile(EditorDocument(
            id: "trip-to-paris-text",
            composition: videoProject.composition,
            assets: [],
            layers: [
                EditorLayer(
                    id: "demo-text", kind: "text",
                    frame: V2Frame(width: project.compositionWidth, height: 80),
                    timing: V2Timing(start: 1000, duration: 3000),
                    text: EditorTextLayer(
                        text: "Trip to Paris",
                        fontFamily: "Helvetica",
                        fontSize: 28,
                        color: "#FFFFFFff",
                        layout: EditorTextLayoutIntent(textAlign: "center", wrap: "none")
                    )
                ),
            ]
        ))
        let textLayers: [V2Layer] = textProject.layers.map { layer in
            var copy = layer
            copy.order = 1
            return copy
        }

        // A standalone audio clip — a real `V2AudioClip` in
        // `V2AudioDomain`, independent of any video's embedded audio.
        let audioAsset = V2Asset.audio(V2AudioAsset(id: "audio-demo", uri: "audio-demo.mp3", mimeType: "audio/mpeg", duration: 262_500))
        let audioTrack = V2AudioTrack(
            id: "track-1", pan: 0, muted: false,
            clips: [
                V2AudioClip(
                    id: "audio-clip-1", assetId: "audio-demo",
                    timing: V2AudioClipTiming(start: 0, duration: 8000),
                    trim: V2AudioClipTrim(start: 0, end: nil),
                    playbackRate: 1
                ),
            ]
        )

        return V2Project(
            composition: videoProject.composition,
            assets: videoProject.assets + [audioAsset],
            filters: videoProject.filters,
            layers: videoLayers + textLayers,
            audio: V2AudioDomain(sampleRate: 48000, tracks: [audioTrack])
        )
    }
}
