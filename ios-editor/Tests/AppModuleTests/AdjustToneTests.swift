import XCTest
import CoreGraphics
@testable import NeonixEditor

/// The Adjust tool's light/colour/detail compilation and the non-SVG primitives it relies on (`feVibrance`,
/// `feHighlightShadow`, `feTemperatureTint`, `feUnsharpMask`), each checked against its Core Image filter.
final class AdjustToneTests: XCTestCase {
    // MARK: compilation

    private func project() -> V2Project {
        V2Project(composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"), assets: [], layers: [
            V2Layer(id: "clip1", order: 0, frame: V2Frame(width: 360, height: 640), transform: .identity,
                    timing: V2Timing(start: 0, duration: 1000), payload: .video(V2VideoPayload(assetId: "a")))
        ])
    }

    private func primitives(for values: AdjustValues) -> [V2FilterPrimitive] {
        SetAdjustCommand(layerId: "clip1", values: values).apply(to: project()).filters?.first?.primitives ?? []
    }

    func testOnlyTheLightGroupBuildsToneStages() {
        var v = AdjustValues(); v.brightness = 0.3
        let gamma = primitives(for: v)
        XCTAssertEqual(gamma.count, 1, "brightness alone is one gamma stage")
        guard case .feComponentTransfer(_, let f) = gamma[0], case .gamma(let amp, let exp, let off)? = f.r else { return XCTFail("expected gamma") }
        XCTAssertEqual(amp, 1); XCTAssertEqual(off, 0); XCTAssertEqual(exp, pow(2, -0.3), accuracy: 1e-9)
        var e = AdjustValues(); e.exposure = 1
        XCTAssertEqual(primitives(for: e).count, 1, "exposure alone is one gain stage")
        var both = AdjustValues(); both.exposure = 1; both.shadows = 0.5
        XCTAssertEqual(primitives(for: both).count, 2, "linear + feHighlightShadow")
        var all = AdjustValues(); all.exposure = 1; all.shadows = 0.5; all.contrast = 1.2; all.brightness = 0.2
        XCTAssertEqual(primitives(for: all).count, 4, "linear, feHighlightShadow, contrast, gamma")
    }

    func testBlackPointAndExposureShareOneLinearStage() {
        var v = AdjustValues(); v.blackPoint = 1; v.exposure = 1
        let p = primitives(for: v)
        XCTAssertEqual(p.count, 1)
        guard case .feComponentTransfer(_, let f) = p[0], case .linear(let slope, let intercept)? = f.r else { return XCTFail("expected linear") }
        let a = adjustBlackPointRange
        XCTAssertEqual(slope, 2 / (1 - a), accuracy: 1e-9)
        XCTAssertEqual(intercept, -a / (1 - a), accuracy: 1e-9)
    }

    func testHighlightsShadowsAndBrillianceAllLandInOneFeHighlightShadow() {
        var v = AdjustValues(); v.highlights = -0.2; v.shadows = 0.1; v.brilliance = 0.5
        let p = primitives(for: v)
        XCTAssertEqual(p.count, 1)
        guard case .feHighlightShadow(_, let h, let s) = p[0] else { return XCTFail("expected feHighlightShadow") }
        XCTAssertEqual(h, -0.2 - 0.5 * adjustBrillianceHighlights, accuracy: 1e-9, "brilliance pulls highlights down")
        XCTAssertEqual(s, 0.1 + 0.5 * adjustBrillianceShadows, accuracy: 1e-9, "and lifts shadows")
        var extreme = AdjustValues(); extreme.shadows = 1; extreme.brilliance = 1
        guard case .feHighlightShadow(_, _, let clamped) = primitives(for: extreme)[0] else { return XCTFail() }
        XCTAssertEqual(clamped, 1, "clamped to the primitive's -1...1")
    }

    func testWhiteBalanceAndDetailCompileToOneNonSvgPrimitiveEach() {
        var w = AdjustValues(); w.temperature = 0.4; w.tint = -0.2
        guard case .feTemperatureTint(_, let t, let tint) = primitives(for: w).first else { return XCTFail("expected feTemperatureTint") }
        XCTAssertEqual(t, 0.4); XCTAssertEqual(tint, -0.2)
        var s = AdjustValues(); s.sharpen = 0.5
        guard case .feUnsharpMask(_, let r1, let i1) = primitives(for: s).first else { return XCTFail("expected feUnsharpMask") }
        XCTAssertEqual(r1, adjustSharpenRadius); XCTAssertEqual(i1, 0.5)
        var c = AdjustValues(); c.clarity = -0.3
        guard case .feUnsharpMask(_, let r2, let i2) = primitives(for: c).first else { return XCTFail("expected feUnsharpMask") }
        XCTAssertEqual(r2, adjustClarityRadius); XCTAssertEqual(i2, -0.3)
        XCTAssertGreaterThan(r2, r1, "clarity is the wide-radius mask")
    }

    func testVibranceCompilesToItsOwnPrimitiveAndSaturationHueToMatrices() {
        var v = AdjustValues(); v.vibrance = 0.6
        let only = primitives(for: v)
        XCTAssertEqual(only.count, 1)
        guard case .feVibrance(_, let amount) = only[0] else { return XCTFail("expected feVibrance") }
        XCTAssertEqual(amount, 0.6)

        var all = AdjustValues(); all.vibrance = 0.6; all.saturation = 1.3; all.hue = 20
        XCTAssertEqual(primitives(for: all).count, 3, "hueRotate + saturate + feVibrance")
    }

    func testBlurAndLightnessAreGoneFromAdjust() {
        let mirror = Mirror(reflecting: AdjustValues()).children.compactMap(\.label)
        XCTAssertFalse(mirror.contains("blur"))
        XCTAssertFalse(mirror.contains("lightness"))
        for name in ["brilliance", "highlights", "shadows", "blackPoint", "vibrance", "sharpen"] {
            XCTAssertTrue(mirror.contains(name), name)
        }
    }

    func testTheNewPresetsAndPrimitiveRoundTripThroughJSON() throws {
        let presets: [EffectPresetKind] = [
            .toneAdjust(exposure: 0.5, brilliance: 0.1, highlights: -0.2, shadows: 0.3, contrast: 1.2, brightness: 0.4, blackPoint: -0.1),
            .colorGrade(saturation: 1.2, vibrance: 0.5, hue: 15),
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys   // key order is otherwise unspecified
        for preset in presets {
            let data = try encoder.encode(preset)
            XCTAssertEqual(try encoder.encode(try JSONDecoder().decode(EffectPresetKind.self, from: data)), data)
        }
        let primitive = V2FilterPrimitive.feVibrance(V2FilterPrimitiveBase(id: "v", in: "SourceGraphic", result: "v", region: nil, colorInterpolationFilters: nil), amount: 0.4)
        let data = try JSONEncoder().encode(primitive)
        guard case .feVibrance(let base, let amount) = try JSONDecoder().decode(V2FilterPrimitive.self, from: data) else { return XCTFail() }
        XCTAssertEqual(base.id, "v")
        XCTAssertEqual(amount, 0.4)

        let b = V2FilterPrimitiveBase(id: "p", in: "SourceGraphic", result: "p", region: nil, colorInterpolationFilters: nil)
        let encoder2 = JSONEncoder(); encoder2.outputFormatting = .sortedKeys
        for primitive in [V2FilterPrimitive.feHighlightShadow(b, highlights: -0.3, shadows: 0.5),
                          .feTemperatureTint(b, temperature: 0.2, tint: -0.4),
                          .feUnsharpMask(b, radius: 2.5, intensity: 0.7)] {
            let data = try encoder2.encode(primitive)
            XCTAssertEqual(try encoder2.encode(try JSONDecoder().decode(V2FilterPrimitive.self, from: data)), data)
        }
    }

    // MARK: rendering

    private func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGImage {
        let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: r, green: g, blue: b, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        return context.makeImage()!
    }

    private func pixel(_ image: CGImage, x: Int = 0) -> (r: Int, g: Int, b: Int) {
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: 0, width: image.width, height: image.height))
        return (Int(data[0]), Int(data[1]), Int(data[2]))
    }

    /// 32x32, left half dark grey (0.3), right half light grey (0.7) - a vertical step edge at x = 16.
    private func stepEdge() -> CGImage {
        let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: 16, height: 32))
        context.setFillColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 1); context.fill(CGRect(x: 16, y: 0, width: 16, height: 32))
        return context.makeImage()!
    }

    private func render(_ values: AdjustValues, _ source: CGImage) -> (r: Int, g: Int, b: Int) {
        let filter = SetAdjustCommand(layerId: "clip1", values: values).apply(to: project()).filters!.first!
        return pixel(FilterRenderer.apply(filter, to: source)!)
    }

    func testBrightnessPlusMaxLiftsAMidGreyWithoutBlowingOutWhiteOrBlack() {
        var v = AdjustValues(); v.brightness = 1
        let mid = render(v, solid(0.5, 0.5, 0.5))
        XCTAssertEqual(Double(mid.r), 0.707 * 255, accuracy: 4, "0.5 -> 0.707, not the old additive 1.0")
        XCTAssertEqual(render(v, solid(1, 1, 1)).r, 255)
        XCTAssertEqual(render(v, solid(0, 0, 0)).r, 0)
    }

    func testVibranceBoostsAMutedColourAndLeavesGreyAlone() {
        var v = AdjustValues(); v.vibrance = 1
        let muted = solid(0.6, 0.5, 0.5)
        let before = pixel(muted), after = render(v, muted)
        XCTAssertGreaterThan(after.r - after.g, before.r - before.g, "the colour spread grows")
        let grey = render(v, solid(0.5, 0.5, 0.5))
        XCTAssertEqual(grey.r, grey.g, accuracy: 2)
        XCTAssertEqual(grey.g, grey.b, accuracy: 2)
    }

    // MARK: Core Image filters behind the non-SVG primitives

    func testShadowsLiftADarkPixelAndHighlightsRecoverABrightOne() {
        let dark = solid(0.15, 0.15, 0.15), bright = solid(0.9, 0.9, 0.9)
        var up = AdjustValues(); up.shadows = 1
        XCTAssertGreaterThan(render(up, dark).r, pixel(dark).r + 10, "shadows + lifts the darks")
        var down = AdjustValues(); down.highlights = -1
        XCTAssertLessThan(render(down, bright).r, pixel(bright).r - 10, "highlights - recovers the brights")
        var up2 = AdjustValues(); up2.highlights = 1
        XCTAssertGreaterThan(render(up2, solid(0.75, 0.75, 0.75)).r, pixel(solid(0.75, 0.75, 0.75)).r, "highlights + brightens (hand-written curve)")
    }

    func testTemperatureWarmsAndCoolsAndTintMovesGreen() {
        let grey = solid(0.5, 0.5, 0.5)
        var warm = AdjustValues(); warm.temperature = 1
        let w = render(warm, grey)
        XCTAssertGreaterThan(w.r, w.b, "temperature + is warmer (more red than blue)")
        var cool = AdjustValues(); cool.temperature = -1
        let c = render(cool, grey)
        XCTAssertGreaterThan(c.b, c.r, "temperature - is cooler")
        var green = AdjustValues(); green.tint = 1
        let g = render(green, grey)
        XCTAssertGreaterThan(g.g, g.r, "tint + is greener")
    }

    func testSharpenOvershootsAtAnEdgeAndNegativeClaritySoftensIt() {
        let edge = stepEdge()
        let before = pixel(edge, x: 14), beforeBright = pixel(edge, x: 17)
        var sharp = AdjustValues(); sharp.sharpen = 1
        let sharpened = FilterRenderer.apply(SetAdjustCommand(layerId: "clip1", values: sharp).apply(to: project()).filters!.first!, to: edge)!
        XCTAssertLessThan(pixel(sharpened, x: 14).r, before.r, "dark side goes darker next to the edge")
        var soft = AdjustValues(); soft.clarity = -1
        let filter = SetAdjustCommand(layerId: "clip1", values: soft).apply(to: project()).filters!.first!
        let softened = FilterRenderer.apply(filter, to: edge)!
        XCTAssertGreaterThan(pixel(softened, x: 14).r, before.r, "negative clarity pulls the dark side toward the blur")
        XCTAssertLessThan(pixel(softened, x: 17).r, beforeBright.r)
    }
}
