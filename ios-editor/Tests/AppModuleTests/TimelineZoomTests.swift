import XCTest
@testable import NeonixEditor

final class TimelineZoomTests: XCTestCase {
    private let fps = 30.0

    func testFarthestZoomOutPutsMinorTicksFiveSecondsApart() {
        let intervals = TimelineZoom.rulerIntervals(pxPerMs: TimelineZoom.minPxPerMs, fps: fps)
        XCTAssertEqual(intervals.minorMs, 5000)
        XCTAssertEqual(intervals.majorMs, 10_000)
    }

    func testClosestZoomInPutsMinorTicksOneFrameApart() {
        let intervals = TimelineZoom.rulerIntervals(pxPerMs: TimelineZoom.maxPxPerMs(fps: fps), fps: fps)
        XCTAssertEqual(intervals.minorMs, 1000 / fps, accuracy: 1e-9)
        XCTAssertEqual(intervals.majorMs, 2000 / fps, accuracy: 1e-9)
    }

    func testOneFrameIsAsWideAsTheMinimumTickSpacingAtFullZoomIn() {
        for rate in [24.0, 25, 30, 60] {
            let pxPerFrame = TimelineZoom.maxPxPerMs(fps: rate) * TimelineZoom.frameMs(fps: rate)
            XCTAssertEqual(pxPerFrame, TimelineZoom.minorSpacingPx, accuracy: 1e-9, "fps \(rate)")
            let intervals = TimelineZoom.rulerIntervals(pxPerMs: TimelineZoom.maxPxPerMs(fps: rate), fps: rate)
            XCTAssertEqual(intervals.minorMs, TimelineZoom.frameMs(fps: rate), accuracy: 1e-9, "fps \(rate)")
        }
    }

    func testDefaultScaleShowsATickEveryHalfSecondAndALabelEverySecond() {
        let intervals = TimelineZoom.rulerIntervals(pxPerMs: TimelineZoom.defaultPxPerMs, fps: fps)
        XCTAssertEqual(intervals.minorMs, 500)
        XCTAssertEqual(intervals.majorMs, 1000)
    }

    func testRulerTicksStayFarEnoughApartAtEveryScale() {
        let bounds = TimelineZoom.range(fps: fps)
        for scale in stride(from: bounds.lowerBound, through: bounds.upperBound, by: 0.005) {
            let intervals = TimelineZoom.rulerIntervals(pxPerMs: scale, fps: fps)
            XCTAssertGreaterThanOrEqual(intervals.minorMs * scale, TimelineZoom.minorSpacingPx - 1e-6, "minor at \(scale)")
            XCTAssertGreaterThanOrEqual(intervals.majorMs, intervals.minorMs * 2 - 1e-6, "major at \(scale)")
            let ratio = intervals.majorMs / intervals.minorMs
            XCTAssertEqual(ratio, ratio.rounded(), accuracy: 1e-6, "labels fall on ticks at \(scale)")
        }
    }

    func testZoomingInShrinksTheIntervalAndZoomingOutGrowsIt() {
        let zoomedIn = TimelineZoom.rulerIntervals(pxPerMs: 1.0, fps: fps)
        let normal = TimelineZoom.rulerIntervals(pxPerMs: 0.2, fps: fps)
        let zoomedOut = TimelineZoom.rulerIntervals(pxPerMs: 0.02, fps: fps)
        XCTAssertLessThan(zoomedIn.minorMs, normal.minorMs)
        XCTAssertGreaterThan(zoomedOut.minorMs, normal.minorMs)
    }

    func testLimitsAreTheFrameAndFiveSecondRulerSettings() {
        XCTAssertEqual(TimelineZoom.minPxPerMs, 0.0096, accuracy: 1e-12)
        XCTAssertEqual(TimelineZoom.maxPxPerMs(fps: 30), 1.44, accuracy: 1e-12)
        XCTAssertEqual(TimelineZoom.maxPxPerMs(fps: 60), 2.88, accuracy: 1e-12)
    }

    func testClampKeepsScaleInsideTheRange() {
        XCTAssertEqual(TimelineZoom.clamped(0.0001, fps: fps), TimelineZoom.minPxPerMs)
        XCTAssertEqual(TimelineZoom.clamped(50, fps: fps), TimelineZoom.maxPxPerMs(fps: fps))
        XCTAssertEqual(TimelineZoom.clamped(0.2, fps: fps), 0.2)
    }

    func testLabelsShowFramesOnceTheIntervalIsBelowOneSecond() {
        XCTAssertEqual(TimelineZoom.rulerLabel(ms: 62_000, majorMs: 2000, fps: fps), "01:02")
        XCTAssertEqual(TimelineZoom.rulerLabel(ms: 2500, majorMs: 500, fps: fps), "00:02:15")
        XCTAssertEqual(TimelineZoom.rulerLabel(ms: 2999.9, majorMs: 66.7, fps: fps), "00:02:29")
        XCTAssertEqual(TimelineZoom.rulerLabel(ms: 0, majorMs: 66.7, fps: fps), "00:00:00")
    }

    func testVisibleWindowCoversThePlayheadAndOnlyMovesAViewportAtATime() {
        // 400 pt viewport at 0.2 px/ms = 2000 ms per viewport.
        let window = TimelineZoom.visibleWindowMs(currentTimeMs: 5000, viewportWidth: 400, pxPerMs: 0.2)
        XCTAssertTrue(window.contains(5000))
        XCTAssertLessThanOrEqual(window.lowerBound, 5000 - 2000)
        XCTAssertGreaterThanOrEqual(window.upperBound, 5000 + 2000)
        XCTAssertEqual(TimelineZoom.visibleWindowMs(currentTimeMs: 5100, viewportWidth: 400, pxPerMs: 0.2), window)
        XCTAssertNotEqual(TimelineZoom.visibleWindowMs(currentTimeMs: 7600, viewportWidth: 400, pxPerMs: 0.2), window)
    }

    func testVisibleWindowStaysSmallEvenWhenTheTimelineIsHugeAtFullZoomIn() {
        let pxPerMs = TimelineZoom.maxPxPerMs(fps: fps)
        let window = TimelineZoom.visibleWindowMs(currentTimeMs: 15_000, viewportWidth: 402, pxPerMs: pxPerMs)
        let widthPx = (window.upperBound - window.lowerBound) * pxPerMs
        XCTAssertLessThanOrEqual(widthPx, 402 * 4 + 1)
        XCTAssertLessThan(widthPx, 31_200 * pxPerMs / 10)
    }

    // MARK: LaneScroll

    func testLaneScrollRangeIsContentMinusViewportNeverNegative() {
        XCTAssertEqual(LaneScroll.maxOffset(contentHeight: 200, viewportHeight: 80), 120)
        XCTAssertEqual(LaneScroll.maxOffset(contentHeight: 50, viewportHeight: 80), 0)
        XCTAssertEqual(LaneScroll.clamped(-30, maxOffset: 120), 0)
        XCTAssertEqual(LaneScroll.clamped(500, maxOffset: 120), 120)
        XCTAssertEqual(LaneScroll.clamped(40, maxOffset: 120), 40)
    }

    func testDragIsAlwaysAScrubWhenLanesCannotScroll() {
        XCTAssertEqual(LaneScroll.axis(forTranslation: CGSize(width: 0, height: 0), canScrollVertically: false), .horizontal)
        XCTAssertEqual(LaneScroll.axis(forTranslation: CGSize(width: 1, height: 30), canScrollVertically: false), .horizontal)
    }

    func testAxisIsLockedFromTheDominantDirectionOnceMovedFarEnough() {
        XCTAssertNil(LaneScroll.axis(forTranslation: CGSize(width: 1, height: 2), canScrollVertically: true))
        XCTAssertEqual(LaneScroll.axis(forTranslation: CGSize(width: 1, height: 6), canScrollVertically: true), .vertical)
        XCTAssertEqual(LaneScroll.axis(forTranslation: CGSize(width: -8, height: 3), canScrollVertically: true), .horizontal)
        XCTAssertEqual(LaneScroll.axis(forTranslation: CGSize(width: 5, height: -5), canScrollVertically: true), .horizontal)
    }
}
