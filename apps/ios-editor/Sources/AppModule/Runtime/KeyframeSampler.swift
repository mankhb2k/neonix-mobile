import Foundation
import UIKit

/// Resolves a layer-track keyframe time to an absolute layer-local
/// millisecond offset. `boundMs` is the owning layer's `timing.duration` for
/// an ordinary track, or `track.animation.durationMs` (the length of one
/// cycle) for a looping track. Mirrors `resolveV2KeyframeTime` in
/// `packages/motion-protocol/src/v2/animation.ts` exactly.
func resolveKeyframeTime(_ time: V2KeyframeTime, boundMs: Double) -> Double {
    switch time {
    case .absolute(let ms):
        return ms
    case .anchored(let anchor, let offsetMs):
        return anchor == .start ? offsetMs : boundMs - offsetMs
    }
}

/// Standard CSS-style cubic-bezier easing: solves for `t` such that the
/// bezier's x-component equals `x`, then returns the corresponding
/// y-component. `x1`/`x2` are expected in `0...1` (enforced by the protocol
/// schema); `y1`/`y2` may overshoot.
func cubicBezierEase(x1: Double, y1: Double, x2: Double, y2: Double, x: Double) -> Double {
    func bezier(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
    }
    var lo = 0.0
    var hi = 1.0
    var t = x
    for _ in 0..<20 {
        t = (lo + hi) / 2
        let guessX = bezier(t, x1, x2)
        if guessX < x {
            lo = t
        } else {
            hi = t
        }
    }
    return bezier(t, y1, y2)
}

/// Interpolates a single track's value at local time `localMs` (already
/// resolved relative to the layer, i.e. the loop cycle math below has
/// already been applied by the caller). Keyframe times here are resolved
/// against `boundMs` per `resolveKeyframeTime`.
private func interpolate(track: V2Track, boundMs: Double, atMs localMs: Double) -> Double {
    // Only `.number` keyframe values are interpolated — see `V2AnimatableValue.asNumber`.
    let resolved = track.keyframes.map { (time: resolveKeyframeTime($0.time, boundMs: boundMs), value: $0.value.asNumber ?? 0, easing: $0.easing) }
    guard let first = resolved.first else { return 0 }
    if localMs <= first.time { return first.value }
    guard let last = resolved.last else { return first.value }
    if localMs >= last.time { return last.value }

    for index in 1..<resolved.count {
        let from = resolved[index - 1]
        let to = resolved[index]
        guard localMs >= from.time, localMs <= to.time else { continue }
        let span = to.time - from.time
        guard span > 0 else { return to.value }
        let t = (localMs - from.time) / span
        let eased: Double
        switch from.easing {
        case .some(.cubicBezier(let x1, let y1, let x2, let y2)):
            eased = cubicBezierEase(x1: x1, y1: y1, x2: x2, y2: y2, x: t)
        case .none, .some(.linear), .some(.step), .some(.spring):
            // `step`/`spring` are a known gap — fall back to linear at sample
            // time (see V2Easing's doc comment).
            eased = t
        }
        return from.value + (to.value - from.value) * eased
    }
    return last.value
}

/// Maps the layer-local elapsed time (since `layer.timing.start`) through a
/// track's `animation` loop policy — cycle index, direction, iteration
/// count — into the local time to sample keyframes at. `fillMode`'s exact
/// backwards/forwards split and `delayMs` edge behavior are simplified here
/// to clamping at the first/last keyframe (equivalent to `fillMode: "both"`)
/// — a known, intentionally scoped-down gap for this first slice; see
/// ARCHITECTURE.md / the plan this was built from.
private func loopedLocalTime(animation: V2AnimationPlayback, elapsedMs: Double) -> Double {
    let playElapsed = animation.playState == .paused ? 0 : elapsedMs
    let sinceDelay = playElapsed - animation.delayMs
    if sinceDelay <= 0 { return 0 }

    let durationMs = max(animation.durationMs, 0.0001)
    var cycleIndex = floor(sinceDelay / durationMs)
    var cycleLocal = sinceDelay - cycleIndex * durationMs

    if case .count(let iterations) = animation.iterations {
        let maxCycleIndex = max(iterations - 1, 0)
        if cycleIndex > maxCycleIndex {
            cycleIndex = maxCycleIndex
            cycleLocal = durationMs
        }
    }

    let playsReversed: Bool
    switch animation.direction {
    case .normal: playsReversed = false
    case .reverse: playsReversed = true
    case .alternate: playsReversed = Int(cycleIndex) % 2 == 1
    case .alternateReverse: playsReversed = Int(cycleIndex) % 2 == 0
    }
    return playsReversed ? durationMs - cycleLocal : cycleLocal
}

/// Samples one track at absolute composition time `atMs`, honoring the
/// layer's own `timing.start`/`timing.duration` and the track's optional
/// loop `animation`. Returns the authored static value's delta is not
/// applied here — callers combine this with the layer's static transform.
func sample(track: V2Track, layer: V2Layer, atMs: Double) -> Double {
    let elapsedMs = atMs - layer.timing.start
    if let animation = track.animation {
        let localMs = loopedLocalTime(animation: animation, elapsedMs: elapsedMs)
        return interpolate(track: track, boundMs: animation.durationMs, atMs: localMs)
    }
    let clampedMs = min(max(elapsedMs, 0), layer.timing.duration)
    return interpolate(track: track, boundMs: layer.timing.duration, atMs: clampedMs)
}

struct ResolvedLayerFrame {
    /// "shape" | "image" | "video"
    var kind: String
    var assetId: String?
    var fit: String?
    var frameWidth: Double
    var frameHeight: Double
    var fill: String?
    var opacity: Double
    var translateX: Double
    var translateY: Double
    var scaleX: Double
    var scaleY: Double
    /// Degrees.
    var rotateX: Double
    /// Degrees.
    var rotateY: Double
    /// Degrees.
    var rotateZ: Double
    /// CSS-style perspective distance for `rotateX`/`rotateY`, if authored.
    var perspective: Double?
    /// Layer-local elapsed time, clamped to `[0, timing.duration]`. Video
    /// layers use this to pick which source frame to extract.
    var elapsedMs: Double
    /// Resolved per-line text runs, `kind == "text"` only — see
    /// `ResolvedTextRun`. Always already-shaped (no wrap/align left to
    /// decide); the renderer only ever draws these numbers.
    var textRuns: [ResolvedTextRun]?
}

/// One already-positioned, already-substringed piece of text ready to draw —
/// derived read-only from `V2TextChunk`/`V2TextSpan` plus the source string,
/// the same way `rotateZ`/`translateX` are derived from the layer transform.
/// Not part of Protocol V2 itself: `x`/`y` here are top-left (for SwiftUI),
/// converted from the protocol's SVG-style baseline `y` using the same font
/// metrics `TextLayoutCompiler` resolved the layout against.
struct ResolvedTextRun {
    var text: String
    var x: Double
    var y: Double
    var fontFamily: String
    var fontSize: Double
    var color: V2Color
}

/// Flattens a text layer's already-shaped chunks/spans into drawable runs.
/// Text layers in this app are static (no track-driven animation of text
/// content yet — a known, separate gap from protocol shape parity), so this
/// only needs the layer's own payload, not `atMs`.
private func resolveTextRuns(_ payload: V2TextLayerPayload) -> [ResolvedTextRun] {
    let utf16 = Array(payload.source.text.utf16)
    var runs: [ResolvedTextRun] = []
    for chunk in payload.chunks {
        guard let x = chunk.x?.first?.numericValue, let baselineY = chunk.y?.first?.numericValue else { continue }
        for span in chunk.spans {
            let start = span.sourceRange.start
            let end = min(span.sourceRange.end, utf16.count)
            guard start < end, start >= 0 else { continue }
            let substring = String(decoding: utf16[start..<end], as: UTF16.self)
            let fontFamily = span.font.families.first ?? "Helvetica"
            let fontSize = span.font.size.numericValue
            let font = TextLayoutCompiler.resolveFont(family: fontFamily, size: fontSize)
            let topY = baselineY - Double(font.ascender)
            runs.append(ResolvedTextRun(
                text: substring, x: x, y: topY,
                fontFamily: fontFamily, fontSize: fontSize,
                color: span.fill?.flatColor ?? "#FFFFFFFF"
            ))
        }
    }
    return runs
}

/// Resolves every animatable field this slice supports for one layer at
/// absolute composition time `atMs`: starts from the layer's static
/// (non-animated) values, then overwrites with any track whose `path`
/// targets that field.
func sampleLayer(_ layer: V2Layer, atMs: Double) -> ResolvedLayerFrame {
    var frame = ResolvedLayerFrame(
        kind: layer.type,
        assetId: layer.assetId,
        fit: layer.fit,
        frameWidth: layer.frame.width,
        frameHeight: layer.frame.height,
        fill: layer.fillColor,
        opacity: layer.opacity ?? 1,
        translateX: layer.transform.translate.x,
        translateY: layer.transform.translate.y,
        scaleX: layer.transform.scale.x,
        scaleY: layer.transform.scale.y,
        rotateX: layer.transform.rotate.x,
        rotateY: layer.transform.rotate.y,
        rotateZ: layer.transform.rotate.z,
        perspective: layer.transform.perspective,
        elapsedMs: min(max(atMs - layer.timing.start, 0), layer.timing.duration),
        textRuns: layer.textPayload.map(resolveTextRuns)
    )

    for track in layer.tracks ?? [] {
        switch track.path {
        case "opacity":
            frame.opacity = sample(track: track, layer: layer, atMs: atMs)
        case "transform.translate.x":
            frame.translateX = sample(track: track, layer: layer, atMs: atMs)
        case "transform.translate.y":
            frame.translateY = sample(track: track, layer: layer, atMs: atMs)
        case "transform.scale.x":
            frame.scaleX = sample(track: track, layer: layer, atMs: atMs)
        case "transform.scale.y":
            frame.scaleY = sample(track: track, layer: layer, atMs: atMs)
        case "transform.rotate.x":
            frame.rotateX = sample(track: track, layer: layer, atMs: atMs)
        case "transform.rotate.y":
            frame.rotateY = sample(track: track, layer: layer, atMs: atMs)
        case "transform.rotate.z":
            frame.rotateZ = sample(track: track, layer: layer, atMs: atMs)
        default:
            continue
        }
    }

    return frame
}
