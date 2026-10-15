import XCTest
@testable import NeonixEditor

/// Speed, Curve: the curve's maths (smooth, no overshoot, both directions of the time map), cutting it, and what the commands do with it.
final class SpeedCurveTests: XCTestCase {
    private func pts(_ list: [(Double, Double)]) -> [V2SpeedPoint] { list.map { V2SpeedPoint(sourceMs: $0.0, rate: $0.1) } }
    private let wavy: [(Double, Double)] = [(0, 1), (1000, 4), (2000, 0.5), (4000, 1)]

    func testAConstantCurveIsJustARate() throws {
        let curve = try XCTUnwrap(SpeedCurve.constant(rate: 2, span: 4000))
        XCTAssertEqual(curve.outputDuration, 2000, accuracy: 0.5)
        XCTAssertEqual(curve.sourceMs(atOutput: 500), 1000, accuracy: 0.5)
        XCTAssertEqual(curve.outputMs(atSource: 3000), 1500, accuracy: 0.5)
        XCTAssertEqual(curve.rate(atSource: 1234), 2, accuracy: 1e-9)
    }

    func testTheCurvePassesThroughItsPointsAndNeverOvershoots() throws {
        let curve = try XCTUnwrap(SpeedCurve(points: pts(wavy), span: 4000))
        for p in curve.points { XCTAssertEqual(curve.rate(atSource: p.sourceMs), p.rate, accuracy: 1e-9, "at \(p.sourceMs)") }
        for i in 0...400 {
            let r = curve.rate(atSource: Double(i) * 10)
            XCTAssertGreaterThanOrEqual(r, 0.5 - 1e-9); XCTAssertLessThanOrEqual(r, 4 + 1e-9)
        }
        // Smooth: no jump between neighbouring samples.
        var last = curve.rate(atSource: 0)
        for i in 1...4000 { let r = curve.rate(atSource: Double(i)); XCTAssertLessThan(abs(r - last), 0.05, "at \(i)"); last = r }
    }

    func testBothDirectionsOfTheTimeMapAgree() throws {
        let curve = try XCTUnwrap(SpeedCurve(points: pts(wavy), span: 4000))
        for x in stride(from: 0.0, through: 4000, by: 137) {
            XCTAssertEqual(curve.sourceMs(atOutput: curve.outputMs(atSource: x)), x, accuracy: 0.6, "x = \(x)")
        }
        XCTAssertEqual(curve.outputMs(atSource: 0), 0); XCTAssertEqual(curve.outputMs(atSource: 4000), curve.outputDuration, accuracy: 1e-9)
        XCTAssertEqual(curve.sourceMs(atOutput: -5), 0); XCTAssertEqual(curve.sourceMs(atOutput: 1e9), 4000, accuracy: 1e-6)
        var last = -1.0
        for i in 0...200 { let t = curve.outputDuration * Double(i) / 200; let x = curve.sourceMs(atOutput: t); XCTAssertGreaterThanOrEqual(x, last); last = x }
    }

    func testFasterStretchesTakeLessTime() throws {
        let fastMiddle = try XCTUnwrap(SpeedCurve(points: pts([(0, 1), (2000, 8), (4000, 1)]), span: 4000))
        let slowMiddle = try XCTUnwrap(SpeedCurve(points: pts([(0, 1), (2000, 0.25), (4000, 1)]), span: 4000))
        XCTAssertLessThan(fastMiddle.outputDuration, 4000)
        XCTAssertGreaterThan(slowMiddle.outputDuration, 4000)
        XCTAssertNil(SpeedCurve(points: pts([(0, 1)]), span: 4000), "a curve needs two points")
        let clamped = try XCTUnwrap(SpeedCurve(points: pts([(0, 100), (4000, 0.001)]), span: 4000))
        XCTAssertEqual(clamped.points[0].rate, 9); XCTAssertEqual(clamped.points[1].rate, 0.1, "kept inside 0.1x ... 9x")
    }

    func testSplittingKeepsTheShapeAndTheTime() throws {
        let curve = try XCTUnwrap(SpeedCurve(points: pts(wavy), span: 4000))
        let cut = 1500.0
        let (a, b) = try XCTUnwrap(curve.splitting(atSource: cut))
        XCTAssertEqual(a.span, 1500); XCTAssertEqual(b.span, 2500)
        XCTAssertEqual(a.outputDuration + b.outputDuration, curve.outputDuration, accuracy: 1.0, "the two halves take as long as the whole")
        XCTAssertEqual(b.rate(atSource: 0), curve.rate(atSource: cut), accuracy: 1e-6, "the second half starts at the speed where the first ended")
        XCTAssertEqual(a.rate(atSource: cut), curve.rate(atSource: cut), accuracy: 1e-6)
        XCTAssertEqual(b.rate(atSource: 1000), curve.rate(atSource: 2500), accuracy: 0.05, "and follows the same shape")
        XCTAssertNil(curve.splitting(atSource: 0)); XCTAssertNil(curve.splitting(atSource: 4000))
    }

    func testTrimmingARemovesOrExtendsAtTheEdges() throws {
        let curve = try XCTUnwrap(SpeedCurve(points: pts(wavy), span: 4000))
        let head = try XCTUnwrap(curve.trimmed(headSource: 500, tailSource: 0))
        XCTAssertEqual(head.span, 3500); XCTAssertEqual(head.rate(atSource: 0), curve.rate(atSource: 500), accuracy: 1e-6)
        let tail = try XCTUnwrap(curve.trimmed(headSource: 0, tailSource: -1000))
        XCTAssertEqual(tail.span, 3000); XCTAssertEqual(tail.rate(atSource: 3000), curve.rate(atSource: 3000), accuracy: 1e-6)
        let longer = try XCTUnwrap(curve.trimmed(headSource: -300, tailSource: 700))
        XCTAssertEqual(longer.span, 5000)
        XCTAssertEqual(longer.rate(atSource: 100), 1, accuracy: 1e-6, "extended at the first speed")
        XCTAssertEqual(longer.rate(atSource: 4900), 1, accuracy: 1e-6, "and at the last")
        XCTAssertNil(curve.trimmed(headSource: 4000, tailSource: 0))
    }

    // MARK: Commands

    private func video(_ id: String, start: Double, duration: Double, trimStart: Double = 0) -> V2Layer {
        V2Layer(id: id, order: 0, frame: V2Frame(width: 360, height: 640), transform: .identity, timing: V2Timing(start: start, duration: duration),
                payload: .video(V2VideoPayload(assetId: "asset", trimStart: trimStart)))
    }

    private func lane() -> V2Project {
        V2Project(composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"), assets: [], layers: [
            video("A", start: 0, duration: 4000, trimStart: 1000), video("B", start: 4000, duration: 2000),
        ])
    }

    private func layer(_ p: V2Project, _ id: String) -> V2Layer { p.layers.first { $0.id == id }! }
    private func curve(_ l: V2Layer) -> [V2SpeedPoint]? { if case .video(let p) = l.payload { return p.speedCurve } else { return nil } }

    func testTheCurveSetsTheClipsLengthAndMovesTheLane() throws {
        let p = SetClipSpeedCurveCommand(layerId: "A", points: pts([(0, 1), (2000, 4), (4000, 1)])).apply(to: lane())
        let a = layer(p, "A")
        let c = try XCTUnwrap(SpeedCurve(points: try XCTUnwrap(curve(a)), span: 4000))
        XCTAssertEqual(a.timing.duration, c.outputDuration, accuracy: 1e-6)
        XCTAssertLessThan(a.timing.duration, 4000)
        XCTAssertEqual(layer(p, "B").timing.start, a.timing.duration, accuracy: 1e-6, "the lane follows")
        guard case .video(let payload) = a.payload else { return XCTFail() }
        XCTAssertEqual(payload.trimStart, 1000, "the footage is the same"); XCTAssertNil(payload.playbackRate)
        // The mapping runs through the curve: the clip's last frame is the footage's last frame.
        let mapping = try XCTUnwrap(VideoTimeMapping(layer: a))
        XCTAssertEqual(mapping.sourceMs(atTimelineMs: a.timing.start + a.timing.duration), 5000, accuracy: 0.6, "1000 + 4000")
        XCTAssertEqual(mapping.timelineMs(atSourceMs: 3000), a.timing.start + c.outputMs(atSource: 2000), accuracy: 1e-6)
        XCTAssertEqual(mapping.rate(atTimelineMs: a.timing.start), 1, accuracy: 1e-6)
    }

    func testRemovingTheCurveOrFlatteningItRestoresTheOriginalLength() {
        let p = SetClipSpeedCurveCommand(layerId: "A", points: pts([(0, 1), (2000, 4), (4000, 1)])).apply(to: lane())
        let back = SetClipSpeedCurveCommand(layerId: "A", points: nil).apply(to: p)
        XCTAssertEqual(layer(back, "A").timing.duration, 4000, accuracy: 1e-6); XCTAssertNil(curve(layer(back, "A")))
        XCTAssertEqual(layer(back, "B").timing.start, 4000, accuracy: 1e-6)
        let flat = SetClipSpeedCurveCommand(layerId: "A", points: pts([(0, 1), (1000, 1), (4000, 1)])).apply(to: p)
        XCTAssertNil(curve(layer(flat, "A")), "a curve that is 1x everywhere is no curve")
        XCTAssertEqual(layer(flat, "A").timing.duration, 4000, accuracy: 1e-6)
        // The Normal ruler replaces a curve with a constant speed over the same footage.
        let normal = SetClipSpeedCommand(layerId: "A", rate: 2).apply(to: p)
        XCTAssertNil(curve(layer(normal, "A"))); XCTAssertEqual(layer(normal, "A").timing.duration, 2000, accuracy: 1e-6)
    }

    func testSplittingACurvedClipKeepsTheFootageContinuous() throws {
        let p = SetClipSpeedCurveCommand(layerId: "A", points: pts(wavy)).apply(to: lane())
        let a = layer(p, "A")
        let cutAt = a.timing.start + a.timing.duration * 0.4
        let split = SplitClipCommand(layerId: "A", atMs: cutAt).apply(to: p)
        let first = split.layers[0], second = split.layers[1]
        XCTAssertEqual(first.timing.duration + second.timing.duration, a.timing.duration, accuracy: 1e-6)
        XCTAssertEqual(second.timing.start, cutAt, accuracy: 1e-6)
        let m1 = try XCTUnwrap(VideoTimeMapping(layer: first)), m2 = try XCTUnwrap(VideoTimeMapping(layer: second))
        let endOfFirst = m1.sourceMs(atTimelineMs: first.timing.start + first.timing.duration)
        XCTAssertEqual(endOfFirst, m2.sourceMs(atTimelineMs: second.timing.start), accuracy: 1.0, "the second half picks up where the first stops")
        XCTAssertEqual(m1.rate(atTimelineMs: first.timing.start + first.timing.duration), m2.rate(atTimelineMs: second.timing.start), accuracy: 0.02, "at the same speed")
        XCTAssertEqual(m2.sourceMs(atTimelineMs: second.timing.start + second.timing.duration), 5000, accuracy: 1.0, "the last frame is still the footage's last")
    }

    func testTrimmingACurvedClip() throws {
        let p = SetClipSpeedCurveCommand(layerId: "A", points: pts(wavy)).apply(to: lane())
        let a = layer(p, "A")
        let oldMapping = try XCTUnwrap(VideoTimeMapping(layer: a))
        // Left handle: the head moves 300 ms later, the end stays.
        let headStart = a.timing.start + 300
        let trimmed = TrimClipCommand(layerId: "A", start: headStart, duration: a.timing.duration - 300, trimStart: 0, trimEnd: nil).apply(to: p)
        let t = layer(trimmed, "A")
        let newMapping = try XCTUnwrap(VideoTimeMapping(layer: t))
        XCTAssertEqual(newMapping.sourceMs(atTimelineMs: headStart), oldMapping.sourceMs(atTimelineMs: headStart), accuracy: 0.6, "the picture at the new first frame is the one that was there")
        XCTAssertEqual(newMapping.sourceMs(atTimelineMs: t.timing.start + t.timing.duration), 5000, accuracy: 0.6, "the end did not move")
        // Right handle: 500 ms shorter.
        let shorter = TrimClipCommand(layerId: "A", start: a.timing.start, duration: a.timing.duration - 500, trimStart: 0, trimEnd: nil).apply(to: p)
        let s = layer(shorter, "A")
        let m = try XCTUnwrap(VideoTimeMapping(layer: s))
        XCTAssertEqual(m.sourceMs(atTimelineMs: s.timing.start + s.timing.duration), oldMapping.sourceMs(atTimelineMs: a.timing.start + a.timing.duration - 500), accuracy: 0.6)
    }

    func testTheCurveIsFailClosedForOtherLayers() {
        let text = AddTextLayerCommand(layerId: "T", text: "Hi", atMs: 0).apply(to: lane())
        XCTAssertEqual(SetClipSpeedCurveCommand(layerId: "T", points: pts(wavy)).apply(to: text).layers.map(\.timing.duration), text.layers.map(\.timing.duration))
        XCTAssertEqual(SetClipSpeedCurveCommand(layerId: "missing", points: pts(wavy)).apply(to: lane()).layers.map(\.timing.duration), lane().layers.map(\.timing.duration))
    }
}
