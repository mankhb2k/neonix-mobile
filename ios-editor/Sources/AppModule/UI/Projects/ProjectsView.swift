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
    var editorProject: V2Project? = nil
}

private struct ProjectRow: View {
    let project: ProjectSample
    /// The project's first frame; the gradient shows until it arrives (and stays for a project with no picture).
    @State private var cover: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                LinearGradient(colors: project.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                if let cover {
                    Image(uiImage: cover).resizable().aspectRatio(contentMode: .fill)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .task(id: project.id) {
                cover = await ProjectCover.firstFrame(of: ProjectsView.openEditorProject(for: project), side: 64)
            }

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
        // Remove BG on video: the two clips with real people (`public/preview/video/demo-nguoi1/2.MOV`, copied into `Documents/ImportedMedia`), one project each.
        ProjectSample(name: ProjectsView.selfieProjectName, lastEdited: "Test project", gradient: [.green, .mint], compositionWidth: 360, compositionHeight: 640),
        ProjectSample(name: ProjectsView.crowdProjectName, lastEdited: "Test project", gradient: [.teal, .indigo], compositionWidth: 360, compositionHeight: 640),
    ]
    // `fullScreenCover`, not `NavigationLink` — a pushed page inside a
    // `TabView` leaves this tab's own tab bar showing underneath it.
    @State private var openedProject: ProjectSample?
    @State private var newProjectPicker: MediaPickerPurpose?
    @State private var projectToOpenAfterPickerDismisses: ProjectSample?
    @State private var isCreatingProject = false
    @State private var creationError: String?

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
                    newProjectPicker = .newProject
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create project")
                .accessibilityIdentifier("createProjectButton")
            }
        }
        .fullScreenCover(item: $newProjectPicker, onDismiss: {
            if let project = projectToOpenAfterPickerDismisses {
                projectToOpenAfterPickerDismisses = nil
                openedProject = project
            }
        }) { purpose in
            EditorMediaPickerView(
                purpose: purpose,
                onPick: { _ in },
                onAppend: { picked in
                    Task { await createProject(from: picked) }
                },
                onCancel: { newProjectPicker = nil }
            )
        }
        .fullScreenCover(item: $openedProject) { project in
            EditorShellView(project: Self.openEditorProject(for: project))
        }
        .overlay {
            if isCreatingProject {
                ZStack {
                    Color.black.opacity(0.32).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Creating project…").font(.subheadline.weight(.medium))
                    }
                    .padding(22)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .accessibilityIdentifier("creatingProjectProgress")
            }
        }
        .alert("Couldn't create project", isPresented: Binding(
            get: { creationError != nil },
            set: { if !$0 { creationError = nil } }
        )) {
            Button("OK", role: .cancel) { creationError = nil }
        } message: {
            Text(creationError ?? "Please select a photo or video and try again.")
        }
    }

    @MainActor
    private func createProject(from picked: [PickedMedia]) async {
        guard !picked.isEmpty else { return }
        isCreatingProject = true
        defer { isCreatingProject = false }

        var items: [MainLaneMediaItem] = []
        var firstImportError: Error?
        for media in picked {
            let layerId = "main-\(UUID().uuidString.prefix(8).lowercased())"
            let assetId = "media-\(UUID().uuidString.prefix(8).lowercased())"
            do {
                let asset = try await PhotoImporter.importMedia(media.asset, kind: media.kind, assetId: assetId)
                items.append(MainLaneMediaItem(asset: asset, layerId: layerId))
            } catch {
                if firstImportError == nil { firstImportError = error }
            }
        }

        guard !items.isEmpty else {
            creationError = firstImportError?.localizedDescription ?? "Couldn't import the selected media."
            newProjectPicker = nil
            return
        }

        let project = Self.makeNewProject(items: items)
        let composition = project.composition
        let sample = ProjectSample(
            name: "New Project",
            lastEdited: "Just now",
            gradient: [.gray, .black],
            compositionWidth: composition.width,
            compositionHeight: composition.height,
            editorProject: project
        )
        projects.insert(sample, at: 0)
        projectToOpenAfterPickerDismisses = sample
        newProjectPicker = nil
    }

    static func makeNewProject(items: [MainLaneMediaItem]) -> V2Project {
        let composition = V2Composition(width: 360, height: 640, fps: 30, background: "#000000")
        let emptyProject = V2Project(id: UUID().uuidString, composition: composition, assets: [], layers: [])
        return AppendMainLaneMediaCommand(items: items).apply(to: emptyProject)
    }

    /// "Trip to Paris" (the 9:16 sample) gets extra demo content — a
    /// standalone audio track + a text lane — so the Timeline's lane UI
    /// (video lane, text lane, audio lane) has something real to show,
    /// per the user's own request 2026-10-08. The other 2 samples are
    /// untouched (still just the plain compiled video). See `CLAUDE.md`'s
    /// audio design note and "Timeline lanes" note for the model this
    /// follows.
    /// `13792197_1080_1920_30fps.mp4` — the same value `SampleProjectBuilder`
    /// declares for the asset.
    private static let sampleClipDurationMs = SampleClipOverride.current?.durationMs ?? 31_200.0

    static let selfieProjectName = "Selfie (Remove BG test)"
    static let crowdProjectName = "Crowd (Remove BG test)"

    /// The Remove BG test projects: one real clip each on the main lane, the whole file - a selfie (1080 x 1920, one person) and a street shot (1920 x 1080, a crowd,
    /// letterboxed in the 9:16 canvas). One clip per project because a second video on the lane shows over the first from t = 0 (`LayerNodeView.isOutsideItsTime`
    /// leaves video layers always drawn). Needs the file in `Documents/ImportedMedia` (or the bundle); without it it is the plain sample.
    private static func peopleProject(for project: ProjectSample, fallback: V2Project) -> V2Project {
        #if DEBUG
        let file = project.name == selfieProjectName ? "demo-nguoi1.MOV" : "demo-nguoi2.MOV"
        guard let clip = VideoFileInfo.read(uri: file) else { return fallback }
        // The whole picture inside the canvas: full width, the height its aspect gives (a selfie fills the canvas, the landscape clip is letterboxed).
        let height = min(project.compositionWidth * clip.height / clip.width, project.compositionHeight)
        let layer = EditorLayer(
            id: "people-1", kind: "video", assetId: "people-1", fill: nil,
            frame: V2Frame(width: project.compositionWidth, height: height),
            timing: V2Timing(start: 0, duration: clip.durationMs)
        )
        let asset = V2Asset.video(V2VideoAsset(id: "people-1", uri: clip.uri, width: clip.width, height: clip.height, duration: clip.durationMs))
        return compile(EditorDocument(id: "people-test", composition: fallback.composition, assets: [asset], layers: [layer]))
        #else
        return fallback
        #endif
    }

    static func openEditorProject(for project: ProjectSample) -> V2Project {
        if let editorProject = project.editorProject { return editorProject }
        let videoProject = compile(SampleProjectBuilder.makeDocument(
            media: .videoPortrait, inOption: .none, outOption: .none,
            effectOption: .none, easingOption: .linear,
            composition: V2Composition(width: project.compositionWidth, height: project.compositionHeight, fps: 30, background: "#101820"),
            frame: V2Frame(width: project.compositionWidth, height: project.compositionHeight)
        ))
        if project.name == Self.selfieProjectName || project.name == Self.crowdProjectName { return peopleProject(for: project, fallback: videoProject) }
        guard project.name == "Trip to Paris" else { return videoProject }

        // The sample clip's own full length (31.2 s) instead of the demo's
        // default 2500 ms: 8 s was short enough that a hard flick hit the end
        // of the timeline within half a second (measured: 36% of coasts
        // ended at an edge), and there was no room to try zoom.
        var videoLayers = videoProject.layers
        for index in videoLayers.indices {
            videoLayers[index].timing = V2Timing(start: videoLayers[index].timing.start, duration: Self.sampleClipDurationMs)
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

        // Photo overlays — four stickers-style images, each on its own lane (they
        // overlap in time), so the sample has enough lanes to try the timeline's
        // vertical scrolling. Compiled through the real pipeline like the text.
        var overlaySpots: [(x: Double, y: Double, start: Double)] = [
            (-90, -170, 500), (90, -170, 1500), (-90, 170, 2500), (90, 170, 3500),
        ]
        var overlaySize = V2Frame(width: 140, height: 210)
        #if DEBUG
        // Marketing screenshots (`MarketingShotsUITests`): one small overlay so the stage stays readable.
        if ProcessInfo.processInfo.environment["EDITOR_MARKETING_DEMO"] != nil {
            overlaySpots = [(105, 235, 500)]
            overlaySize = V2Frame(width: 100, height: 150)
        }
        #endif
        let overlayProject = compile(EditorDocument(
            id: "trip-to-paris-overlays",
            composition: videoProject.composition,
            assets: [SampleMedia.photo.asset],
            layers: overlaySpots.indices.map { index in
                EditorLayer(
                    id: "overlay-photo-\(index)", kind: "image",
                    assetId: SampleMedia.photo.asset.id,
                    fill: nil,
                    frame: overlaySize,
                    timing: V2Timing(start: overlaySpots[index].start, duration: 8000)
                )
            }
        ))
        let overlayLayers: [V2Layer] = overlayProject.layers.enumerated().map { index, layer in
            var copy = layer
            copy.order = 2 + index
            let t = layer.transform
            copy.transform = V2Transform(
                translate: V2Vec3(x: overlaySpots[index].x, y: overlaySpots[index].y, z: 0),
                scale: t.scale, rotate: t.rotate, skew: t.skew, anchor: t.anchor, perspective: t.perspective
            )
            return copy
        }

        // Debug/UI tests: `EDITOR_EXTRA_LANES=N` stacks N more copies of the text
        // lane (one lane each) so the timeline's vertical scrolling can be exercised.
        var extraLayers: [V2Layer] = []
        #if DEBUG
        let extraLanes = Int(ProcessInfo.processInfo.environment["EDITOR_EXTRA_LANES"] ?? "") ?? 0
        for n in 0..<max(extraLanes, 0) {
            for var copy in textLayers {
                copy.id = "\(copy.id)-extra-\(n)"
                copy.order = 2 + overlayLayers.count + n
                extraLayers.append(copy)
            }
        }
        #endif

        // A standalone audio clip — a real `V2AudioClip` in
        // `V2AudioDomain`, independent of any video's embedded audio.
        let audioAsset = V2Asset.audio(V2AudioAsset(id: "audio-demo", uri: "audio-demo.mp3", mimeType: "audio/mpeg", duration: 262_500))
        let audioTrack = V2AudioTrack(
            id: "track-1", pan: 0, muted: false,
            clips: [
                V2AudioClip(
                    id: "audio-clip-1", assetId: "audio-demo",
                    timing: V2AudioClipTiming(start: 0, duration: Self.sampleClipDurationMs),
                    trim: V2AudioClipTrim(start: 0, end: nil),
                    playbackRate: 1
                ),
            ]
        )

        return V2Project(
            composition: videoProject.composition,
            assets: videoProject.assets + overlayProject.assets + [audioAsset],
            filters: videoProject.filters,
            layers: videoLayers + textLayers + overlayLayers + extraLayers,
            audio: V2AudioDomain(sampleRate: 48000, tracks: [audioTrack])
        )
    }
}
