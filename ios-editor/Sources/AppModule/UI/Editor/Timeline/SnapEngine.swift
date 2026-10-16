import SwiftUI
import UIKit

/// Snapping for everything that moves a time on the timeline - a dragged clip and a trimmed edge (user 2026-10-16). Thresholds are
/// on-screen points, so the feel is the same at every zoom: an edge within 8 pt of a snap point is pulled onto it, and once there
/// it stays until the finger is 14 pt away (no flicker around the point).
enum SnapEngine {
    static let capturePoints = 8.0
    static let releasePoints = 14.0

    struct Result: Equatable {
        /// Added to every edge to land the closest one on `point`.
        var deltaMs: Double
        var point: Double?
    }

    /// `edges`: where the dragged things would be without snapping (ms), `points`: the places they may snap to,
    /// `held`: the point the last call snapped to, if any.
    static func resolve(edges: [Double], points: [Double], pxPerMs: Double, held: Double?) -> Result {
        guard pxPerMs > 0, !edges.isEmpty else { return Result(deltaMs: 0, point: nil) }
        func closestEdge(to point: Double) -> (edge: Double, distance: Double) {
            edges.map { ($0, abs($0 - point)) }.min { $0.1 < $1.1 }!
        }
        if let held {
            let near = closestEdge(to: held)
            if near.distance * pxPerMs <= releasePoints { return Result(deltaMs: held - near.edge, point: held) }
        }
        var best: (point: Double, edge: Double, distance: Double)?
        for point in points {
            let near = closestEdge(to: point)
            if near.distance * pxPerMs <= capturePoints, near.distance < (best?.distance ?? .infinity) {
                best = (point, near.edge, near.distance)
            }
        }
        guard let best else { return Result(deltaMs: 0, point: nil) }
        return Result(deltaMs: best.point - best.edge, point: best.point)
    }
}

/// What a gesture may snap to, taken when the gesture begins (so a trim that ripples its lane does not chase its own
/// neighbours, and the playhead - which auto-scroll moves - stays where it was): t = 0, the playhead, every other clip's
/// edges (audio too), and for a trim the clip's own keyframes. A dragged clip's own keyframes are not points but extra
/// *edges* (they travel with it), so they can snap onto the other points.
@MainActor
final class SnapContext {
    // Refreshed by the timeline on every render.
    var layers: [V2Layer] = []
    var audio = V2AudioDomain(sampleRate: 48000, tracks: [])
    var pxPerMs = 0.096
    var playheadMs = 0.0
    /// Shows (or hides, nil) the vertical snap line.
    var onLine: (Double?) -> Void = { _ in }

    private var points: [Double] = []
    private var held: Double?
    private let haptic = UISelectionFeedbackGenerator()

    func begin(layer: V2Layer, isMove: Bool) {
        held = nil
        var result = [0, playheadMs]
        for other in layers where other.type != "group" && other.id != layer.id {
            if isPushLane(layer) && other.order == layer.order { continue }   // a push lane ripples along with the trimmed edge
            result += [other.timing.start, other.timing.start + other.timing.duration]
        }
        for track in audio.tracks {
            for clip in track.clips { result += [clip.timing.start, clip.timing.start + clip.timing.duration] }
        }
        if !isMove { result += TransformKeyframes.visibleTimelineTimes(of: layer) }
        points = result
        haptic.prepare()
    }

    /// The shift (ms) that lands the closest of `edges` on a snap point, 0 when none is near. Shows the snap line.
    func delta(edges: [Double]) -> Double {
        let result = SnapEngine.resolve(edges: edges, points: points, pxPerMs: pxPerMs, held: held)
        if let point = result.point, point != held { haptic.selectionChanged() }
        held = result.point
        onLine(result.point)
        return result.deltaMs
    }

    func end() {
        held = nil
        points = []
        onLine(nil)
    }
}

private struct SnapContextKey: EnvironmentKey {
    static let defaultValue: SnapContext? = nil
}

extension EnvironmentValues {
    var snapContext: SnapContext? {
        get { self[SnapContextKey.self] }
        set { self[SnapContextKey.self] = newValue }
    }
}
