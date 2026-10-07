import SwiftUI

/// The real Editor screen's **shell only** — a nav bar (`Huỷ`/`Xuất`), then
/// 3 vertically-stacked sections: **Stage** (preview canvas), **Titlebar**
/// (`controlsRow` — fullscreen left, play/pause center, undo/redo right),
/// **Timeline** (`TimelineView.swift`). The titlebar's structural role is to
/// sit *between*, separating stage from timeline — not a top-of-screen nav
/// bar (that's the separate `Huỷ`/`Xuất` bar above all 3).
///
/// **Height split, decided in conversation 2026-10-07**: the titlebar is a
/// **fixed height**, not a fraction of screen height — matching how every
/// real iOS toolbar/tab bar works (constant ~56-64pt regardless of device
/// size; it holds icons, not content that benefits from more room on a
/// bigger screen). Its actual height is *measured*, not hardcoded
/// (`TitlebarHeightKey`, a `PreferenceKey` read off `controlsRow`'s real
/// rendered size), so this stays correct if the row's padding/font ever
/// changes.
///
/// **Stage is a fixed square sized purely from screen width — `squareSide =
/// geo.size.width`, height derived by squaring that, not by fitting into
/// whatever height happens to be left over.** **Timeline is no longer a
/// fixed 33%** — redesigned 2026-10-07, replacing the original version
/// where `timelineHeight` was computed first (33% of post-titlebar space)
/// and Stage got whatever remained. Now Stage is computed *first*, driven
/// only by width, and **Timeline gets whatever's left** after Titlebar +
/// Stage + the divider's ~1pt are subtracted from the total — the reverse
/// dependency order from before. The video renders at `squareSide * 0.96`
/// within the square, so any project aspect ratio scales down to fit,
/// leaving a consistent small margin around it — the project's own aspect
/// ratio still has no way to influence Stage's own size, only what's left
/// for Timeline afterward. No floor on Timeline's height in this version —
/// on a device/orientation where `squareSide` (full width) genuinely
/// exceeds the available height, Timeline can shrink to `0` (clamped via
/// `max(...)`, never negative); that trade-off was an explicit choice here,
/// not an oversight.
///
/// **An aspect-ratio-*adaptive* Stage (no forced square; Stage reshaped
/// itself per project, Timeline got whatever height was left) was tried
/// and fully working — all 10 unit tests and all 3 real-tap `XCUITest`s
/// passed — right before this, in the same conversation.** The user asked
/// to revert to the fixed square above and raise the video's share from
/// 90% to 96%, rather than keep the adaptive reshaping. If an adaptive
/// Stage is wanted again later, the full working version is recoverable
/// from this file's own git history around that timestamp — it is not
/// preserved inline here since the user explicitly chose the square.
/// 96% (not 90%) is **purely this count's own value** — a 9:16 video's
/// *height* hits 96% of the square's side exactly; its *width* is still
/// naturally narrower (pillarboxed), proportional to the composition's own
/// ratio — same mathematical shape as the 90% version had, just a smaller
/// margin.
///
/// **A second, more surprising bug surfaced right after the overflow fix
/// above, caught only because a real `XCUITest` was added (`EditorNavigationUITests`)
/// — `simctl` itself cannot synthesize a real tap, and this bug was
/// invisible to every build/screenshot-based check used until then.**
/// Real taps on `Huỷ` silently failed to dismiss for 2 of the 3 sample
/// projects (16:9 and 1:1 — the ones that actually needed shrinking to fit
/// the square box; the 9:16 one happened to need almost no shrinking and
/// never showed the bug), 100% reproducibly, with the button's own action
/// closure never executing. Root-caused by elimination, swapping one
/// variable at a time under the real UI test: not the Liquid Glass button
/// style (reproduced with it removed), not an async/video-decode race
/// (reproduced with a 5s settle delay first), not `titlebarHeight`
/// oscillation (reproduced after that was independently fixed), not the
/// test code itself (reproduced with the exact passing test's own code,
/// just pointed at a different project) — narrowed to `PreviewCanvas`
/// itself by replacing it with a plain `Color` (passed) vs the real view
/// (failed). `PreviewCanvas`'s `GeometryReader` + `.scaleEffect` combo (see
/// that file's own doc comment) still absorbed touches meant for `Huỷ`
/// sitting above it in z-order, even with `.clipped()` already applied —
/// `.clipped()` constrains drawing and most hit-testing, but evidently not
/// all of it for this specific transform combination. **Fix: the stage
/// preview was never interactive to begin with (no gesture of its own), so
/// `.allowsHitTesting(false)` on `PreviewCanvas` removes it from hit-testing
/// entirely** — a narrower, more certain fix than trying to further
/// chase exactly which part of `.scaleEffect`'s hit-test footprint
/// `.clipped()` wasn't reaching.
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
    /// The titlebar's real measured height (see `TitlebarHeightKey`) — a
    /// reasonable guess until the first layout pass reports the actual
    /// value, never used as a hardcoded final answer.
    @State private var titlebarHeight: CGFloat = 60

    init(project: V2Project) {
        _project = State(initialValue: project)
    }

    private var maxDurationMs: Double {
        max(project.layers.map { $0.timing.start + $0.timing.duration }.max() ?? 1, 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            // Stage / Titlebar / Timeline — Stage is computed first (from
            // width alone, see this file's top doc comment), Timeline gets
            // whatever's left. One `GeometryReader` for the whole section,
            // not one per child, so every height comes from a single source
            // of truth.
            GeometryReader { geo in
                // Stage is a square sized *only* from the available width —
                // no longer clamped against a separate height budget (that
                // was the old 67%-of-remainder rule). Height is derived by
                // squaring the width, not fit into whatever space happens to
                // be left.
                let squareSide = geo.size.width
                let videoBoxSide = squareSide * 0.96
                let stageHeight = squareSide

                // Timeline gets whatever's left after Titlebar + Stage + the
                // divider's ~1pt — the reverse of the old order (Timeline
                // used to be computed first, as a fixed 33%, and Stage got
                // the remainder). `max(..., 0)` only guards against a
                // negative frame value; there is deliberately no minimum
                // floor here — see top doc comment.
                let timelineHeight = max(geo.size.height - titlebarHeight - stageHeight - 1, 0)

                VStack(spacing: 0) {
                    // The "stage" — plain white around the preview, matching
                    // the native Photos editor's own stage background
                    // (confirmed by sampling pixels from a reference
                    // screenshot: the area around the photo reads
                    // (255,255,255), not a gray letterbox). Any letterboxing
                    // a non-matching aspect ratio needs is drawn *inside*
                    // `PreviewCanvas` itself (`composition.background`), not
                    // by this surrounding panel.
                    // No external `.aspectRatio(...)` needed — `PreviewCanvas`
                    // now scales its own native composition coordinate space
                    // to fit whatever frame it's given (see its doc comment),
                    // so handing it the 96%-of-square box directly is enough.
                    // `.allowsHitTesting(false)` is load-bearing, not
                    // cosmetic — see this file's top doc comment for the real
                    // bug this closed (`GeometryReader` + `.scaleEffect`
                    // inside `PreviewCanvas` could still absorb taps meant for
                    // `Huỷ`/`Xuất` above it, `.clipped()` alone wasn't
                    // enough). The stage has never had its own gesture here
                    // anyway, so removing it from hit-testing costs nothing.
                    PreviewCanvas(
                        composition: project.composition,
                        assets: project.assets,
                        layers: project.layers,
                        atMs: currentTimeMs
                    )
                    .allowsHitTesting(false)
                    .frame(width: videoBoxSide, height: videoBoxSide)
                    .frame(width: squareSide, height: squareSide)
                    .background(Color(.systemBackground))

                    controlsRow
                        .background(GeometryReader { titlebarGeo in
                            Color.clear.preference(key: TitlebarHeightKey.self, value: titlebarGeo.size.height)
                        })
                    Divider()
                    TimelineView(
                        layers: project.layers,
                        currentTimeMs: $currentTimeMs,
                        maxDurationMs: maxDurationMs,
                        onScrub: { isPlaying = false }
                    )
                    .frame(height: timelineHeight)
                    .clipped()
                }
            }
        }
        .background(Color(.systemBackground))
        // Ignore a reported `0` — the titlebar's real content always has a
        // positive height; `0` only ever shows up as a transient artifact
        // during the fullScreenCover's own presentation animation (the whole
        // view briefly renders at a near-zero size while sliding in). Found
        // 2026-10-07 chasing a real, reproducible XCUITest failure: without
        // this guard, a stray `0` mid-animation fed back into `stageHeight`'s
        // computation, growing Stage/shrinking nothing-in-particular for one
        // more frame, which could still be mid-flight exactly when a UI test
        // (or a fast real tap right as the screen appears) dispatched its
        // touch — the accessibility snapshot and the actual on-screen layout
        // had briefly diverged. Dropping the `0` keeps `titlebarHeight`
        // monotonically settling to its one real measured value instead of
        // oscillating.
        .onPreferenceChange(TitlebarHeightKey.self) { newValue in
            guard newValue > 0 else { return }
            titlebarHeight = newValue
        }
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

    /// The **titlebar** — exactly 3 controls (fullscreen left, play/pause
    /// center, undo/redo right), structurally the divider between Stage and
    /// Timeline (see this file's top doc comment for the height-split
    /// rule). Its height is read via `TitlebarHeightKey`, not assumed.
    ///
    /// **Play/pause is centered via a separate, overlaid `HStack` with its
    /// own two `Spacer()`s — not the single shared `HStack { left; Spacer();
    /// play; Spacer(); right }` this used to be.** Found 2026-10-07: a
    /// single `HStack` with two `Spacer()`s only centers its middle child
    /// when the two *side* groups are equal width. Here they never are — the
    /// right side holds 2 buttons (undo+redo), the left side holds 1
    /// (fullscreen) — so each `Spacer()` claimed a different share of the
    /// remaining space and play/pause sat visibly off-center, always pulled
    /// toward the lighter (left) side. Layering the center button in its own
    /// `HStack(spacer, button, spacer)`, with the left/right buttons in a
    /// *second*, independent `HStack` underneath, makes play/pause's
    /// position depend only on the row's own total width — never on how
    /// wide either side group happens to be.
    private var controlsRow: some View {
        ZStack {
            HStack {
                Spacer()
                Button {
                    isPlaying.toggle()
                    lastTick = .init()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                Spacer()
            }

            HStack {
                // No fullscreen presentation mode exists yet — disabled,
                // not a dead button someone might mistake for a bug.
                Button {} label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.title3)
                }
                .disabled(true)

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
        }
        .foregroundColor(.primary)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
    }
}

/// Carries the titlebar's real rendered height up to `EditorShellView.body`
/// so the timeline height computation (`(total - titlebar) / 3`) uses the
/// actual value instead of a guessed constant.
private struct TitlebarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// 9:16 (360x640), matching `ProjectsView`'s "Trip to Paris" sample exactly —
// not the default square composition `EditorDemoView.makeDocument` falls
// back to without these two arguments — so Canvas previews the same shape
// the real Folder → Editor flow opens.
#Preview {
    EditorShellView(project: compile(EditorDemoView.makeDocument(
        media: .videoPortrait, inOption: .none, outOption: .none,
        effectOption: .none, easingOption: .linear,
        composition: V2Composition(width: 360, height: 640, fps: 30, background: "#101820"),
        frame: V2Frame(width: 360, height: 640)
    )))
}
