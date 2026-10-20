import ImageIO
import SwiftUI

/// What a preset does to a picture at one moment, for the Animation sheet's tiles (user 2026-10-17: the tiles play the animation on
/// `preview-animation.png`, a hot-air balloon, instead of showing an icon). It reads the same channels `AnimationCatalog` lowers into V2 tracks, so a
/// tile moves the way the clip will; the easing is a close stand-in for the real cubic-beziers (a preview, not the renderer).
enum AnimationPreview {
    struct Pose: Equatable {
        /// Translation as a fraction of the tile's width / height (the catalogue's slides are fractions of the canvas).
        var x = 0.0, y = 0.0
        var scaleX = 1.0, scaleY = 1.0
        /// Clockwise degrees.
        var rotation = 0.0
        var opacity = 1.0
    }

    /// `progress` 0...1 along the animation: In runs from the hidden / offset start to rest, Out from rest to the hidden / offset end (the entrance played
    /// backwards), Combo is one cycle of the loop.
    static func pose(of preset: AnimationPreset, slot: AnimationSlot, progress: Double) -> Pose {
        let p = min(max(progress, 0), 1)
        let t = slot == .out ? 1 - p : p
        var pose = Pose()
        for channel in preset.channels {
            let value = sample(channel.keyframes, at: t, slot: slot)
            switch channel.path {
            case "opacity": pose.opacity = value
            case "transform.scale.x": pose.scaleX = value
            case "transform.scale.y": pose.scaleY = value
            case "transform.translate.x": pose.x = value
            case "transform.translate.y": pose.y = value
            case "transform.rotate.z": pose.rotation = value
            default: break
            }
        }
        return pose
    }

    /// A channel's value at `t`: between its two surrounding keyframes, eased (entrance eases out, exit eases in, loop eases in and out).
    private static func sample(_ keys: [(t: Double, value: Double)], at t: Double, slot: AnimationSlot) -> Double {
        guard let first = keys.first, let last = keys.last else { return 0 }
        if t <= first.t { return first.value }
        if t >= last.t { return last.value }
        for i in 0..<(keys.count - 1) where t >= keys[i].t && t <= keys[i + 1].t {
            let span = keys[i + 1].t - keys[i].t
            let u = span > 0 ? (t - keys[i].t) / span : 1
            let eased: Double
            switch slot {
            case .in: eased = 1 - (1 - u) * (1 - u)
            case .out: eased = u * u
            case .combo: eased = u * u * (3 - 2 * u)
            }
            return keys[i].value + (keys[i + 1].value - keys[i].value) * eased
        }
        return last.value
    }

    /// How a tile loops: an entrance or exit plays over `max(its default length, 0.7 s)` with a rest before / after so the eye can follow it; a combo
    /// plays its cycle over and over.
    static func progress(of preset: AnimationPreset, slot: AnimationSlot, atSeconds time: Double) -> Double {
        switch slot {
        case .combo:
            let cycle = max(preset.cycleMs, 100) / 1000
            return time.truncatingRemainder(dividingBy: cycle) / cycle
        case .in:
            let length = max(preset.defaultDurationMs, 700) / 1000
            let period = length + 0.9
            return min(time.truncatingRemainder(dividingBy: period) / length, 1)
        case .out:
            let length = max(preset.defaultDurationMs, 700) / 1000
            let period = length + 0.9
            let phase = time.truncatingRemainder(dividingBy: period)
            return min(max((phase - 0.5) / length, 0), 1)   // a beat at rest first, then out, then a beat gone
        }
    }
}

/// The preview picture, loaded once at the size the tiles need (about 360 px on its long side) and **not cropped**: the tiles are about 73 x 58 pt (5:4)
/// and the picture is 4:3, so filling a tile trims only a few points from the sides - a square crop first would cut the top of the balloon and its basket.
enum AnimationPreviewImage {
    static let filename = "preview-animation.png"
    private static var cached: UIImage?

    @MainActor
    static func load() async -> UIImage? {
        if let cached { return cached }
        guard let url = bundledURL(filename: filename) else { return nil }
        let scale = UIScreen.main.scale
        let image: UIImage? = await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(120 * scale),
            ]
            guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return UIImage(cgImage: thumb, scale: scale, orientation: .up)
        }.value
        cached = image
        return image
    }
}

/// One tile's preview: the balloon picture, cropped to the tile, playing the preset in a loop (about 30 frames a second; only the tiles on screen run).
struct AnimationPreviewTile: View {
    let preset: AnimationPreset
    let slot: AnimationSlot
    let image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let pose = AnimationPreview.pose(of: preset, slot: slot, progress: AnimationPreview.progress(of: preset, slot: slot, atSeconds: time))
                ZStack {
                    if let image {
                        Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .scaleEffect(x: pose.scaleX, y: pose.scaleY)
                            .rotationEffect(.degrees(pose.rotation))
                            .offset(x: pose.x * proxy.size.width, y: pose.y * proxy.size.height)
                            .opacity(pose.opacity)
                    } else {
                        Image(systemName: preset.symbol).font(.system(size: 22)).foregroundColor(.secondary)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }
}
