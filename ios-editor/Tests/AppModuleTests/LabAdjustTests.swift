import XCTest
@testable import NeonixEditor

final class LabAdjustTests: XCTestCase {
    func testThirteenControlsInThreeGroupsThatFitTheScreen() {
        XCTAssertEqual(LabAdjustParam.allCases.count, 13)
        let sizes = LabAdjustGroup.allCases.map { group in LabAdjustParam.allCases.filter { $0.group == group }.count }
        XCTAssertEqual(sizes, [4, 4, 5])
        XCTAssertTrue(sizes.allSatisfy { $0 <= 5 }, "each group's buttons fit in one fixed row")
    }

    func testEveryControlStartsAtNeutralOnItsRulerAndRoundTrips() {
        for param in LabAdjustParam.allCases {
            let mapping = param.mapping
            XCTAssertEqual(mapping.value(mapping.index(param.neutral)), param.neutral, accuracy: 1e-9, "\(param) neutral is a tick")
            for index in stride(from: 0, to: mapping.tickCount, by: max(1, mapping.tickCount / 30)) {
                XCTAssertEqual(mapping.index(mapping.value(index)), index, "\(param) tick \(index)")
            }
        }
    }

    func testValuesTrackWhichControlsWereChanged() {
        var values = LabAdjustValues()
        XCTAssertEqual(values[.contrast], 1, "contrast and saturation are neutral at 1, the rest at 0")
        XCTAssertEqual(values[.brightness], 0)
        XCTAssertFalse(LabAdjustParam.allCases.contains { values.isChanged($0) })

        values[.saturation] = 1.4
        values[.noise] = 0.2
        XCTAssertTrue(values.isChanged(.saturation))
        XCTAssertFalse(values.isChanged(.hue))
        XCTAssertEqual(values.changedCount(in: .color), 1)
        XCTAssertEqual(values.changedCount(in: .detail), 1)
        XCTAssertEqual(values.changedCount(in: .light), 0)

        values[.saturation] = 1
        XCTAssertFalse(values.isChanged(.saturation), "putting it back to neutral clears the mark")
    }

    func testReadoutsLikePhotos() {
        XCTAssertEqual(LabAdjustParam.brightness.display(0), "0")
        XCTAssertEqual(LabAdjustParam.brightness.display(0.1), "+20")
        XCTAssertEqual(LabAdjustParam.brightness.display(-0.25), "-50")
        XCTAssertEqual(LabAdjustParam.contrast.display(1), "0")
        XCTAssertEqual(LabAdjustParam.contrast.display(1.25), "+50")
        XCTAssertEqual(LabAdjustParam.saturation.display(0), "-100")
        XCTAssertEqual(LabAdjustParam.saturation.display(2), "+100")
        XCTAssertEqual(LabAdjustParam.exposure.display(-1.5), "-1.5")
        XCTAssertEqual(LabAdjustParam.hue.display(0), "0°")
        XCTAssertEqual(LabAdjustParam.hue.display(30), "+30°")
        XCTAssertEqual(LabAdjustParam.sharpen.display(0.4), "40")
        XCTAssertEqual(LabAdjustParam.blur.display(2.5), "2.5")
        XCTAssertEqual(LabAdjustParam.vignette.display(2), "100")
    }
}
