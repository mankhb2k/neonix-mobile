import XCTest
@testable import NeonixEditor

final class TrimAutoScrollTests: XCTestCase {
    private let width = 402.0

    func testFingerAwayFromTheEdgesDoesNotScroll() {
        XCTAssertEqual(TrimAutoScrollTuning.targetSpeed(fingerX: 201, panelWidth: width), 0)
        XCTAssertEqual(TrimAutoScrollTuning.targetSpeed(fingerX: 100, panelWidth: width), 0)
        XCTAssertEqual(TrimAutoScrollTuning.targetSpeed(fingerX: width - 100, panelWidth: width), 0)
    }

    func testSlowLevelBetweenTheOuterAndInnerZone() {
        XCTAssertEqual(TrimAutoScrollTuning.targetSpeed(fingerX: width - 40, panelWidth: width), TrimAutoScrollTuning.slowSpeed)
        XCTAssertEqual(TrimAutoScrollTuning.targetSpeed(fingerX: 40, panelWidth: width), -TrimAutoScrollTuning.slowSpeed)
        XCTAssertEqual(TrimAutoScrollTuning.targetSpeed(fingerX: width - TrimAutoScrollTuning.slowZone, panelWidth: width), TrimAutoScrollTuning.slowSpeed)
    }

    func testFastLevelRightAtTheEdge() {
        XCTAssertEqual(TrimAutoScrollTuning.targetSpeed(fingerX: width - 10, panelWidth: width), TrimAutoScrollTuning.fastSpeed)
        XCTAssertEqual(TrimAutoScrollTuning.targetSpeed(fingerX: 10, panelWidth: width), -TrimAutoScrollTuning.fastSpeed)
        XCTAssertEqual(TrimAutoScrollTuning.targetSpeed(fingerX: width, panelWidth: width), TrimAutoScrollTuning.fastSpeed)
    }

    func testFastIsFasterThanSlowAndAnUnknownWidthDoesNothing() {
        XCTAssertGreaterThan(TrimAutoScrollTuning.fastSpeed, TrimAutoScrollTuning.slowSpeed)
        XCTAssertEqual(TrimAutoScrollTuning.targetSpeed(fingerX: 5, panelWidth: 0), 0)
    }
}
