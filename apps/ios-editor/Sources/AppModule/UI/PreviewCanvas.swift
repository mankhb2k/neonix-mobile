import AVFoundation
import SwiftUI

struct PreviewCanvas: View {
    let composition: V2Composition
    let assets: [V2Asset]
    let frames: [ResolvedLayerFrame]
    /// Set only while a video layer is actively playing (see
    /// `EditorDemoView`): that one layer renders the live `AVPlayer` output
    /// instead of an extracted still frame. Paused/scrubbing, or the static
    /// fixtures, never set this.
    var activePlayer: (assetId: String, player: AVPlayer)? = nil

    var body: some View {
        ZStack {
            Color(hex: composition.background)
            ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                LayerContentView(frame: frame, asset: assets.first { $0.id == frame.assetId }, activePlayer: activePlayer)
                    .frame(width: frame.frameWidth * frame.scaleX, height: frame.frameHeight * frame.scaleY)
                    .clipped()
                    .rotation3DEffect(.degrees(frame.rotateX), axis: (x: 1, y: 0, z: 0), perspective: frame.perspective ?? 1)
                    .rotation3DEffect(.degrees(frame.rotateY), axis: (x: 0, y: 1, z: 0), perspective: frame.perspective ?? 1)
                    .rotationEffect(.degrees(frame.rotateZ))
                    .opacity(frame.opacity)
                    .offset(x: frame.translateX, y: frame.translateY)
            }
        }
        .frame(width: composition.width, height: composition.height)
        .clipped()
    }
}

/// Renders one layer's own content (before the shared transform/opacity
/// modifiers `PreviewCanvas` applies): a flat color for a shape, or a still
/// frame for image/video — see `VideoFrameCache` for why video uses a
/// synchronously-extracted frame rather than `AVPlayer`.
private struct LayerContentView: View {
    let frame: ResolvedLayerFrame
    let asset: V2Asset?
    let activePlayer: (assetId: String, player: AVPlayer)?

    var body: some View {
        let contentMode: ContentMode = frame.fit == "contain" ? .fit : .fill
        switch frame.kind {
        case "image":
            if let asset, let uiImage = bundledImage(filename: asset.uri) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color.gray
            }
        case "video":
            if let asset, let activePlayer, activePlayer.assetId == asset.id {
                VideoPlayerLayerView(player: activePlayer.player, gravity: contentMode == .fit ? .resizeAspect : .resizeAspectFill)
            } else if let asset, let url = bundledURL(filename: asset.uri),
               let uiImage = VideoFrameCache.shared.frame(assetId: asset.id, url: url, atSeconds: frame.elapsedMs / 1000) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color.gray
            }
        case "text":
            // `.fixedSize()` lets each line report its true (possibly
            // overflowing, e.g. `wrap: "none"`) width upward — without an
            // explicit `alignment: .topLeading` frame right here, the next
            // fixed-size `.frame(width:height:)` up in `PreviewCanvas`
            // would silently *center* that oversized content instead of
            // anchoring it at the resolved `x`/`y` this view already
            // computed, which would make every `x`/`y` below meaningless.
            ZStack(alignment: .topLeading) {
                ForEach(Array((frame.textRuns ?? []).enumerated()), id: \.offset) { _, run in
                    Text(run.text)
                        .font(.custom(run.fontFamily, size: run.fontSize))
                        .foregroundColor(Color(hex: run.color))
                        .fixedSize()
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

/// Resources bundled via SwiftPM's `.process()` rule are flattened to the
/// bundle root (see `loadFixture` in `ContentView.swift`), so lookup is by
/// filename alone, split into base name + extension.
func bundledURL(filename: String) -> URL? {
    let parts = filename.split(separator: ".", maxSplits: 1)
    guard parts.count == 2 else { return nil }
    return Bundle.module.url(forResource: String(parts[0]), withExtension: String(parts[1]))
}

private func bundledImage(filename: String) -> UIImage? {
    guard let url = bundledURL(filename: filename), let image = UIImage(contentsOfFile: url.path) else { return nil }
    return image
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
