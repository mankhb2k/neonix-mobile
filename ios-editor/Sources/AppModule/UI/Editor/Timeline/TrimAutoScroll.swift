import SwiftUI
import UIKit

/// Tuning for `TrimAutoScroll` (user decision 2026-10-12): two speed levels by how close the finger is to a screen edge.
/// Speeds are on-screen (pt/s of timeline content), not time, so the glide looks the same at every zoom.
enum TrimAutoScrollTuning {
    /// Finger within this many pt of a screen edge: slow level.
    static let slowZone = 64.0
    /// Finger within this many pt of a screen edge: fast level.
    static let fastZone = 24.0
    static let slowSpeed = 120.0
    static let fastSpeed = 480.0
    /// Seconds to ease from one level to another, so a change of level doesn't jolt.
    static let ramp = 0.15

    /// Signed target speed (pt/s; positive = playhead forward) for a finger at global `x` on a panel `width` wide.
    static func targetSpeed(fingerX x: Double, panelWidth width: Double) -> Double {
        guard width > 0 else { return 0 }
        let leftDepth = x, rightDepth = width - x
        let (depth, sign) = rightDepth < leftDepth ? (rightDepth, 1.0) : (leftDepth, -1.0)
        if depth <= fastZone { return sign * fastSpeed }
        if depth <= slowZone { return sign * slowSpeed }
        return 0
    }
}

/// While a trim handle is held near a screen edge the timeline keeps moving: the playhead (and with it the content)
/// runs toward that edge and the trimmed edge follows, until the finger leaves the zone, lifts, or the trim hits a
/// limit - then everything stops together. The trim itself is applied by the handle's own code (`apply`), called once
/// per display frame with this object's `scrolledMs` added to the finger's own travel.
@MainActor
final class TrimAutoScroll {
    weak var engine: EditorPlaybackEngine?
    var panelWidth = 0.0

    /// Playhead time travelled since the drag began; added to the finger's travel by the handle's trim code.
    private(set) var scrolledMs = 0.0
    private(set) var translationWidth: CGFloat = 0

    private var pxPerMs = 0.096
    /// Re-applies the trim for the current finger position; false = the edge hit a limit.
    private var apply: (() -> Bool)?
    private let clock = DisplayLinkClock()
    private var speed = 0.0
    private var target = 0.0
    private var startTimeMs = 0.0
    private var movedPlayhead = false
    private var halted = false
    private let haptic = UIImpactFeedbackGenerator(style: .rigid)

    /// `allowsNegativeTime`: main-lane left trim - the playhead may follow the edge before t0.
    func begin(pxPerMs: Double, allowsNegativeTime: Bool = false, apply: @escaping () -> Bool) {
        reset()
        engine?.setTimeFloor(allowsNegativeTime ? -1_000_000 : 0)
        self.pxPerMs = pxPerMs
        self.apply = apply
        startTimeMs = engine?.editorTimeMs ?? 0
        haptic.prepare()
    }

    /// Call on every drag change.
    func update(translationWidth: CGFloat, fingerX: Double) {
        self.translationWidth = translationWidth
        target = TrimAutoScrollTuning.targetSpeed(fingerX: fingerX, panelWidth: panelWidth)
        if target == 0 { halted = false }
        if target != 0, !halted, !clock.isRunning {
            clock.start { [weak self] dt in self?.tick(dt) }
        }
    }

    func end() {
        clock.stop()
        if movedPlayhead { engine?.endScrub(velocityMsPerSecond: 0) }
        reset()
    }

    private func reset() {
        clock.stop()
        scrolledMs = 0
        translationWidth = 0
        speed = 0
        target = 0
        movedPlayhead = false
        halted = false
        apply = nil
    }

    private func tick(_ dt: Double) {
        let goal = halted ? 0 : target
        speed += (goal - speed) * min(dt / TrimAutoScrollTuning.ramp, 1)
        if goal == 0, abs(speed) < 1 {
            speed = 0
            clock.stop()
            return
        }
        var advance = speed * dt / pxPerMs
        // The playhead stops at the engine's time floor (0, or far below on a main-lane left trim): going on would let
        // the edge slip away from the finger.
        var reachedFloor = false
        let floor = engine?.timeFloorMs ?? 0
        if startTimeMs + scrolledMs + advance <= floor {
            advance = floor - (startTimeMs + scrolledMs)
            reachedFloor = true
        }
        scrolledMs += advance
        if apply?() == false {
            // Limit reached: the playhead stays where it was one frame ago, so it stops together with the edge.
            scrolledMs -= advance
            speed = 0
            halted = true
            clock.stop()
            haptic.impactOccurred()
            return
        }
        guard let engine else { return }
        engine.beginScrub()   // idempotent; re-enters scrub mode if something else ended it
        movedPlayhead = true
        engine.scrub(toMs: startTimeMs + scrolledMs)
        if reachedFloor {
            speed = 0
            halted = true
            clock.stop()
            haptic.impactOccurred()
        }
    }
}

private struct TrimAutoScrollKey: EnvironmentKey {
    static let defaultValue: TrimAutoScroll? = nil
}

extension EnvironmentValues {
    var trimAutoScroll: TrimAutoScroll? {
        get { self[TrimAutoScrollKey.self] }
        set { self[TrimAutoScrollKey.self] = newValue }
    }
}
