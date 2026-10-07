import SwiftUI

/// The real Editor screen's **shell only** — a title bar, the "stage"
/// (preview canvas), one control row underneath it (fullscreen left,
/// play/pause center, undo/redo right), and the timeline (`TimelineView.swift`)
/// below that. Opened from `ProjectsView` when a project row is tapped.
///
/// Redesigned 2026-10-07, replacing an earlier version that also had a
/// scrubber bar, an "add content" row, and a 7-tool bottom toolbar — the
/// user asked for those removed entirely, keeping only the stage and this
/// one minimal control row (see the reference screenshot this was rebuilt
/// from). `EditorTool` (`EditorTool.swift`) still documents the 7-tool v1
/// scope decided earlier, but nothing in this view references it anymore —
/// where those tools resurface in the UI is a separate, not-yet-decided
/// question, not dropped work.
///
/// **Nav and chrome are the native iOS Photos editor's own light style**
/// (`Huỷ`/`Xuất` text buttons), using **system dynamic colors** throughout
/// (`Color(.systemBackground)`, `.secondarySystemBackground`, `.primary`)
/// instead of hardcoded black/white — this already renders light or dark
/// automatically based on the user's own iOS appearance setting, which is
/// the "stays light unless the user has chosen dark mode" behavior asked
/// for. Don't reintroduce hardcoded black/white here.
///
/// Fullscreen and undo/redo are disabled placeholders — there is no
/// fullscreen presentation mode and no command/undo stack yet (see
/// CLAUDE.md's "Command pattern, not JSON Patch or CRDT" note: that's the
/// intended mechanism, just not built). `project` here is a freshly
/// compiled sample (`EditorDemoView.makeDocument`), **not** loaded from
/// `ProjectsView`'s own `ProjectSample` — that type has no real
/// project-document backing yet (see its own doc comment), so every
/// project row opens the same placeholder composition for now.
struct EditorShellView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var project: V2Project
    @State private var currentTimeMs: Double = 0
    @State private var isPlaying = false
    @State private var lastTick: Date = .init()

    init(project: V2Project) {
        _project = State(initialValue: project)
    }

    private var maxDurationMs: Double {
        max(project.layers.map { $0.timing.start + $0.timing.duration }.max() ?? 1, 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            // The "stage" — plain white around the preview, matching the
            // native Photos editor's own stage background (confirmed by
            // sampling pixels from a reference screenshot: the area around
            // the photo reads (255,255,255), not a gray letterbox — an
            // earlier version of this comment assumed gray without
            // checking). Any letterboxing a non-matching aspect ratio needs
            // is drawn *inside* `PreviewCanvas` itself (`composition
            // .background`), not by this surrounding panel.
            PreviewCanvas(
                composition: project.composition,
                assets: project.assets,
                layers: project.layers,
                atMs: currentTimeMs
            )
            .aspectRatio(project.composition.width / project.composition.height, contentMode: .fit)
            .frame(maxHeight: .infinity)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))

            controlsRow
            Divider()
            TimelineView(
                layers: project.layers,
                currentTimeMs: $currentTimeMs,
                maxDurationMs: maxDurationMs,
                onScrub: { isPlaying = false }
            )
        }
        .background(Color(.systemBackground))
        .onReceive(playbackTimer) { now in
            guard isPlaying else { return }
            let deltaMs = now.timeIntervalSince(lastTick) * 1000
            lastTick = now
            let next = currentTimeMs + deltaMs
            if next >= maxDurationMs {
                currentTimeMs = 0
                isPlaying = false
            } else {
                currentTimeMs = next
            }
        }
    }

    /// `Huỷ`/`Xuất` text buttons, not icon buttons — matching the native
    /// Photos editor's own nav shape, but labeled for export (CapCut's own
    /// wording) rather than "Done". Neither actually diverges yet (no
    /// edit state exists to discard, and no export pipeline exists to run —
    /// both just dismiss for now; that split is real future work, not an
    /// oversight.
    ///
    /// **iOS 26's Liquid Glass button styles** (`.glass`/`.glassProminent`,
    /// `SwiftUI.GlassButtonStyle`/`GlassProminentButtonStyle` — confirmed by
    /// reading the actual SDK's `.swiftinterface`, not guessed) — the same
    /// chrome `ProjectsView`'s toolbar `+` button already gets "for free"
    /// from being inside a real `ToolbarItem` (iOS 26 auto-styles toolbar
    /// buttons this way). This view's top bar isn't a real toolbar, so it
    /// needs the style applied explicitly. Both styles need iOS 26 — gated
    /// with `if #available` so this still deploys to the 17.0 target in
    /// `project.yml`, falling back to the plain-text/`.borderedProminent`
    /// look on older OS versions instead of failing to build.
    private var topBar: some View {
        HStack {
            cancelButton
            Spacer()
            exportButton
        }
        .padding()
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var cancelButton: some View {
        if #available(iOS 26.0, *) {
            Button("Huỷ") { dismiss() }
                .buttonStyle(.glass)
        } else {
            Button("Huỷ") { dismiss() }
                .foregroundColor(.primary)
        }
    }

    @ViewBuilder
    private var exportButton: some View {
        if #available(iOS 26.0, *) {
            Button("Xuất") { dismiss() }
                .buttonStyle(.glassProminent)
        } else {
            Button("Xuất") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    /// Exactly 3 controls, matching the reference layout: fullscreen on the
    /// left, play/pause centered under the stage, undo/redo on the right.
    private var controlsRow: some View {
        HStack {
            // No fullscreen presentation mode exists yet — disabled, not a
            // dead button someone might mistake for a bug.
            Button {} label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.title3)
            }
            .disabled(true)

            Spacer()

            Button {
                isPlaying.toggle()
                lastTick = .init()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }

            Spacer()

            HStack(spacing: 22) {
                // No command/undo stack exists yet (see CLAUDE.md) —
                // disabled for the same reason fullscreen is.
                Button {} label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.title3)
                }
                .disabled(true)
                Button {} label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.title3)
                }
                .disabled(true)
            }
        }
        .foregroundColor(.primary)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
    }
}

#Preview {
    EditorShellView(project: compile(EditorDemoView.makeDocument(
        media: .videoPortrait, inOption: .none, outOption: .none,
        effectOption: .none, easingOption: .linear
    )))
}
