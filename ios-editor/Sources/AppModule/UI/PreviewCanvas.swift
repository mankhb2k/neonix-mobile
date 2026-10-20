import AVFoundation
import CoreImage
import MetalKit
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
        let paintIndex = Dictionary(uniqueKeysWithValues: layers.enumerated().map { ($0.element.id, $0.offset) })
        let byParent = Dictionary(grouping: layers, by: { $0.parentLayerId })
        func ordered(_ children: [V2Layer]) -> [V2Layer] {
            children.sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return (paintIndex[$0.id] ?? 0) < (paintIndex[$1.id] ?? 0)
            }
        }
        func node(for layer: V2Layer) -> LayerTreeNode {
            let kids = ordered(byParent[layer.id] ?? []).map(node(for:))
            return LayerTreeNode(layer: layer, children: kids)
        }
        return ordered(byParent[nil] ?? []).map(node(for:))
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
    /// Resolved via each layer's `mask` id (the Mask tool's `V2Mask`s); a layer with none is untouched.
    var masks: [V2Mask] = []
    let atMs: Double
    /// The same cut window used by the playback engine and export frame sampler.
    var transitionFramePlan: TransitionFramePlan? = nil
    /// Owns one `AVPlayer` per video layer; video layers draw from it.
    let playerEngine: EditorPlaybackEngine
    /// Offline export supplies exact source frames while retaining this same V2 layer tree and sampler.
    var exportFrames: [String: CGImage]? = nil

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
                LayerNodeView(
                    node: node,
                    atMs: atMs,
                    assets: assets,
                    filters: filters,
                    masks: masks,
                    playerEngine: playerEngine,
                    exportFrames: exportFrames,
                    transitionFramePlan: transitionFramePlan
                )
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
    let masks: [V2Mask]
    let playerEngine: EditorPlaybackEngine
    let exportFrames: [String: CGImage]?
    let transitionFramePlan: TransitionFramePlan?

    /// A layer is visible only inside its own timing window. Video views stay mounted below so their player sessions remain prepared.
    private var isOutsideItsTime: Bool {
        if node.layer.type == "video", transitionFramePlan?.isVisible(node.layer.id, at: atMs) == true { return false }
        return atMs < node.layer.timing.start || atMs > node.layer.timing.start + node.layer.timing.duration
    }

    var body: some View {
        let _ = PlaybackMetrics.shared.count(.layerBodyEvals)
        if node.layer.type == "video" {
            // Keep AVPlayerLayer mounted so its decoder/session survives cut boundaries, but hide frames outside
            // the clip's timeline window. Overlapping main-lane clips can then both render during a transition.
            drawn.opacity(isOutsideItsTime ? 0 : 1)
        } else if isOutsideItsTime {
            Color.clear.frame(width: 0, height: 0)
        } else {
            drawn
        }
    }

    @ViewBuilder private var drawn: some View {
        let frame = PlaybackMetrics.shared.measure(.sampleLayerMs) { sampleLayer(node.layer, atMs: atMs) }
        Group {
            if node.layer.type == "group" {
                ZStack {
                    ForEach(node.children, id: \.layer.id) { child in
                        LayerNodeView(
                            node: child,
                            atMs: atMs,
                            assets: assets,
                            filters: filters,
                            masks: masks,
                            playerEngine: playerEngine,
                            exportFrames: exportFrames,
                            transitionFramePlan: transitionFramePlan
                        )
                    }
                }
            } else {
                LayerContentView(
                    layerId: node.layer.id,
                    frame: frame, asset: assets.first { $0.id == frame.assetId },
                    filter: node.layer.filter.flatMap { id in filters.first { $0.id == id } },
                    segmentation: node.layer.mask.flatMap { id in masks.first { $0.id == id && $0.segmentation != nil } },
                    playerEngine: playerEngine,
                    exportFrame: exportFrames?[node.layer.id]
                )
                .frame(width: frame.frameWidth, height: frame.frameHeight)
                .modifier(CropEffect(layer: node.layer, assets: assets, frameSize: CGSize(width: frame.frameWidth, height: frame.frameHeight)))
                .modifier(MaskEffect(layer: node.layer, masks: masks, frameSize: CGSize(width: frame.frameWidth, height: frame.frameHeight)))
                .modifier(ClipUnlessText(isText: node.layer.type == "text"))
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

/// Mask tool: shows the layer only where its `V2Mask` (named by `layer.mask`) lets it through, with the mask's feather and invert (`MaskMatteView`). Applied after
/// the crop, to the layer's own box. A layer with no mask, or one this renderer cannot draw, is untouched.
private struct MaskEffect: ViewModifier {
    let layer: V2Layer
    let masks: [V2Mask]
    let frameSize: CGSize

    func body(content: Content) -> some View {
        if let id = layer.mask, let mask = masks.first(where: { $0.id == id }), mask.children != nil {
            content.mask { MaskMatteView(mask: mask, size: frameSize) }
        } else {
            content
        }
    }
}

/// Crop tool: shows only the layer's `V2Crop` region (see `CropLayout`). A layer with no crop is untouched.
private struct CropEffect: ViewModifier {
    let layer: V2Layer
    let assets: [V2Asset]
    let frameSize: CGSize

    func body(content: Content) -> some View {
        if let crop = layer.crop, let plan = CropLayout.plan(frame: frameSize, pictureAspect: pictureAspect, cover: layer.fit != "contain", crop: crop) {
            content
                .scaleEffect(x: (crop.flipped ?? false ? -1 : 1) * plan.zoom, y: plan.zoom)
                .rotationEffect(.degrees(crop.rotation ?? 0))
                .scaleEffect(plan.scale)
                .offset(plan.offset)
                .mask(alignment: .center) { Rectangle().frame(width: plan.visible.width, height: plan.visible.height) }
        } else {
            content
        }
    }

    private var pictureAspect: Double {
        guard let id = layer.assetId, let asset = assets.first(where: { $0.id == id }) else { return 1 }
        switch asset {
        case .image(let image): return image.width / max(image.height, 1)
        case .video(let video): return video.width / max(video.height, 1)
        default: return 1
        }
    }
}

/// Renders one layer's own content (before the shared transform/opacity
/// modifiers `LayerNodeView` applies): a flat color for a shape, a cached
/// still for an image, and an AVPlayer-backed frame for video.
private struct LayerContentView: View {
    let layerId: String
    let frame: ResolvedLayerFrame
    let asset: V2Asset?
    /// Tuỳ chỉnh — see `FilteredImageView`/`FilterRenderer`. `nil` for every
    /// layer that hasn't had a filter applied (the overwhelming common
    /// case), in which case `FilteredImageView` is a pure pass-through.
    let filter: V2Filter?
    /// The layer's Remove BG mask (a `V2Mask` with a `segmentation` source), if any: a photo is drawn cut out.
    let segmentation: V2Mask?
    let playerEngine: EditorPlaybackEngine
    let exportFrame: CGImage?
    @State private var metalReady = false

    var body: some View {
        let contentMode: ContentMode = frame.fit == "contain" ? .fit : .fill
        switch frame.kind {
        case "image":
            if let asset, let uiImage = BundledImageCache.image(filename: asset.uri) {
                SegmentedImageView(sourceKey: asset.uri, source: uiImage.cgImage, mask: segmentation, boxShort: min(frame.frameWidth, frame.frameHeight), filter: filter, contentMode: contentMode)
            } else {
                Color.gray
            }
        case "video":
            if let exportFrame {
                Image(decorative: exportFrame, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode == .fit ? .fit : .fill)
            } else if asset == nil {
                Color.gray
            } else if let player = playerEngine.player(for: layerId) {
                // The raw layer stays mounted under the filtered view. A filter appearing mid-edit (the first
                // Adjust tick) used to swap the raw layer for a brand-new Metal view that needs ~250 ms before its
                // first frame - a black flash; now the raw frame shows until the Metal view has drawn.
                // Remove BG (video): the Metal view cuts each frame with its precomputed matte; once it has drawn, the raw layer
                // (opaque, would show the background through the cut) is hidden.
                let matteSet = segmentation.flatMap { _ in asset.map { VideoMatteStore.shared.set(forAssetURI: $0.uri) } }
                let chromaKeyActive = filter?.primitives.contains { if case .feChromaKey = $0 { return true }; return false } ?? false
                ZStack {
                    StagePlayerLayerView(player: player, contentMode: contentMode)
                        .opacity((matteSet != nil || chromaKeyActive) && metalReady ? 0 : 1)
                    if filter != nil || matteSet != nil {
                        FilteredPlayerView(
                            player: player,
                            filter: filter,
                            previewContentMode: contentMode,
                            requestedSeconds: (frame.sourceMs ?? frame.elapsedMs) / 1000,
                            matteSet: matteSet,
                            matteFeather: segmentation?.feather ?? 0,
                            matteInvert: segmentation?.invert ?? false,
                            onPresented: { metalReady = true }
                        )
                    }
                }
            } else {
                // The engine has not created this layer's player yet (it does
                // on `prepare()`, right after the editor appears).
                Color.clear
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
                if let background = frame.textBackground, let fill = background.fill.flatColor {
                    Path(MotionPathResolver.buildCGPath(contours: background.contours)).fill(Color(hex: fill))
                }
                ForEach(Array((frame.textRuns ?? []).enumerated()), id: \.offset) { _, run in
                    TextRunView(run: run)
                }
            }
            // Not clipped to the frame: outlines, shadows and glows reach past the text block.
            .frame(width: frame.frameWidth, height: frame.frameHeight, alignment: .topLeading)
        default:
            Rectangle().fill(Color(hex: frame.fill ?? "#000000"))
        }
    }
}

/// Attaches a persistent player to an AVPlayerLayer. SwiftUI updates only
/// change the layer configuration; they never create a new player.
private struct StagePlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    let contentMode: ContentMode

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = contentMode == .fit ? .resizeAspect : .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = contentMode == .fit ? .resizeAspect : .resizeAspectFill
    }

    final class PlayerContainerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }

        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}

/// Filtered video preview without a `CGImage` hop. `AVPlayerItemVideoOutput`
/// supplies the player's decoded `CVPixelBuffer`; Core Image evaluates the
/// filter graph lazily and `CIContext` renders the result directly into a
/// Metal drawable. The view keeps the player paused during scrub and draws
/// the newest decoded buffer on the next display tick.
private struct FilteredPlayerView: UIViewRepresentable {
    let player: AVPlayer
    let filter: V2Filter?
    let previewContentMode: SwiftUI.ContentMode
    let requestedSeconds: Double
    /// Remove BG: the video's precomputed mattes (nil = no cut), the mask's feather (px of the layer box) and invert.
    var matteSet: MatteSet?
    var matteFeather: Double = 0
    var matteInvert = false
    var onPresented: () -> Void = {}

    func makeUIView(context: Context) -> FilteredPlayerMetalView {
        let view = FilteredPlayerMetalView(
            player: player,
            filter: filter,
            previewContentMode: previewContentMode,
            requestedSeconds: requestedSeconds
        )
        view.rebindMatte(set: matteSet, feather: matteFeather, invert: matteInvert, onPresented: onPresented)
        return view
    }

    func updateUIView(_ uiView: FilteredPlayerMetalView, context: Context) {
        uiView.rebind(
            player: player,
            filter: filter,
            previewContentMode: previewContentMode,
            requestedSeconds: requestedSeconds
        )
        uiView.rebindMatte(set: matteSet, feather: matteFeather, invert: matteInvert, onPresented: onPresented)
        uiView.setNeedsDisplay()
    }
}

@MainActor
private final class FilteredPlayerMetalView: MTKView {
    private var player: AVPlayer
    private var filter: V2Filter?
    private var previewContentMode: SwiftUI.ContentMode
    private var requestedSeconds: Double
    private var matteSet: MatteSet?
    private var matteFeather = 0.0
    private var matteInvert = false
    private var onPresented: () -> Void = {}
    private var output: AVPlayerItemVideoOutput
    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext
    private let outputColorSpace = CGColorSpaceCreateDeviceRGB()

    init(player: AVPlayer, filter: V2Filter?, previewContentMode: SwiftUI.ContentMode, requestedSeconds: Double) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue()
        else {
            fatalError("Metal is required for filtered video preview")
        }
        self.player = player
        self.filter = filter
        self.previewContentMode = previewContentMode
        self.requestedSeconds = requestedSeconds
        self.output = Self.makeOutput()
        self.commandQueue = commandQueue
        // `.workingColorSpace: NSNull()` like the shared context (CLAUDE.md "Core Image"): with the default (linear) working space the untagged video numbers were encoded to sRGB
        // a second time on output - every filtered / cut video looked washed out (sweater 58 -> 127 of 255, measured on an iPhone 13).
        self.ciContext = CIContext(mtlDevice: device, options: [.cacheIntermediates: false, .workingColorSpace: NSNull()])
        super.init(frame: .zero, device: device)
        framebufferOnly = false
        // Keep a display-synchronised draw loop alive while AVPlayerItemVideoOutput
        // is waiting for the frame produced by an asynchronous seek. A single
        // `setNeedsDisplay` can run before the decoder has published that buffer,
        // which is exactly the blank/stale-frame flash seen after reverse scrubs.
        enableSetNeedsDisplay = false
        isPaused = false
        colorPixelFormat = .bgra8Unorm
        backgroundColor = .clear
        alpha = 0   // invisible until the first frame is presented, so the raw video underneath shows meanwhile
        player.currentItem?.add(output)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }


    func rebindMatte(set: MatteSet?, feather: Double, invert: Bool, onPresented: @escaping () -> Void) {
        matteSet = set
        matteFeather = feather
        matteInvert = invert
        self.onPresented = onPresented
        // A cut frame has transparent pixels: the layer must not be opaque (and every pixel is written, see `draw`).
        let filterHasAlpha = filter?.primitives.contains { if case .feChromaKey = $0 { return true }; return false } ?? false
        let hasTransparency = set != nil || filterHasAlpha
        isOpaque = !hasTransparency
        (layer as? CAMetalLayer)?.isOpaque = !hasTransparency
    }

    func rebind(player: AVPlayer, filter: V2Filter?, previewContentMode: SwiftUI.ContentMode, requestedSeconds: Double) {
        if self.player !== player {
            self.player.currentItem?.remove(output)
            self.output = Self.makeOutput()
            self.player = player
            self.player.currentItem?.add(output)
        }
        self.filter = filter
        self.previewContentMode = previewContentMode
        self.requestedSeconds = requestedSeconds
    }

    override func draw(_ rect: CGRect) {
        let metrics = PlaybackMetrics.shared
        let drawStart = CACurrentMediaTime()
        metrics.count(.metalDraws)
        defer { metrics.record(.metalDrawMs, ms: (CACurrentMediaTime() - drawStart) * 1000) }
        guard let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let item = player.currentItem
        else { return }

        let time = CMTime(seconds: max(requestedSeconds, 0), preferredTimescale: 600)
        var shownTime = CMTime.invalid
        guard let pixelBuffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: &shownTime) else {
            metrics.count(.metalEmptyBuffers)
            commandBuffer.commit()
            return
        }

        var image = CIImage(cvPixelBuffer: pixelBuffer, options: [.colorSpace: NSNull()])
        image = oriented(image, using: item)
        #if DEBUG
        if matteSet != nil { RemoveBGSyncLog.shared.add(requested: requestedSeconds, shown: shownTime.isValid ? shownTime.seconds : .nan, rate: player.rate) }
        #endif
        // The matte belongs to the frame the player really handed over (`shownTime`), not to the playhead: while scrubbing / coasting the player lands on a nearby frame
        // (scrub tolerance 0.2 s, seek lag), measured median 191 ms away, which left the cut a few pixels off the person.
        if let matteSet, let matte = matteSet.matte(atSourceSeconds: shownTime.isValid ? shownTime.seconds : requestedSeconds) {
            image = cut(image, with: matte)
        }
        if let filter { image = FilterRenderer.apply(filter, to: image) }
        image = fitted(image, to: drawableSize)
        if matteSet != nil {
            // Write every pixel (transparent where the cut is, and outside a letterboxed picture), not only the picture's.
            image = image.composited(over: CIImage(color: .clear).cropped(to: CGRect(origin: .zero, size: drawableSize)))
        }
        ciContext.render(
            image,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: image.extent,
            colorSpace: outputColorSpace
        )
        commandBuffer.present(drawable)
        commandBuffer.commit()
        if alpha == 0 { alpha = 1 }
        onPresented()
    }


    /// The frame with its background cleared: alpha = the matte (512 x 512, stretched over the picture), softened by the mask's feather and flipped by invert.
    private func cut(_ image: CIImage, with matte: CIImage) -> CIImage {
        let extent = image.extent
        var mask = matte.transformed(by: CGAffineTransform(scaleX: extent.width / matte.extent.width, y: extent.height / matte.extent.height))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
        if matteInvert { mask = mask.applyingFilter("CIColorInvert") }
        if matteFeather > 0.01 {
            // The feather is in px of the layer's box = `contentScaleFactor` drawable px each; the mask is in picture px, which `fitted` scales to the drawable.
            let sigma = matteFeather * Double(contentScaleFactor) * Double(extent.width / max(drawableSize.width, 1))
            mask = mask.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: extent)
        }
        return image.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: extent), kCIInputMaskImageKey: mask]).cropped(to: extent)
    }

    private static func makeOutput() -> AVPlayerItemVideoOutput {
        AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ])
    }

    private func oriented(_ image: CIImage, using item: AVPlayerItem) -> CIImage {
        guard let track = item.asset.tracks(withMediaType: .video).first else { return image }
        return VideoOrientation.upright(image, transform: track.preferredTransform)
    }

    private func fitted(_ image: CIImage, to size: CGSize) -> CIImage {
        guard size.width > 0, size.height > 0,
              image.extent.width > 0, image.extent.height > 0
        else { return image }
        let scale: CGFloat
        switch previewContentMode {
        case .fit:
            scale = min(size.width / image.extent.width, size.height / image.extent.height)
        case .fill:
            scale = max(size.width / image.extent.width, size.height / image.extent.height)
        @unknown default:
            scale = min(size.width / image.extent.width, size.height / image.extent.height)
        }
        let width = image.extent.width * scale
        let height = image.extent.height * scale
        let x = (size.width - width) / 2 - image.extent.minX * scale
        let y = (size.height - height) / 2 - image.extent.minY * scale
        return image.transformed(by: CGAffineTransform(translationX: x, y: y).scaledBy(x: scale, y: scale))
    }
}

/// A photo, cut out when its layer has a Remove BG mask: the original shows until the cut-out is ready (never nothing), then the cut-out replaces it, and the filter
/// (if any) runs on whichever is showing. The mask's `feather` is in px of the layer's box; it is converted to the picture's pixels proportionally.
private struct SegmentedImageView: View {
    let sourceKey: String
    let source: CGImage?
    let mask: V2Mask?
    let boxShort: Double
    let filter: V2Filter?
    let contentMode: ContentMode

    @State private var cutout: CGImage?

    private var key: String {
        guard let mask, let segmentation = mask.segmentation, let data = try? JSONEncoder().encode(segmentation) else { return "none" }
        return data.base64EncodedString() + "|\(mask.feather ?? 0)|\(mask.invert ?? false)"
    }

    var body: some View {
        FilteredImageView(sourceKey: sourceKey + "|" + (cutout == nil ? "whole" : key), source: cutout ?? source, filter: filter, contentMode: contentMode)
            .task(id: key) {
                guard let mask, let segmentation = mask.segmentation, let source else { cutout = nil; return }
                let pictureShort = Double(min(source.width, source.height))
                let featherPx = (mask.feather ?? 0) * (boxShort > 0 ? pictureShort / boxShort : 1)
                let result = await SegmentationStore.shared.cutout(of: source, sourceKey: sourceKey, segmentation: segmentation, featherPx: featherPx, invert: mask.invert ?? false)
                guard !Task.isCancelled else { return }
                cutout = result
            }
    }
}

/// Tuỳ chỉnh's one display-side entry point: given a raw decoded/cached
/// `CGImage` and an optional `V2Filter`, runs it through `FilterRenderer`
/// asynchronously and draws whichever is freshest — the newly filtered
/// result once it's ready, the previous filtered result while a new one is
/// computing, or the unfiltered `source` if there's no filter (or none has
/// resolved yet). Never renders `Color.clear`/nothing once `source` exists,
/// same "never show nothing" discipline, and never runs `FilterRenderer` synchronously from `body`
/// (see CLAUDE.md's "Rendering notes": never decode media inline from a
/// `body` — filtering is exactly that same category of work).
///
/// Used by the `"image"` layer case — the one place this app draws a `CGImage`
/// onto the Stage; video draws through `AVPlayerLayer`/Metal instead.
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
enum BundledImageCache {
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

/// Every layer is clipped to its frame except text: a text layer's outline, shadow and glow bleed past the text block.
private struct ClipUnlessText: ViewModifier {
    let isText: Bool
    func body(content: Content) -> some View {
        if isText { content } else { content.clipped() }
    }
}

#if DEBUG
/// Measurement (Remove BG on video): per draw, the time the matte is looked up at (`requested`), the time of the frame the player really handed over (`shown`), and the player's rate.
/// Writes `Documents/removebg_sync.csv` (emptied by `REMOVEBG_SYNC_LOG=1` at launch). Used to find out whether the cut lags the picture.
@MainActor
final class RemoveBGSyncLog {
    static let shared = RemoveBGSyncLog()
    private var lines: [String] = []
    private let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("removebg_sync.csv")
    private var started = false

    func add(requested: Double, shown: Double, rate: Float) {
        guard ProcessInfo.processInfo.environment["REMOVEBG_SYNC_LOG"] != nil else { return }
        if !started { started = true; try? "t,requested,shown,rate\n".write(to: url, atomically: true, encoding: .utf8) }
        lines.append(String(format: "%.3f,%.4f,%.4f,%.1f", CACurrentMediaTime(), requested, shown, rate))
        if lines.count >= 60 {
            let chunk = (lines.joined(separator: "\n") + "\n").data(using: .utf8)!
            lines.removeAll(keepingCapacity: true)
            if let handle = try? FileHandle(forWritingTo: url) { handle.seekToEndOfFile(); handle.write(chunk); try? handle.close() }
        }
    }
}
#endif
