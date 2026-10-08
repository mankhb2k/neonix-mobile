import XCTest
@testable import NeonixEditor

final class KeyframeSamplerTests: XCTestCase {
    func testResolveKeyframeTimeAbsolute() {
        XCTAssertEqual(resolveKeyframeTime(.absolute(600), boundMs: 2000), 600)
    }

    func testResolveKeyframeTimeStartAnchor() {
        XCTAssertEqual(resolveKeyframeTime(.anchored(anchor: .start, offsetMs: 0), boundMs: 2000), 0)
    }

    func testResolveKeyframeTimeEndAnchorStaysCorrectAcrossTrim() {
        // Same authored offset, different layer durations — this is exactly
        // the trim-safety property the protocol-v2 anchor redesign exists for.
        XCTAssertEqual(resolveKeyframeTime(.anchored(anchor: .end, offsetMs: 300), boundMs: 2000), 1700)
        XCTAssertEqual(resolveKeyframeTime(.anchored(anchor: .end, offsetMs: 300), boundMs: 500), 200)
    }

    func testFadeOutFixtureResolvesToZeroAtClipEnd() throws {
        let project = try XCTUnwrap(decodeFixtureJSON(fadeOutFixtureJSON))
        let layer = try XCTUnwrap(project.layers.first)
        XCTAssertEqual(sampleLayer(layer, atMs: 0).opacity, 1, accuracy: 0.0001)
        XCTAssertEqual(sampleLayer(layer, atMs: 2000).opacity, 0, accuracy: 0.0001)
        // Halfway through the 300ms fade window (1700...2000): ~0.5.
        XCTAssertEqual(sampleLayer(layer, atMs: 1850).opacity, 0.5, accuracy: 0.01)
    }

    func testLoopSpinFixtureCompletesFullRotationsEveryCycle() throws {
        let project = try XCTUnwrap(decodeFixtureJSON(loopSpinFixtureJSON))
        let layer = try XCTUnwrap(project.layers.first)
        XCTAssertEqual(sampleLayer(layer, atMs: 0).rotateZ, 0, accuracy: 0.0001)
        XCTAssertEqual(sampleLayer(layer, atMs: 500).rotateZ, 180, accuracy: 0.01)
        // A cycle longer than this clip's own duration must still bound
        // correctly against animation.durationMs (the loop-bound fix).
        XCTAssertEqual(sampleLayer(layer, atMs: 3500).rotateZ, 180, accuracy: 0.01)
    }

    func testFlip3DFixtureEasesFromNegative90ToZero() throws {
        let project = try XCTUnwrap(decodeFixtureJSON(flip3DFixtureJSON))
        let layer = try XCTUnwrap(project.layers.first)
        XCTAssertEqual(sampleLayer(layer, atMs: 0).rotateY, -90, accuracy: 0.0001)
        XCTAssertEqual(sampleLayer(layer, atMs: 400).rotateY, 0, accuracy: 0.0001)
        let midway = sampleLayer(layer, atMs: 200).rotateY
        XCTAssertGreaterThan(midway, -90)
        XCTAssertLessThan(midway, 0)
    }

    func testTransformCoverageFixtureAnimatesAllNewlyCoveredPaths() throws {
        let project = try XCTUnwrap(decodeFixtureJSON(transformCoverageFixtureJSON))
        let layer = try XCTUnwrap(project.layers.first)

        let start = sampleLayer(layer, atMs: 0)
        XCTAssertEqual(start.frameWidth, 160, accuracy: 0.0001)
        XCTAssertEqual(start.skewX, 10, accuracy: 0.0001)
        XCTAssertEqual(start.anchorX, 40, accuracy: 0.0001)
        XCTAssertEqual(start.translateZ, 0, accuracy: 0.0001)
        XCTAssertEqual(start.scaleZ, 1, accuracy: 0.0001)

        let end = sampleLayer(layer, atMs: 1000)
        XCTAssertEqual(end.frameWidth, 260, accuracy: 0.0001)
        XCTAssertEqual(end.translateZ, 300, accuracy: 0.0001)
        XCTAssertEqual(end.scaleZ, 2, accuracy: 0.0001)
        // Static (untracked) fields still come through from `transform` as-is.
        XCTAssertEqual(end.skewX, 10, accuracy: 0.0001)
        XCTAssertEqual(end.skewY, -5, accuracy: 0.0001)
        XCTAssertEqual(end.anchorX, 40, accuracy: 0.0001)
        XCTAssertEqual(end.anchorY, -20, accuracy: 0.0001)
        XCTAssertEqual(end.anchorZ, 5, accuracy: 0.0001)

        let mid = sampleLayer(layer, atMs: 500)
        XCTAssertEqual(mid.frameWidth, 210, accuracy: 0.01)
        XCTAssertEqual(mid.translateZ, 150, accuracy: 0.01)
    }

    func testMotionPathSquareFixtureFollowsOffsetDistanceAlongLineSegments() throws {
        let project = try XCTUnwrap(decodeFixtureJSON(motionPathSquareFixtureJSON))
        let layer = try XCTUnwrap(project.layers.first)

        // t=0: offsetDistance 0 — the path's own start point (0,0), minus
        // the authored offsetAnchor (10, 5).
        let start = sampleLayer(layer, atMs: 0)
        XCTAssertEqual(start.motionDx, -10, accuracy: 0.01)
        XCTAssertEqual(start.motionDy, -5, accuracy: 0.01)
        XCTAssertEqual(start.motionRotation, 0, accuracy: 0.01)

        // t=250/1000 -> offsetDistance 0.25 -> exactly a quarter of the way
        // around a 400-unit perimeter (100 units per side) -> the (100,0)
        // corner, still along the first (horizontal) edge.
        let quarter = sampleLayer(layer, atMs: 250)
        XCTAssertEqual(quarter.motionDx, 90, accuracy: 0.01)
        XCTAssertEqual(quarter.motionDy, -5, accuracy: 0.01)
        XCTAssertEqual(quarter.motionRotation, 0, accuracy: 0.01)

        // t=500/1000 -> offsetDistance 0.5 -> the (100,100) corner, now
        // along the second (vertical) edge — "auto" rotate mode should
        // report the new 90° tangent.
        let half = sampleLayer(layer, atMs: 500)
        XCTAssertEqual(half.motionDx, 90, accuracy: 0.01)
        XCTAssertEqual(half.motionDy, 95, accuracy: 0.01)
        XCTAssertEqual(half.motionRotation, 90, accuracy: 0.01)
    }

    func testMotionPathArcToBezierApproximatesATrueCircle() {
        let contours = [
            V2PathContour(
                id: "circle", start: V2PathPoint(x: 50, y: 0),
                segments: [
                    .arc(radii: V2PathPoint(x: 50, y: 50), rotation: 0, largeArc: false, sweep: true, to: V2PathPoint(x: -50, y: 0)),
                    .arc(radii: V2PathPoint(x: 50, y: 50), rotation: 0, largeArc: false, sweep: true, to: V2PathPoint(x: 50, y: 0)),
                ],
                closed: false
            ),
        ]
        let flattened = flattenPath(MotionPathResolver.buildCGPath(contours: contours))

        // Two 180° arcs of radius 50 should flatten to ~2πr circumference.
        XCTAssertEqual(flattened.totalLength, 2 * Double.pi * 50, accuracy: 1.0)

        let atStart = flattened.position(atDistance: 0)
        XCTAssertEqual(Double(atStart.point.x), 50, accuracy: 0.5)
        XCTAssertEqual(Double(atStart.point.y), 0, accuracy: 0.5)

        // Halfway around the circumference should land opposite the start.
        let atHalf = flattened.position(atDistance: flattened.totalLength / 2)
        XCTAssertEqual(Double(atHalf.point.x), -50, accuracy: 1.0)
        XCTAssertEqual(Double(atHalf.point.y), 0, accuracy: 1.0)
    }

    func testMotionPathArcFixtureDecodesAndResolvesThroughSampleLayer() throws {
        let project = try XCTUnwrap(decodeFixtureJSON(motionPathArcFixtureJSON))
        let layer = try XCTUnwrap(project.layers.first)

        let atStart = sampleLayer(layer, atMs: 0)
        XCTAssertEqual(atStart.motionDx, 50, accuracy: 0.5)
        XCTAssertEqual(atStart.motionDy, 0, accuracy: 0.5)

        let atHalf = sampleLayer(layer, atMs: 1000)
        XCTAssertEqual(atHalf.motionDx, -50, accuracy: 1.0)
        XCTAssertEqual(atHalf.motionDy, 0, accuracy: 1.0)
    }
}

private func decodeFixtureJSON(_ json: String) -> V2Project? {
    try? JSONDecoder().decode(V2Project.self, from: Data(json.utf8))
}

private let fadeOutFixtureJSON = """
{
  "format": "motion-protocol", "formatVersion": 2, "id": "fade-out-test",
  "composition": { "width": 320, "height": 320, "fps": 30, "background": "#101820" },
  "assets": [],
  "layers": [{
    "id": "card",
    "order": 0,
    "type": "shape",
    "frame": { "width": 160, "height": 160 },
    "transform": {
      "translate": { "x": 0, "y": 0, "z": 0 }, "scale": { "x": 1, "y": 1, "z": 1 },
      "rotate": { "x": 0, "y": 0, "z": 0 }, "skew": { "x": 0, "y": 0 }, "anchor": { "x": 0, "y": 0, "z": 0 }
    },
    "opacity": 1,
    "timing": { "start": 0, "duration": 2000 },
    "payload": { "shape": "rectangle" },
    "style": { "fill": "#14B8A6" },
    "tracks": [{
      "id": "fade-out", "path": "opacity",
      "keyframes": [
        { "time": { "anchor": "end", "offsetMs": 300 }, "value": { "type": "number", "value": 1 } },
        { "time": { "anchor": "end", "offsetMs": 0 }, "value": { "type": "number", "value": 0 } }
      ]
    }]
  }],
  "audio": { "sampleRate": 48000, "tracks": [] }
}
"""

private let loopSpinFixtureJSON = """
{
  "format": "motion-protocol", "formatVersion": 2, "id": "loop-spin-test",
  "composition": { "width": 320, "height": 320, "fps": 30, "background": "#101820" },
  "assets": [],
  "layers": [{
    "id": "card",
    "order": 0,
    "type": "shape",
    "frame": { "width": 140, "height": 140 },
    "transform": {
      "translate": { "x": 0, "y": 0, "z": 0 }, "scale": { "x": 1, "y": 1, "z": 1 },
      "rotate": { "x": 0, "y": 0, "z": 0 }, "skew": { "x": 0, "y": 0 }, "anchor": { "x": 0, "y": 0, "z": 0 }
    },
    "opacity": 1,
    "timing": { "start": 0, "duration": 4000 },
    "payload": { "shape": "rectangle" },
    "style": { "fill": "#2563EB" },
    "tracks": [{
      "id": "spin", "path": "transform.rotate.z",
      "keyframes": [
        { "time": 0, "value": { "type": "number", "value": 0 } },
        { "time": 1000, "value": { "type": "number", "value": 360 } }
      ],
      "animation": {
        "durationMs": 1000, "delayMs": 0, "iterations": "infinite",
        "direction": "normal", "fillMode": "none", "playState": "running"
      }
    }]
  }],
  "audio": { "sampleRate": 48000, "tracks": [] }
}
"""

private let flip3DFixtureJSON = """
{
  "format": "motion-protocol", "formatVersion": 2, "id": "flip-3d-test",
  "composition": { "width": 320, "height": 320, "fps": 30, "background": "#101820" },
  "assets": [],
  "layers": [{
    "id": "card",
    "order": 0,
    "type": "shape",
    "frame": { "width": 160, "height": 220 },
    "transform": {
      "translate": { "x": 0, "y": 0, "z": 0 }, "scale": { "x": 1, "y": 1, "z": 1 },
      "rotate": { "x": 0, "y": -90, "z": 0 }, "skew": { "x": 0, "y": 0 }, "anchor": { "x": 0, "y": 0, "z": 0 },
      "perspective": 600
    },
    "opacity": 1,
    "timing": { "start": 0, "duration": 800 },
    "payload": { "shape": "rectangle" },
    "style": { "fill": "#F97316" },
    "tracks": [{
      "id": "flip-y", "path": "transform.rotate.y",
      "keyframes": [
        { "time": 0, "value": { "type": "number", "value": -90 } },
        { "time": 400, "value": { "type": "number", "value": 0 },
          "easing": { "type": "cubicBezier", "x1": 0.22, "y1": 1, "x2": 0.36, "y2": 1 } }
      ]
    }]
  }],
  "audio": { "sampleRate": 48000, "tracks": [] }
}
"""

private let transformCoverageFixtureJSON = """
{
  "format": "motion-protocol", "formatVersion": 2, "id": "transform-coverage-test",
  "composition": { "width": 320, "height": 320, "fps": 30, "background": "#101820" },
  "assets": [],
  "layers": [{
    "id": "card",
    "order": 0,
    "type": "shape",
    "frame": { "width": 160, "height": 160 },
    "transform": {
      "translate": { "x": 0, "y": 0, "z": 0 }, "scale": { "x": 1, "y": 1, "z": 1 },
      "rotate": { "x": 0, "y": 0, "z": 0 }, "skew": { "x": 10, "y": -5 },
      "anchor": { "x": 40, "y": -20, "z": 5 }
    },
    "opacity": 1,
    "timing": { "start": 0, "duration": 1000 },
    "payload": { "shape": "rectangle" },
    "style": { "fill": "#A855F7" },
    "tracks": [
      {
        "id": "width-grow", "path": "frame.width",
        "keyframes": [
          { "time": 0, "value": { "type": "number", "value": 160 } },
          { "time": 1000, "value": { "type": "number", "value": 260 } }
        ]
      },
      {
        "id": "depth-push", "path": "transform.translate.z",
        "keyframes": [
          { "time": 0, "value": { "type": "number", "value": 0 } },
          { "time": 1000, "value": { "type": "number", "value": 300 } }
        ]
      },
      {
        "id": "scale-z", "path": "transform.scale.z",
        "keyframes": [
          { "time": 0, "value": { "type": "number", "value": 1 } },
          { "time": 1000, "value": { "type": "number", "value": 2 } }
        ]
      }
    ]
  }],
  "audio": { "sampleRate": 48000, "tracks": [] }
}
"""

private let motionPathSquareFixtureJSON = """
{
  "format": "motion-protocol", "formatVersion": 2, "id": "motion-path-square-test",
  "composition": { "width": 320, "height": 320, "fps": 30, "background": "#101820" },
  "assets": [],
  "layers": [{
    "id": "card",
    "order": 0,
    "type": "shape",
    "frame": { "width": 40, "height": 40 },
    "transform": {
      "translate": { "x": 0, "y": 0, "z": 0 }, "scale": { "x": 1, "y": 1, "z": 1 },
      "rotate": { "x": 0, "y": 0, "z": 0 }, "skew": { "x": 0, "y": 0 }, "anchor": { "x": 0, "y": 0, "z": 0 }
    },
    "opacity": 1,
    "timing": { "start": 0, "duration": 1000 },
    "payload": { "shape": "rectangle" },
    "style": { "fill": "#F472B6" },
    "motion": {
      "offsetPath": {
        "type": "path",
        "contours": [{
          "id": "square", "start": { "x": 0, "y": 0 },
          "segments": [
            { "kind": "line", "to": { "x": 100, "y": 0 } },
            { "kind": "line", "to": { "x": 100, "y": 100 } },
            { "kind": "line", "to": { "x": 0, "y": 100 } }
          ],
          "closed": true
        }]
      },
      "offsetAnchor": { "x": 10, "y": 5 }
    },
    "tracks": [{
      "id": "travel", "path": "motion.offsetDistance",
      "keyframes": [
        { "time": 0, "value": { "type": "number", "value": 0 } },
        { "time": 1000, "value": { "type": "number", "value": 1 } }
      ]
    }]
  }],
  "audio": { "sampleRate": 48000, "tracks": [] }
}
"""

private let motionPathArcFixtureJSON = """
{
  "format": "motion-protocol", "formatVersion": 2, "id": "motion-path-arc-test",
  "composition": { "width": 320, "height": 320, "fps": 30, "background": "#101820" },
  "assets": [],
  "layers": [{
    "id": "card",
    "order": 0,
    "type": "shape",
    "frame": { "width": 20, "height": 20 },
    "transform": {
      "translate": { "x": 0, "y": 0, "z": 0 }, "scale": { "x": 1, "y": 1, "z": 1 },
      "rotate": { "x": 0, "y": 0, "z": 0 }, "skew": { "x": 0, "y": 0 }, "anchor": { "x": 0, "y": 0, "z": 0 }
    },
    "opacity": 1,
    "timing": { "start": 0, "duration": 1000 },
    "payload": { "shape": "circle" },
    "style": { "fill": "#22D3EE" },
    "motion": {
      "offsetPath": {
        "type": "path",
        "contours": [{
          "id": "circle", "start": { "x": 50, "y": 0 },
          "segments": [
            { "kind": "arc", "radii": { "x": 50, "y": 50 }, "rotation": 0, "largeArc": false, "sweep": true, "to": { "x": -50, "y": 0 } },
            { "kind": "arc", "radii": { "x": 50, "y": 50 }, "rotation": 0, "largeArc": false, "sweep": true, "to": { "x": 50, "y": 0 } }
          ],
          "closed": false
        }]
      }
    },
    "tracks": [{
      "id": "travel", "path": "motion.offsetDistance",
      "keyframes": [
        { "time": 0, "value": { "type": "number", "value": 0 } },
        { "time": 1000, "value": { "type": "number", "value": 0.5 } }
      ]
    }]
  }],
  "audio": { "sampleRate": 48000, "tracks": [] }
}
"""
