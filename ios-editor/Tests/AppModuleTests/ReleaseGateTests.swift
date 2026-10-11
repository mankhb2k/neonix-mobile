import XCTest
@testable import NeonixEditor

/// Rows are from the real iPhone 13 release log (finger px/s, hold ms).
final class ReleaseGateTests: XCTestCase {
    func testSlowAndHeldReleasesDoNotGlide() {
        for (v, hold) in [(5.0, 626.0), (32, 409), (-3, 859), (-12, 48), (85, 8), (-65, 8), (-31, 32)] {
            XCTAssertFalse(ReleaseGate.shouldCoast(fingerPxPerSecond: v, holdSeconds: hold / 1000), "\(v) pt/s, \(hold) ms")
        }
    }

    func testRealFlicksGlideInBothDirections() {
        for (v, hold) in [(427.0, 16.0), (-742, 8), (734, 8), (-1517, 8), (-924, 8)] {
            XCTAssertTrue(ReleaseGate.shouldCoast(fingerPxPerSecond: v, holdSeconds: hold / 1000), "\(v) pt/s, \(hold) ms")
        }
    }

    func testAFastFingerThatSatStillBeforeLiftingDoesNotGlide() {
        XCTAssertFalse(ReleaseGate.shouldCoast(fingerPxPerSecond: 900, holdSeconds: 0.25))
    }

    func testUnknownHoldFallsBackToSpeedAlone() {
        XCTAssertTrue(ReleaseGate.shouldCoast(fingerPxPerSecond: 500, holdSeconds: nil))
        XCTAssertFalse(ReleaseGate.shouldCoast(fingerPxPerSecond: 60, holdSeconds: nil))
    }
}
