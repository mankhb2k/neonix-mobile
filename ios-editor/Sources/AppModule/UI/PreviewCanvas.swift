import AVFoundation
import SwiftUI

/// One node of the parent/child layer tree, built from the flat
/// `parentLayerId`-linked `layers[]` array — see `LayerTree.build`.
private struct LayerTreeNode {
    var layer: V2Layer
    var children: [LayerTreeNode]
}

/// Protocol V2 stores layers as a flat array; only `parentLayerId`
/// expresses the tree (see `README.md`'s "`layers[]` is a flat array
/// representing a tree" note). This rebuilds the actual tree once per
/// render so `PreviewCanvas` can render it as real nested SwiftUI views —
/// see that type's doc comment for why nesting (not manual matrix math)
/// is how parent→child transform/opacity composition works here.
private enum LayerTree {
    static func build(from layers: [V2Layer]) -> [LayerTreeNode] {
        let byParent = Dictionary(grouping: layers, by: { $0.parentLayerId })
        func node(for layer: V2Layer) -> LayerTreeNode {
            let kids = (byParent[layer.id] ?? []).sorted { $0.order < $1.order }.map(node(for:))
            return LayerTreeNode(layer: layer, children: kids)
        }
        return (byParent[nil] ?? []).sorted { $0.order < $1.order }.map(node(for:))
    }
}

/// Renders one `V2Project` composition at `atMs`.
///
/// Layers nest via `parentLayerId` (`type: "group"` layers have no visual
/// content of their own — see CLAUDE.md's "Group layers compose
/// transform/opacity by real view nesting" note). This renders that tree as
/// genuinely nested SwiftUI views, one recursive `LayerNodeView` per node:
/// a group's own `.offset`/`.scaleEffect`/`.rotationEffect`/`.opacity`
/// modifiers are applied to a container that the group's *children* render
/// inside, so SwiftUI's own layout engine composes parent and child
/// transforms correctly (matching nested SVG `<g>`/CSS transform
/// semantics) — no manual matrix multiplication needed here.
struct PreviewCanvas: View {
    let composition: V2Composition
    let assets: [V2Asset]
    let layers: [V2Layer]
    /// Resolved via each layer's own `filter: String?` id — see
    /// `FilterRenderer`/CLAUDE.md's "Tuỳ chỉnh" note. Empty on every call
    /// site that never authors a filter, same "no-op by default" shape as
    /// every other optional Protocol V2 feature this renderer reads.
    var filters: [V2Filter] = []
    let atMs: Double
    /// `true` while the playhead is at rest: video layers then swap their
    /// decoded preview frame for an exact full-quality one.
    var refinesStills: Bool = true

    /// Scales the fixed `composition.width`/`height` coordinate space to fit
    /// whatever box the caller gives this view. `.clipped()` keeps drawing
    /// (and most hit-testing) bounded to that box — callers must also set
    /// `.allowsHitTesting(false)` themselves, since `.clipped()` alone isn't
    /// fully sufficient (see `ui-design-note.md`, repo root, for the real
    /// bug this was built to fix and the one `.clipped()` didn't).
    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / composition.width, geo.size.height / composition.height)
            content
                .frame(width: composition.width, height: composition.height)
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
    }

    private var content: some View {
        let tree = LayerTree.build(from: layers)
        return ZStack {
            Color(hex: composition.background)
            ForEach(tree, id: \.layer.id) { node in
                LayerNodeView(node: node, atMs: atMs, assets: assets, filters: filters, refinesStills: refinesStills)
            }
        }
        .clipped()
    }
}

/// One layer's own transform/opacity modifiers, applied once, wrapping
/// either its drawable content (leaf layers) or its children (`"group"`
/// layers only — see `README.md`: "only a group may be a parent").
private struct LayerNodeView: View {
    let node: LayerTreeNode
    let atMs: Double
    let assets: [V2Asset]
    let filters: [V2Filter]
    let refinesStills: Bool

    var body: some View {
        let frame = sampleLayer(node.layer, atMs: atMs)
        Group {
            if node.layer.type == "group" {
                ZStack {
                    ForEach(node.children, id: \.layer.id) { child in
                        LayerNodeView(node: child, atMs: atMs, assets: assets, filters: filters, refinesStills: refinesStills)
                    }
                }
            } else {
                LayerContentView(
                    frame: frame, asset: assets.first { $0.id == frame.assetId },
                    filter: node.layer.filter.flatMap { id in filters.first { $0.id == id } },
                    refinesStills: refinesStills
                )
                .frame(width: frame.frameWidth, height: frame.frameHeight)
                .clipped()
            }
        }
        // `anchor` is an offset from the layer's own center (see CLAUDE.md's
        // "Transform anchor is an offset from center" note), converted here
        // to the `UnitPoint` every one of SwiftUI's own anchor parameters
        // expects (0...1 fraction of the view's native, unscaled bounds).
        .scaleEffect(x: frame.scaleX * depthScale(frame), y: frame.scaleY * depthScale(frame), anchor: anchorPoint(frame))
        .transformEffect(skewTransform(frame))
        .rotation3DEffect(.degrees(frame.rotateX), axis: (x: 1, y: 0, z: 0), anchor: anchorPoint(frame), anchorZ: frame.anchorZ, perspective: frame.perspective ?? 1)
        .rotation3DEffect(.degrees(frame.rotateY), axis: (x: 0, y: 1, z: 0), anchor: anchorPoint(frame), anchorZ: frame.anchorZ, perspective: frame.perspective ?? 1)
        .rotationEffect(.degrees(frame.rotateZ), anchor: anchorPoint(frame))
        // `layer.motion` (CSS `offset-path`) — a no-op (`0`/`0`/`0`) for any
        // layer without one. Added on top of the ordinary transform, not in
        // place of it, matching how `ResolvedLayerFrame.motionDx/Dy/Rotation`
        // are documented to combine (see CLAUDE.md's motion-path note).
        .rotationEffect(.degrees(frame.motionRotation), anchor: anchorPoint(frame))
        .opacity(frame.opacity)
        .offset(x: frame.translateX + frame.motionDx, y: frame.translateY + frame.motionDy)
    }

    private func anchorPoint(_ frame: ResolvedLayerFrame) -> UnitPoint {
        guard frame.frameWidth > 0, frame.frameHeight > 0 else { return .center }
        return UnitPoint(x: 0.5 + frame.anchorX / frame.frameWidth, y: 0.5 + frame.anchorY / frame.frameHeight)
    }

    /// 2D shear — `CGAffineTransform`'s own native skew representation, via
    /// `.transformEffect(_:)` (the one SwiftUI modifier that takes a raw
    /// affine matrix), since there's no dedicated `.skewEffect()`.
    private func skewTransform(_ frame: ResolvedLayerFrame) -> CGAffineTransform {
        guard frame.skewX != 0 || frame.skewY != 0 else { return .identity }
        let skewXRadians = frame.skewX * .pi / 180
        let skewYRadians = frame.skewY * .pi / 180
        return CGAffineTransform(a: 1, b: tan(skewYRadians), c: tan(skewXRadians), d: 1, tx: 0, ty: 0)
    }

    /// Approximates `translate.z` the way a flat (non-`preserve-3d`) CSS
    /// element reads it: moving "closer"/"further" along z, under a given
    /// `perspective`, is visually indistinguishable from scaling by
    /// `perspective / (perspective - z)` — the same relation this app
    /// already leans on for `rotateX`/`rotateY`. Only applies once
    /// `perspective` is actually authored, matching that field's own
    /// "only meaningful once a 3D field is non-zero" rule; otherwise
    /// `translate.z` has no own visual effect here (same as real CSS
    /// outside a 3D context).
    private func depthScale(_ frame: ResolvedLayerFrame) -> Double {
        guard let perspective = frame.perspective, frame.translateZ != 0 else { return 1 }
        let denominator = perspective - frame.translateZ
        guard denominator > 0.0001 else { return 1 }
        return perspective / denominator
    }
}

/// Renders one layer's own content (before the shared transform/opacity
/// modifiers `LayerNodeView` applies): a flat color for a shape, a cached
/// still for an image, and the decoded frame at the playhead for video
/// (`VideoFrameView`).
private struct LayerContentView: View {
    let frame: ResolvedLayerFrame
    let asset: V2Asset?
    /// Tuỳ chỉnh — see `FilteredImageView`/`FilterRenderer`. `nil` for every
    /// layer that hasn't had a filter applied (the overwhelming common
    /// case), in which case `FilteredImageView` is a pure pass-through.
    let filter: V2Filter?
    let refinesStills: Bool

    var body: some View {
        let contentMode: ContentMode = frame.fit == "contain" ? .fit : .fill
        switch frame.kind {
        case "image":
            if let asset, let uiImage = BundledImageCache.image(filename: asset.uri) {
                FilteredImageView(sourceKey: asset.uri, source: uiImage.cgImage, filter: filter, contentMode: contentMode)
            } else {
                Color.gray
            }
        case "video":
            if let asset, let url = bundledURL(filename: asset.uri) {
                VideoFrameView(
                    assetId: asset.id,
                    url: url,
                    atSeconds: (frame.sourceMs ?? frame.elapsedMs) / 1000,
                    contentMode: contentMode,
                    refines: refinesStills,
                    filter: filter
                )
            } else {
                Color.gray
            }
        case "text":
            // `.fixedSize()` lets each line report its true (possibly
            // overflowing, e.g. `wrap: "none"`) width upward — without an
            // explicit `alignment: .topLeading` frame right here, the next
            // fixed-size `.frame(width:height:)` up in `LayerNodeView`
            // would silently *center* that oversized content instead of
            // anchoring it at the resolved `x`/`y` this view already
            // computed, which would make every `x`/`y` below meaningless.
            ZStack(alignment: .topLeading) {
                ForEach(Array((frame.textRuns ?? []).enumerated()), id: \.offset) { _, run in
                    Text(run.text)
                        .font(.custom(run.fontFamily, size: run.fontSize))
                        .foregroundColor(Color(hex: run.color))
                        .opacity(run.opacity)
                        .fixedSize()
                        .rotationEffect(.degrees(run.rotation))
                        .offset(x: run.x, y: run.y)
                }
            }
            .frame(width: frame.frameWidth, height: frame.frameHeight, alignment: .topLeading)
            .clipped()
        default:
            Rectangle().fill(Color(hex: frame.fill ?? "#000000"))
        }
    }
}

/// One video layer's pixels: always the frame at the playhead, read
/// synchronously from `VideoFrameServer` — the same path while scrubbing,
/// coasting and playing, so there is never a hand-off between two kinds of
/// view to flash. `EditorPlaybackEngine` keeps the frames decoded ahead;
/// this view only reads them. When `refines` (playhead at rest) and it has
/// held still for `settleNanoseconds`, an exact full-quality frame replaces
/// the downscaled preview frame.
///
/// Never draws nothing once it has drawn something: when the server has no
/// frame for this asset (a playhead jump evicted the old region and the new
/// reader is still walking from the previous keyframe — up to ~2 s for the
/// long-GOP sample files on the simulator), the last frame shown stays up
/// until a new one arrives. An empty Stage there was a real bug.
private struct VideoFrameView: View {
    let assetId: String
    let url: URL
    let atSeconds: Double
    let contentMode: ContentMode
    let refines: Bool
    /// Tuỳ chỉnh — only actually applied while `refines` (playhead at rest);
    /// see `FilteredImageView`'s own doc comment for why live Play doesn't
    /// grade yet.
    var filter: V2Filter?

    @State private var sharpFrame: (seconds: Double, image: CGImage)?
    /// Reference box on purpose: remembering what was drawn mustn't itself
    /// trigger another render.
    @State private var lastShown = LastShownFrame()

    private static let settleNanoseconds: UInt64 = 150_000_000

    private struct RefineKey: Equatable {
        let atSeconds: Double
        let refines: Bool
    }

    var body: some View {
        let sharp = refines ? sharpFrame.flatMap { $0.seconds == atSeconds ? $0.image : nil } : nil
        let image = sharp ?? VideoFrameServer.shared.image(assetId: assetId, atSeconds: atSeconds) ?? lastShown.image
        let _ = lastShown.image = image
        Group {
            if let image {
                FilteredImageView(sourceKey: "\(assetId)-\(atSeconds)", source: image, filter: refines ? filter : nil, contentMode: contentMode)
            } else {
                Color.clear
            }
        }
        .task(id: RefineKey(atSeconds: atSeconds, refines: refines)) {
            guard refines, sharpFrame?.seconds != atSeconds else { return }
            try? await Task.sleep(nanoseconds: Self.settleNanoseconds)
            guard !Task.isCancelled else { return }
            let target = atSeconds
            guard let image = await SharpFrameLoader.shared.image(assetId: assetId, url: url, atSeconds: target),
                  !Task.isCancelled
            else { return }
            sharpFrame = (target, image)
        }
    }
}

private final class LastShownFrame {
    var image: CGImage?
}

/// Tuỳ chỉnh's one display-side entry point: given a raw decoded/cached
/// `CGImage` and an optional `V2Filter`, runs it through `FilterRenderer`
/// asynchronously and draws whichever is freshest — the newly filtered
/// result once it's ready, the previous filtered result while a new one is
/// computing, or the unfiltered `source` if there's no filter (or none has
/// resolved yet). Never renders `Color.clear`/nothing once `source` exists,
/// same "never show nothing" discipline as `VideoFrameView`'s own
/// `lastShown`, and never runs `FilterRenderer` synchronously from `body`
/// (see CLAUDE.md's "Scrubbing must never re-decode media inline from
/// `body`" rule — filtering is exactly that same category of work).
///
/// Used by both the `"image"` layer case and `VideoFrameView` — the one
/// place this app draws a `CGImage` onto the Stage, now the one place it
/// gets filtered too.
private struct FilteredImageView: View {
    /// Identifies *which* image `source` is (a bundled image's own
    /// filename, or `"<assetId>-<atSeconds>"` for a video frame) — needed
    /// alongside the filter snapshot below because `CGImage` has no cheap
    /// stable identity of its own: without this, scrubbing a graded video
    /// clip would keep re-showing a stale filtered frame from whichever
    /// moment the filter's own values last changed, not the frame actually
    /// at the playhead now.
    let sourceKey: String
    let source: CGImage?
    let filter: V2Filter?
    let contentMode: ContentMode

    @State private var filtered: CGImage?

    /// `.task(id:)`'s own key — `sourceKey` plus a JSON snapshot of the
    /// filter's current values. The filter-snapshot half is generic on
    /// purpose: works for *any* future filter shape (Blur/Noise/Vignette/
    /// ...) with zero changes here, since it never has to know what the
    /// primitives mean, only when they've changed. Cheap for the
    /// 2-4-primitive chains this app compiles today.
    private var cacheKey: String {
        guard let filter, let data = try? JSONEncoder().encode(filter) else { return sourceKey }
        return sourceKey + "|" + data.base64EncodedString()
    }

    var body: some View {
        let image = filtered ?? source
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color.clear
            }
        }
        .task(id: cacheKey) {
            guard let filter, let source else {
                filtered = nil
                return
            }
            let result = FilterRenderer.apply(filter, to: source)
            guard !Task.isCancelled else { return }
            filtered = result
        }
    }
}

/// Resources (`project.yml`'s `buildPhase: resources` on
/// `Sources/AppModule/Resources`) land flattened in the app's main bundle
/// root, so lookup is by filename alone, split into base name + extension.
/// Falls back to `MediaImportService.importedMediaDirectory` (Documents) for
/// anything imported/recorded/extracted at runtime, which obviously isn't in
/// the app bundle — every existing call site gets this for free, no changes
/// needed anywhere else.
func bundledURL(filename: String) -> URL? {
    let parts = filename.split(separator: ".", maxSplits: 1)
    guard parts.count == 2 else { return nil }
    if let bundled = Bundle.main.url(forResource: String(parts[0]), withExtension: String(parts[1])) {
        return bundled
    }
    let imported = MediaImportService.importedMediaDirectory.appendingPathComponent(filename)
    return FileManager.default.fileExists(atPath: imported.path) ? imported : nil
}

/// Decodes each bundled image exactly once and reuses it. Unlike a video
/// frame, a static image layer's content never depends on the scrub
/// position — the old code called `UIImage(contentsOfFile:)` (disk read +
/// decode) directly from `body`, meaning every single slider tick re-read
/// and re-decoded the same file from scratch, which is what made scrubbing
/// a photo layer feel janky too, same symptom as the video case but a
/// different cause (needless repeated work, not a slow one-off operation).
private enum BundledImageCache {
    private static var cache: [String: UIImage] = [:]

    static func image(filename: String) -> UIImage? {
        if let cached = cache[filename] { return cached }
        guard let url = bundledURL(filename: filename), let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache[filename] = image
        return image
    }
}

extension Color {
    /// Parses `#RRGGBB` or `#RRGGBBAA`, matching `V2ColorSchema`.
    init(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized.removeAll { $0 == "#" }
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)
        let hasAlpha = sanitized.count == 8
        let r: Double
        let g: Double
        let b: Double
        let a: Double
        if hasAlpha {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        } else {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
