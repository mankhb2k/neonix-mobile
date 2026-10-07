import Foundation
import UIKit

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

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

/// CSS `steps()` timing function — a hard on/off switch, no blending
/// between keyframe values. `jump-end` (the schema default) holds the
/// starting value for the whole segment and only flips at the very end
/// (which the caller's own `localMs >= last.time` boundary check, not this
/// function, is what actually returns the end value); `jump-start` flips
/// at the start of each step instead. Used for an "instant" per-character
/// reveal (no fade) — see `rangeSelectors`' `reveal: "instant"` in
/// `PresetCompiler.swift`.
func stepEase(count: Int, position: String, t: Double) -> Double {
    let steps = max(count, 1)
    let stepIndex = min(Int(t * Double(steps)), steps - 1)
    switch position {
    case "jump-start", "jump-both":
        return Double(stepIndex + 1) / Double(steps)
    default: // "jump-end", "jump-none"
        return Double(stepIndex) / Double(steps)
    }
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
        case .some(.step(let count, let position)):
            eased = stepEase(count: count ?? 1, position: position ?? "jump-end", t: t)
        case .none, .some(.linear), .some(.spring):
            // `spring` is a known gap — falls back to linear at sample time
            // (see V2Easing's doc comment). `.none`/`.linear` are linear by
            // definition.
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
    /// Depth — no own 2D position, only feeds the perspective-based
    /// apparent-scale approximation in `PreviewCanvas.swift` (real z-axis
    /// depth compositing isn't implemented; this matches how CSS
    /// `translateZ` reads on a flat element outside a `preserve-3d`
    /// context).
    var translateZ: Double
    var scaleX: Double
    var scaleY: Double
    /// Stored for round-trip fidelity only — a flat 2D layer with no
    /// `preserve-3d` child depth has no own visual use for its *own*
    /// z-axis scale (matches real CSS/After Effects semantics: `scale.z`
    /// only matters for 3D content that itself extends in z). Not a
    /// renderer gap.
    var scaleZ: Double
    /// Degrees.
    var skewX: Double
    /// Degrees.
    var skewY: Double
    /// Pivot offset from the layer's own center, in local units — see
    /// CLAUDE.md's "Transform anchor is an offset from center" note.
    var anchorX: Double
    var anchorY: Double
    var anchorZ: Double
    /// Degrees.
    var rotateX: Double
    /// Degrees.
    var rotateY: Double
    /// Degrees.
    var rotateZ: Double
    /// CSS-style perspective distance for `rotateX`/`rotateY`/`translateZ`,
    /// if authored.
    var perspective: Double?
    /// Additional position/rotation from `layer.motion` (CSS `offset-path`),
    /// already resolved for this frame by `MotionPathResolver` — `0`/`0`/`0`
    /// (a no-op) when the layer has no `motion`. Added on top of
    /// `translateX`/`translateY`/`rotateZ` the same way those are added;
    /// see CLAUDE.md's motion-path note.
    var motionDx: Double = 0
    var motionDy: Double = 0
    var motionRotation: Double = 0
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
    /// Always `1` unless a `rangeSelectors` stagger entry applies to this
    /// run's character — see `resolveTextRuns`.
    var opacity: Double = 1
    /// Degrees — from `V2TextChunk.rotate[i]`, always `0` otherwise.
    var rotation: Double = 0
}

/// Which stagger entry (if any) a given absolute source-text character
/// index falls under, plus its 0-based position within that selector's own
/// range (already reordered for `direction: "reverse"`) and the range's
/// total unit count. `nil` when no `unit: "character"` selector covers it —
/// `unit: "word"` is reserved but not implemented, matching the real
/// schema's own fail-closed note, so word selectors are simply skipped here.
private func staggerPosition(forSourceIndex index: Int, in selectors: [V2TextRangeSelector], totalLength: Int) -> (selector: V2TextRangeSelector, position: Int)? {
    for selector in selectors where selector.unit == "character" {
        let start: Int
        let end: Int
        switch selector.range {
        case .all: start = 0; end = totalLength
        case .range(let r): start = r.start; end = r.end
        }
        guard index >= start, index < end else { continue }
        let total = end - start
        let forward = index - start
        let position = (selector.stagger.direction == "reverse") ? (total - 1 - forward) : forward
        return (selector, position)
    }
    return nil
}

/// Flattens a text layer's already-shaped chunks/spans into drawable runs,
/// splitting a span into one run per character whenever per-character data
/// actually applies to it — either a `rangeSelectors` stagger entry (see
/// CLAUDE.md's "`rangeSelectors` stays in Protocol V2" note — the Runtime
/// interpreting that compact, unexpanded intent directly, in place of a
/// separate motion-compiler stage) or the chunk's own `dx`/`dy`/`rotate`
/// arrays (already fully atomic literal numbers — no compiler-side
/// expansion needed, just reading them). A chunk with none of these stays
/// one run per span, same as before.
private func resolveTextRuns(_ payload: V2TextLayerPayload, layer: V2Layer, atMs: Double) -> [ResolvedTextRun] {
    let utf16 = Array(payload.source.text.utf16)
    let selectors = payload.rangeSelectors ?? []
    var runs: [ResolvedTextRun] = []

    for chunk in payload.chunks {
        guard let x = chunk.x?.first?.numericValue, let baselineY = chunk.y?.first?.numericValue else { continue }
        let chunkStart = chunk.sourceRange.start
        let chunkEnd = min(chunk.sourceRange.end, utf16.count)
        guard chunkStart < chunkEnd else { continue }
        let lineText = String(decoding: utf16[chunkStart..<chunkEnd], as: UTF16.self)
        let hasPerCharacterOffsets = chunk.dx != nil || chunk.dy != nil || chunk.rotate != nil

        for span in chunk.spans {
            let start = span.sourceRange.start
            let end = min(span.sourceRange.end, utf16.count)
            guard start < end, start >= 0 else { continue }
            let fontFamily = span.font.families.first ?? "Helvetica"
            let fontSize = span.font.size.numericValue
            let font = TextLayoutCompiler.resolveFont(family: fontFamily, size: fontSize)
            let topY = baselineY - Double(font.ascender)
            let color = span.fill?.flatColor ?? "#FFFFFFFF"

            let staggered = !selectors.isEmpty && (start..<end).contains { staggerPosition(forSourceIndex: $0, in: selectors, totalLength: utf16.count) != nil }
            guard staggered || hasPerCharacterOffsets else {
                let substring = String(decoding: utf16[start..<end], as: UTF16.self)
                runs.append(ResolvedTextRun(text: substring, x: x, y: topY, fontFamily: fontFamily, fontSize: fontSize, color: color))
                continue
            }

            for sourceIndex in start..<end {
                let localIndex = sourceIndex - chunkStart
                let character = String(decoding: [utf16[sourceIndex]], as: UTF16.self)
                let extraDx = chunk.dx?[safe: localIndex]?.numericValue ?? 0
                let extraDy = chunk.dy?[safe: localIndex]?.numericValue ?? 0
                let rotation = chunk.rotate?[safe: localIndex] ?? 0
                let charX = x + TextLayoutCompiler.offsetForCharacter(in: lineText, font: font, localIndex: localIndex) + extraDx
                var opacity = 1.0
                if let (selector, position) = staggerPosition(forSourceIndex: sourceIndex, in: selectors, totalLength: utf16.count) {
                    let elapsedMs = atMs - layer.timing.start
                    let delayMs = Double(position) * selector.stagger.perUnitDelayMs
                    let localMs = min(max(elapsedMs - delayMs, 0), layer.timing.duration)
                    opacity = interpolate(track: selector.track, boundMs: layer.timing.duration, atMs: localMs)
                }
                runs.append(ResolvedTextRun(text: character, x: charX, y: topY + extraDy, fontFamily: fontFamily, fontSize: fontSize, color: color, opacity: opacity, rotation: rotation))
            }
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
        translateZ: layer.transform.translate.z,
        scaleX: layer.transform.scale.x,
        scaleY: layer.transform.scale.y,
        scaleZ: layer.transform.scale.z,
        skewX: layer.transform.skew.x,
        skewY: layer.transform.skew.y,
        anchorX: layer.transform.anchor.x,
        anchorY: layer.transform.anchor.y,
        anchorZ: layer.transform.anchor.z,
        rotateX: layer.transform.rotate.x,
        rotateY: layer.transform.rotate.y,
        rotateZ: layer.transform.rotate.z,
        perspective: layer.transform.perspective,
        elapsedMs: min(max(atMs - layer.timing.start, 0), layer.timing.duration),
        textRuns: layer.textPayload.map { resolveTextRuns($0, layer: layer, atMs: atMs) }
    )

    var motionOffsetDistance = layer.motion?.offsetDistance ?? 0
    // Not itself animatable — `COMMON_NUMBER_PATHS` only covers
    // `offsetRotate.angle`, not `.mode` (a string enum, not a number).
    let motionOffsetRotateMode = layer.motion?.offsetRotate?.mode ?? "auto"
    var motionOffsetRotateAngle = layer.motion?.offsetRotate?.angle ?? 0
    var motionOffsetAnchorX = layer.motion?.offsetAnchor?.x ?? 0
    var motionOffsetAnchorY = layer.motion?.offsetAnchor?.y ?? 0

    for track in layer.tracks ?? [] {
        switch track.path {
        case "opacity":
            frame.opacity = sample(track: track, layer: layer, atMs: atMs)
        case "frame.width":
            frame.frameWidth = sample(track: track, layer: layer, atMs: atMs)
        case "frame.height":
            frame.frameHeight = sample(track: track, layer: layer, atMs: atMs)
        case "transform.translate.x":
            frame.translateX = sample(track: track, layer: layer, atMs: atMs)
        case "transform.translate.y":
            frame.translateY = sample(track: track, layer: layer, atMs: atMs)
        case "transform.translate.z":
            frame.translateZ = sample(track: track, layer: layer, atMs: atMs)
        case "transform.scale.x":
            frame.scaleX = sample(track: track, layer: layer, atMs: atMs)
        case "transform.scale.y":
            frame.scaleY = sample(track: track, layer: layer, atMs: atMs)
        case "transform.scale.z":
            frame.scaleZ = sample(track: track, layer: layer, atMs: atMs)
        case "transform.skew.x":
            frame.skewX = sample(track: track, layer: layer, atMs: atMs)
        case "transform.skew.y":
            frame.skewY = sample(track: track, layer: layer, atMs: atMs)
        case "transform.anchor.x":
            frame.anchorX = sample(track: track, layer: layer, atMs: atMs)
        case "transform.anchor.y":
            frame.anchorY = sample(track: track, layer: layer, atMs: atMs)
        case "transform.anchor.z":
            frame.anchorZ = sample(track: track, layer: layer, atMs: atMs)
        case "transform.rotate.x":
            frame.rotateX = sample(track: track, layer: layer, atMs: atMs)
        case "transform.rotate.y":
            frame.rotateY = sample(track: track, layer: layer, atMs: atMs)
        case "transform.rotate.z":
            frame.rotateZ = sample(track: track, layer: layer, atMs: atMs)
        case "motion.offsetDistance":
            motionOffsetDistance = sample(track: track, layer: layer, atMs: atMs)
        case "motion.offsetRotate.angle":
            motionOffsetRotateAngle = sample(track: track, layer: layer, atMs: atMs)
        case "motion.offsetAnchor.x":
            motionOffsetAnchorX = sample(track: track, layer: layer, atMs: atMs)
        case "motion.offsetAnchor.y":
            motionOffsetAnchorY = sample(track: track, layer: layer, atMs: atMs)
        default:
            continue
        }
    }

    if let motion = layer.motion {
        let resolved = MotionPathResolver.resolve(
            motion: motion, offsetDistance: motionOffsetDistance, offsetRotateMode: motionOffsetRotateMode,
            offsetRotateAngle: motionOffsetRotateAngle, offsetAnchorX: motionOffsetAnchorX, offsetAnchorY: motionOffsetAnchorY
        )
        frame.motionDx = resolved.dx
        frame.motionDy = resolved.dy
        frame.motionRotation = resolved.rotationDegrees
    }

    return frame
}
