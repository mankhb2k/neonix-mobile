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
    let atMs: Double
    /// Set only while a video layer is actively playing: that one layer
    /// renders the live `AVPlayer` output instead of an extracted still
    /// frame. Paused/scrubbing never sets this.
    var activePlayer: (assetId: String, player: AVPlayer)? = nil

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
                LayerNodeView(node: node, atMs: atMs, assets: assets, activePlayer: activePlayer)
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
    let activePlayer: (assetId: String, player: AVPlayer)?

    var body: some View {
        let frame = sampleLayer(node.layer, atMs: atMs)
        Group {
            if node.layer.type == "group" {
                ZStack {
                    ForEach(node.children, id: \.layer.id) { child in
                        LayerNodeView(node: child, atMs: atMs, assets: assets, activePlayer: activePlayer)
                    }
                }
            } else {
                LayerContentView(frame: frame, asset: assets.first { $0.id == frame.assetId }, activePlayer: activePlayer)
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
/// still frame for an image, and for video either the live playback
/// `AVPlayer` (while playing) or a cached decoded frame (`ScrubFrameView`).
private struct LayerContentView: View {
    let frame: ResolvedLayerFrame
    let asset: V2Asset?
    let activePlayer: (assetId: String, player: AVPlayer)?

    var body: some View {
        let contentMode: ContentMode = frame.fit == "contain" ? .fit : .fill
        switch frame.kind {
        case "image":
            if let asset, let uiImage = BundledImageCache.image(filename: asset.uri) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color.gray
            }
        case "video":
            if let asset, let activePlayer, activePlayer.assetId == asset.id {
                VideoPlayerLayerView(player: activePlayer.player, gravity: contentMode == .fit ? .resizeAspect : .resizeAspectFill)
            } else if let asset, let url = bundledURL(filename: asset.uri) {
                ScrubFrameView(assetId: asset.id, url: url, atSeconds: (frame.sourceMs ?? frame.elapsedMs) / 1000, contentMode: contentMode)
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

/// Paused/scrubbing video frame: read synchronously from `ScrubFrameCache`
/// (decoded ahead with `AVAssetReader`), so the picture follows
/// `currentTimeMs` in the same render pass as every other layer instead of
/// waiting on an `AVPlayer` seek. Once the playhead has held still for
/// `settleNanoseconds`, an exact full-quality frame replaces the cached one.
private struct ScrubFrameView: View {
    let assetId: String
    let url: URL
    let atSeconds: Double
    let contentMode: ContentMode

    @State private var sharpFrame: (seconds: Double, image: CGImage)?

    private static let settleNanoseconds: UInt64 = 150_000_000

    var body: some View {
        let image = sharpFrame.flatMap { $0.seconds == atSeconds ? $0.image : nil }
            ?? ScrubFrameCache.shared.image(assetId: assetId, atSeconds: atSeconds)
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color.gray
            }
        }
        .onAppear {
            ScrubFrameCache.shared.prefetch(assetId: assetId, url: url, around: atSeconds)
        }
        .onChange(of: atSeconds) { _, newValue in
            ScrubFrameCache.shared.prefetch(assetId: assetId, url: url, around: newValue)
        }
        .task(id: atSeconds) {
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

/// Resources (`project.yml`'s `buildPhase: resources` on
/// `Sources/AppModule/Resources`) land flattened in the app's main bundle
/// root, so lookup is by filename alone, split into base name + extension.
func bundledURL(filename: String) -> URL? {
    let parts = filename.split(separator: ".", maxSplits: 1)
    guard parts.count == 2 else { return nil }
    return Bundle.main.url(forResource: String(parts[0]), withExtension: String(parts[1]))
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
