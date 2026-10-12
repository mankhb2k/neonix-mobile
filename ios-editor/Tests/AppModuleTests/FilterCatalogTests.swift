import XCTest
import CoreGraphics
@testable import NeonixEditor

/// The Filter tool: its presets are bundles of Adjust values, scaled by Intensity and compiled with the Adjust sliders.
final class FilterCatalogTests: XCTestCase {
    func testSixteenUniquePresetsInFourCategories() {
        XCTAssertEqual(FilterCatalog.presets.count, 16)
        XCTAssertEqual(Set(FilterCatalog.presets.map(\.id)).count, 16)
        XCTAssertEqual(Set(FilterCatalog.presets.map(\.name)).count, 16)
        XCTAssertEqual(FilterCatalog.list(in: .all).count, 16)
        var total = 0
        for category in FilterCategory.allCases where category != .all {
            let list = FilterCatalog.list(in: category)
            XCTAssertFalse(list.isEmpty, "\(category)")
            total += list.count
        }
        XCTAssertEqual(total, 16)
        XCTAssertEqual(FilterCatalog.preset(id: "mono")?.name, "Mono")
        XCTAssertNil(FilterCatalog.preset(id: "nope"))
    }

    func testEveryPresetChangesSomethingAndIsAWellFormedLook() {
        for preset in FilterCatalog.presets {
            XCTAssertNotEqual(preset.values, AdjustValues(), "\(preset.id) must not be a no-op")
            XCTAssertFalse(adjustPresets(for: preset.values).isEmpty, preset.id)
        }
    }

    func testScalingMovesEveryNumberLinearlyFromNeutral() {
        let film = FilterCatalog.preset(id: "film400")!.values
        XCTAssertEqual(film.scaled(0), AdjustValues())
        XCTAssertEqual(film.scaled(1), film)
        let half = film.scaled(0.5)
        XCTAssertEqual(half.contrast, 1 + (film.contrast - 1) / 2, accuracy: 1e-9)
        XCTAssertEqual(half.saturation, 1 + (film.saturation - 1) / 2, accuracy: 1e-9)
        XCTAssertEqual(half.vignette, film.vignette / 2, accuracy: 1e-9)
        XCTAssertEqual(half.blackPoint, film.blackPoint / 2, accuracy: 1e-9)
        XCTAssertEqual(film.scaled(7), film.scaled(1), "clamped")
        var curved = AdjustValues(); curved.curvePoints = [0, 0.3, 0.5, 0.6, 1]
        XCTAssertEqual(curved.scaled(0.5).curvePoints, [0, 0.275, 0.5, 0.675, 1], "the curve moves toward the identity too")
    }

    // MARK: compilation with the Adjust sliders

    private func project() -> V2Project {
        V2Project(composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"), assets: [], layers: [
            V2Layer(id: "clip1", order: 0, frame: V2Frame(width: 360, height: 640), transform: .identity,
                    timing: V2Timing(start: 0, duration: 1000), payload: .video(V2VideoPayload(assetId: "a")))
        ])
    }

    private func primitiveCount(_ filter: AppliedFilter?, _ adjust: AdjustValues = AdjustValues()) -> Int {
        SetAdjustCommand(layerId: "clip1", values: adjust, filter: filter).apply(to: project()).filters?.first?.primitives.count ?? 0
    }

    func testAFilterAloneBuildsTheChainAndNoneClearsIt() {
        let picked = SetAdjustCommand(layerId: "clip1", values: AdjustValues(), filter: AppliedFilter(id: "mono")).apply(to: project())
        XCTAssertEqual(picked.layers.first?.filter, "adjust-clip1")
        XCTAssertGreaterThan(picked.filters?.first?.primitives.count ?? 0, 0)

        let cleared = SetAdjustCommand(layerId: "clip1", values: AdjustValues(), filter: nil).apply(to: picked)
        XCTAssertNil(cleared.layers.first?.filter)
        XCTAssertNil(cleared.filters)
    }

    func testIntensityZeroOrAnUnknownFilterLeavesNothing() {
        XCTAssertEqual(primitiveCount(AppliedFilter(id: "mono", intensity: 0)), 0)
        XCTAssertEqual(primitiveCount(AppliedFilter(id: "does-not-exist")), 0)
    }

    func testTheSlidersStackOnTopOfTheFilter() {
        var sliders = AdjustValues(); sliders.vignette = 0.5
        let filterOnly = primitiveCount(AppliedFilter(id: "mono"))
        let slidersOnly = primitiveCount(nil, sliders)
        XCTAssertEqual(primitiveCount(AppliedFilter(id: "mono"), sliders), filterOnly + slidersOnly, "both chains in the one filter")
        XCTAssertEqual(SetAdjustCommand(layerId: "clip1", values: sliders, filter: AppliedFilter(id: "mono")).apply(to: project()).filters?.count, 1)
    }

    // MARK: rendering

    private func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGImage {
        let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: r, green: g, blue: b, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        return context.makeImage()!
    }

    private func pixel(_ image: CGImage) -> (r: Int, g: Int, b: Int) {
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (Int(data[0]), Int(data[1]), Int(data[2]))
    }

    private func render(_ id: String, intensity: Double = 1, _ source: CGImage) -> (r: Int, g: Int, b: Int) {
        let filter = SetAdjustCommand(layerId: "clip1", values: AdjustValues(), filter: AppliedFilter(id: id, intensity: intensity))
            .apply(to: project()).filters!.first!
        return pixel(FilterRenderer.apply(filter, to: source)!)
    }

    func testMonoMakesAColourGreyAndWarmCoolShiftTheBalance() {
        let orange = solid(0.8, 0.5, 0.2)
        let mono = render("mono", orange)
        XCTAssertEqual(mono.r, mono.g, accuracy: 3)
        XCTAssertEqual(mono.g, mono.b, accuracy: 3)

        let grey = solid(0.5, 0.5, 0.5)
        let warm = render("warm", grey), cool = render("cool", grey)
        XCTAssertGreaterThan(warm.r - warm.b, 10, "warm pushes red over blue")
        XCTAssertGreaterThan(cool.b - cool.r, 10, "cool pushes blue over red")
    }

    func testVividSpreadsColoursAndIntensityScalesTheEffect() {
        let muted = solid(0.6, 0.5, 0.5)
        let before = pixel(muted)
        let full = render("vivid", muted), half = render("vivid", intensity: 0.5, muted)
        let spread = { (p: (r: Int, g: Int, b: Int)) in p.r - p.g }
        XCTAssertGreaterThan(spread(full), spread(before))
        XCTAssertGreaterThan(spread(half), spread(before))
        XCTAssertLessThan(spread(half), spread(full), "half strength sits between the original and full")
    }
}
