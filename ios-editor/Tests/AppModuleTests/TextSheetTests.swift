import XCTest
import UIKit
@testable import NeonixEditor

final class TextSheetTests: XCTestCase {
    func testStyleBadgesFollowTheUsersOrderAndHaveSymbols() {
        XCTAssertEqual(TextSheet.StyleSection.allCases.map(\.rawValue),
                       ["Text", "Colors", "Stroke", "Glow", "Background", "Shadow", "Curve", "Spacing", "Case"])
        for section in TextSheet.StyleSection.allCases {
            XCTAssertNotNil(UIImage(systemName: section.symbol), "\(section): \(section.symbol)")
        }
    }

    func testAPresetSetsOnlyTheColourAndTheLabel() {
        var values = TextStyleValues()
        values.fontFamily = "Georgia-Bold"; values.fontSize = 50; values.align = "left"
        let preset = TextPreset.all.first { $0.id == "black-on-yellow" }!
        XCTAssertFalse(preset.matches(values))
        preset.apply(to: &values)
        XCTAssertTrue(preset.matches(values))
        XCTAssertEqual(values.color, "#000000ff")
        XCTAssertEqual(values.backgroundColor, "#FFD60Aff")
        XCTAssertEqual(values.fontFamily, "Georgia-Bold"); XCTAssertEqual(values.fontSize, 50); XCTAssertEqual(values.align, "left")
        TextPreset.plain.apply(to: &values)
        XCTAssertNil(values.backgroundColor, "the first tile removes the label")
        XCTAssertTrue(TextPreset.plain.textIsLight)
        XCTAssertFalse(TextPreset.all.first { $0.id == "black" }!.textIsLight)
    }

    func testNoTwoPresetsShareALook() {
        let looks = TextPreset.all.map { "\($0.color)|\($0.background ?? "-")" }
        XCTAssertEqual(Set(looks).count, looks.count)
        XCTAssertEqual(Set(TextPreset.all.map(\.id)).count, TextPreset.all.count)
    }

    func testThePaletteHasFortyDistinctColours() {
        XCTAssertEqual(ColorPalette.colors.count, 40)
        XCTAssertEqual(Set(ColorPalette.colors).count, 40)
        XCTAssertTrue(ColorPalette.colors.allSatisfy { $0.count == 9 && $0.hasPrefix("#") && $0.hasSuffix("ff") })
        for hex in ["#FFFFFFff", "#000000ff", "#FF1414ff"] { XCTAssertTrue(ColorPalette.colors.contains(hex), hex) }
    }

    func testHexAndHSBRoundTrip() {
        for hex in ["#FF1414ff", "#33CCFFff", "#FFD60Aff"] {
            let c = ColorPalette.hsb(of: hex)
            let back = ColorPalette.hex(hue: c.hue, saturation: c.saturation, brightness: c.brightness)
            XCTAssertEqual(back, hex)
        }
        let grey = ColorPalette.hsb(of: "#808080ff", keepingHue: 0.4)
        XCTAssertEqual(grey.hue, 0.4, accuracy: 1e-9, "a grey has no hue of its own, so the picker keeps the one it had")
        XCTAssertEqual(grey.saturation, 0, accuracy: 1e-6)
    }
}
