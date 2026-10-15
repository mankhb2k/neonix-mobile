import XCTest
@testable import NeonixEditor

final class SpeedScaleTests: XCTestCase {
    func testTheRangeIsPointOneToNine() {
        XCTAssertEqual(SpeedScale.minimum, 0.1)
        XCTAssertEqual(SpeedScale.maximum, 9)
        XCTAssertEqual(SpeedScale.clamped(10), 9, "10x is where the system drops to key frames only (iPhone 13, 1080p60 HEVC)")
        XCTAssertEqual(SpeedScale.clamped(0.01), 0.1)
    }

    func testNotchesLabelsAndDuration() {
        XCTAssertEqual(SpeedScale.snapped(1.04), 1.0)
        XCTAssertEqual(SpeedScale.snapped(1.06), 1.1, accuracy: 1e-9)
        XCTAssertEqual(SpeedScale.snapped(99), 9)
        XCTAssertEqual(SpeedScale.label(1), "1x"); XCTAssertEqual(SpeedScale.label(0.5), "0.5x"); XCTAssertEqual(SpeedScale.label(2.5), "2.5x")
        XCTAssertEqual(SpeedScale.duration(sourceMs: 3900, rate: 1.2, fps: 30), 3250, accuracy: 0.5, "the CapCut example: 3.9 s at 1.2x is 3.2 s")
        XCTAssertEqual(SpeedScale.duration(sourceMs: 10, rate: 9, fps: 30), 1000 / 30, accuracy: 1e-9, "never shorter than one frame")
    }
}
