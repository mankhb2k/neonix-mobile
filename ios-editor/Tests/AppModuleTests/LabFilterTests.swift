import XCTest
@testable import NeonixEditor

final class LabFilterTests: XCTestCase {
    func testCatalogueHasSixteenUniqueFiltersAndNoneComesFirst() {
        XCTAssertEqual(LabFilter.catalogue.count, 16)
        XCTAssertEqual(Set(LabFilter.catalogue.map(\.id)).count, 16)
        XCTAssertEqual(Set(LabFilter.catalogue.map(\.name)).count, 16)
        XCTAssertEqual(LabFilter.list(in: .all).first, LabFilter.none)
        XCTAssertEqual(LabFilter.list(in: .all).count, 17)
    }

    func testEveryCategoryHasFiltersAndTheListsPartitionTheCatalogue() {
        var total = 0
        for category in LabFilterCategory.allCases where category != .all {
            let list = LabFilter.list(in: category)
            XCTAssertEqual(list.first, LabFilter.none, "None leads every category")
            XCTAssertGreaterThan(list.count, 1, "\(category)")
            total += list.count - 1
        }
        XCTAssertEqual(total, LabFilter.catalogue.count)
    }

    func testIntensityZeroIsTheOriginalAndOneIsFull() {
        let warm = LabFilter.catalogue.first { $0.id == "warm" }!.values
        XCTAssertEqual(warm.scaled(0), LabFilterValues(tint: warm.tint), "nothing left at 0 (the tint colour has no opacity)")
        XCTAssertEqual(warm.scaled(1), warm)
        let half = warm.scaled(0.5)
        XCTAssertEqual(half.contrast, 1 + (warm.contrast - 1) / 2, accuracy: 1e-9)
        XCTAssertEqual(half.saturation, 1 + (warm.saturation - 1) / 2, accuracy: 1e-9)
        XCTAssertEqual(half.tintOpacity, warm.tintOpacity / 2, accuracy: 1e-9)
    }

    func testIntensityIsClamped() {
        let v = LabFilter.catalogue[0].values
        XCTAssertEqual(v.scaled(-1), v.scaled(0))
        XCTAssertEqual(v.scaled(7), v.scaled(1))
    }
}
