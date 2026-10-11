import XCTest
@testable import NeonixEditor

final class RulerMappingTests: XCTestCase {
    func testLinearRulerMapsTicksToValuesAndBack() {
        let rotation = RulerMapping.linear(-180...180, step: 1, majorEvery: 15)
        XCTAssertEqual(rotation.tickCount, 361)
        XCTAssertEqual(rotation.value(0), -180)
        XCTAssertEqual(rotation.value(180), 0)
        XCTAssertEqual(rotation.value(360), 180)
        XCTAssertEqual(rotation.index(0), 180)
        XCTAssertEqual(rotation.index(-45.4), 135, "values snap to the nearest tick")
        XCTAssertEqual(rotation.index(999), 360, "and are clamped into the ruler")
        XCTAssertEqual(rotation.index(-999), 0)
    }

    func testMajorTicksAreMultiplesSoZeroIsAlwaysOne() {
        let x = RulerMapping.linear(-1080...1080, step: 10, majorEvery: 10)
        XCTAssertTrue(x.isMajor(x.index(0)), "0 is a major tick even though the range starts at -1080")
        XCTAssertTrue(x.isMajor(x.index(100)))
        XCTAssertTrue(x.isMajor(x.index(-300)))
        XCTAssertFalse(x.isMajor(x.index(50)))
    }

    func testFractionalStepsDoNotDrift() {
        let opacity = RulerMapping.linear(0...1, step: 0.01, majorEvery: 10)
        XCTAssertEqual(opacity.tickCount, 101)
        XCTAssertEqual(opacity.value(30), 0.3, "0.3, not 0.30000000000000004")
        XCTAssertEqual(opacity.value(100), 1)
        XCTAssertTrue(opacity.isMajor(50))
        XCTAssertFalse(opacity.isMajor(55))
    }

    func testLogarithmicRulerPutsHalfAndDoubleAtEqualDistanceFromNeutral() {
        let scale = RulerMapping.logarithmic(0.25...4, ticksPerDoubling: 12)
        XCTAssertEqual(scale.tickCount, 49)
        let one = scale.index(1)
        XCTAssertEqual(one, 24, "100% is the middle tick")
        XCTAssertEqual(scale.value(one), 1, accuracy: 1e-9)
        XCTAssertEqual(scale.value(one + 12), 2, accuracy: 1e-9)
        XCTAssertEqual(scale.value(one - 12), 0.5, accuracy: 1e-9)
        XCTAssertEqual(scale.value(0), 0.25, accuracy: 1e-9)
        XCTAssertEqual(scale.value(48), 4, accuracy: 1e-9)
        XCTAssertTrue(scale.isMajor(0) && scale.isMajor(12) && scale.isMajor(24))
        XCTAssertFalse(scale.isMajor(13))
        XCTAssertEqual(scale.index(100), 48)
        XCTAssertEqual(scale.index(0.01), 0)
    }

    func testRoundTripThroughEveryParameter() {
        for param in LabParam.allCases {
            let mapping = param.mapping
            for index in stride(from: 0, to: mapping.tickCount, by: max(1, mapping.tickCount / 40)) {
                XCTAssertEqual(mapping.index(mapping.value(index)), index, "\(param) tick \(index)")
            }
            XCTAssertEqual(mapping.value(mapping.index(param.neutral)), param.neutral, accuracy: 1e-9, "\(param) neutral is a tick")
        }
    }

    func testLabFormatting() {
        XCTAssertEqual(LabParam.rotation.format(-12), "-12°")
        XCTAssertEqual(LabParam.rotation.format(0), "0°")
        XCTAssertEqual(LabParam.scale.format(1), "100%")
        XCTAssertEqual(LabParam.scale.format(1.5), "150%")
        XCTAssertEqual(LabParam.x.format(0), "0")
        XCTAssertEqual(LabParam.x.format(-120), "-120")
        XCTAssertEqual(LabParam.y.format(40), "+40")
        XCTAssertEqual(LabParam.opacity.format(0.5), "50%")
    }
}
