import XCTest
@testable import AppModule

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
