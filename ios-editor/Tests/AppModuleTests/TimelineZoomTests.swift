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

    func testDefaultScaleIsHalfASecondPer48Points() {
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

    func testDotsStayCloseTogetherAndEveryLabelHasExactlyOneDotBetween() {
        for rate in [24.0, 30, 60] {
            let bounds = TimelineZoom.range(fps: rate)
            for scale in stride(from: bounds.lowerBound, through: bounds.upperBound, by: 0.003) {
                let intervals = TimelineZoom.rulerIntervals(pxPerMs: scale, fps: rate)
                // Up to ~120 pt only between 2 s and 5 s.
                XCTAssertLessThanOrEqual(intervals.minorMs * scale, 121, "dots too far apart at \(scale), fps \(rate)")
                XCTAssertEqual(intervals.majorMs, intervals.minorMs * 2, accuracy: 1e-9, "one dot between labels at \(scale), fps \(rate)")
            }
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
        XCTAssertEqual(TimelineZoom.rulerLabel(ms: 2500, majorMs: 500, fps: fps), "15f")
        XCTAssertEqual(TimelineZoom.rulerLabel(ms: 2966.7, majorMs: 66.7, fps: fps), "29f")
        // 2999.9 ms is frame 90: the next whole second, not "30f".
        XCTAssertEqual(TimelineZoom.rulerLabel(ms: 2999.9, majorMs: 66.7, fps: fps), "00:03")
        XCTAssertEqual(TimelineZoom.rulerLabel(ms: 0, majorMs: 66.7, fps: fps), "00:00")
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

    func testLaneScrollRangeIsTheOverflowAndZeroWhenItFits() {
        XCTAssertEqual(LaneScroll.maxOffset(contentHeight: 200, viewportHeight: 80), 120)
        XCTAssertEqual(LaneScroll.maxOffset(contentHeight: 50, viewportHeight: 80), 0)
        XCTAssertEqual(LaneScroll.maxOffset(contentHeight: 80, viewportHeight: 80), 0, "nothing scrolls when everything fits")
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

final class FilmstripGridTests: XCTestCase {
    func testBaseStepIsOneSecondUntilTheThumbnailCap() {
        XCTAssertEqual(FilmstripGrid.baseStepMs(durationMs: 95_000), 1000)
        XCTAssertEqual(FilmstripGrid.baseStepMs(durationMs: 240_000), 1000)
        // 10 minutes would be 600 thumbnails: the step doubles to stay under 240.
        XCTAssertEqual(FilmstripGrid.baseStepMs(durationMs: 600_000), 3000)
    }

    func testDetailStepIsTheCoarsestHalvingThatGivesEveryTileItsOwnFrame() {
        XCTAssertNil(FilmstripGrid.detailStepMs(baseStepMs: 1000, tileSourceMs: 1000), "base already as fine as a tile")
        XCTAssertNil(FilmstripGrid.detailStepMs(baseStepMs: 1000, tileSourceMs: 5000))
        XCTAssertEqual(FilmstripGrid.detailStepMs(baseStepMs: 1000, tileSourceMs: 240), 125)
        XCTAssertEqual(FilmstripGrid.detailStepMs(baseStepMs: 1000, tileSourceMs: 33), 31.25)
        XCTAssertEqual(FilmstripGrid.detailStepMs(baseStepMs: 1000, tileSourceMs: 5), 31.25, "never finer than 5 halvings")
    }

    func testTilesAreAnchoredToSourceTimeNotToTheClipEdge() {
        // A clip trimmed 100 pt in: its left edge shows part of tile 2 (100/48), not tile 0.
        XCTAssertEqual(FilmstripGrid.tiles(lower: 0, upper: 96, trimStartPx: 100, tileWidth: 48), 2...4)
        // Untrimmed: starts at tile 0.
        XCTAssertEqual(FilmstripGrid.tiles(lower: 0, upper: 96, trimStartPx: 0, tileWidth: 48), 0...1)
        // Trimming the right edge changes only how far the range reaches, never which tile is where.
        XCTAssertEqual(FilmstripGrid.tiles(lower: 0, upper: 200, trimStartPx: 100, tileWidth: 48), 2...6)
        XCTAssertNil(FilmstripGrid.tiles(lower: 10, upper: 10, trimStartPx: 0, tileWidth: 48))
    }
}

final class RulerLabelTests: XCTestCase {
    func testWholeSecondsReadAsMinutesAndSeconds() {
        XCTAssertEqual(TimelineZoom.rulerLabel(ms: 0, majorMs: 2000, fps: 30), "00:00")
        XCTAssertEqual(TimelineZoom.rulerLabel(ms: 2000, majorMs: 2000, fps: 30), "00:02")
        XCTAssertEqual(TimelineZoom.rulerLabel(ms: 65_000, majorMs: 5000, fps: 30), "01:05")
    }

    func testSubSecondLabelsAreTheFrameWithinTheSecond() {
        let frame = 1000.0 / 30
        XCTAssertEqual(TimelineZoom.rulerLabel(ms: 2 * frame, majorMs: 2 * frame, fps: 30), "2f")
        XCTAssertEqual(TimelineZoom.rulerLabel(ms: 1000 + 4 * frame, majorMs: 2 * frame, fps: 30), "4f")
        XCTAssertEqual(TimelineZoom.rulerLabel(ms: 1500, majorMs: 500, fps: 30), "15f")
        // The second boundary itself is a whole-second label even at frame zoom.
        XCTAssertEqual(TimelineZoom.rulerLabel(ms: 1000, majorMs: 2 * frame, fps: 30), "00:01")
    }
}
