import XCTest
import CoreGraphics
@testable import NeonixEditor

/// Covers `FilterRenderer` end to end — a real `CIContext` render, not a
/// mock, reading back actual output pixels (same "real I/O" discipline as
/// `MediaImportServiceTests`/`AudioMixEngineTests`) and comparing against
/// hand-computed expected values for the W3C `feColorMatrix`
/// `saturate`/`hueRotate` formulas and `feComponentTransfer`'s `linear`
/// function.
final class FilterRendererTests: XCTestCase {
    /// A solid-color image — small enough to render instantly, large enough
    /// for `CIContext.createCGImage` to produce a normal image. `size`
    /// defaults to 2 (fine for position-independent point filters); blur/
    /// convolution tests pass a larger size so the center pixel isn't
    /// dominated by edge-clamping.
    private func solidColorImage(r: CGFloat, g: CGFloat, b: CGFloat, size: Int = 2) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: r, green: g, blue: b, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()!
    }

    /// Reads back the top-left pixel's RGBA (0...255 each).
    private func pixel(of image: CGImage) -> (r: Int, g: Int, b: Int, a: Int) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (Int(data[0]), Int(data[1]), Int(data[2]), Int(data[3]))
    }

    private func base(result: String) -> V2FilterPrimitiveBase {
        V2FilterPrimitiveBase(id: result, in: "SourceGraphic", result: result, region: nil, colorInterpolationFilters: nil)
    }

    private func makeFilter(primitives: [V2FilterPrimitive]) -> V2Filter {
        V2Filter(id: "test", x: nil, y: nil, width: nil, height: nil, filterUnits: nil, primitiveUnits: nil, colorInterpolationFilters: nil, primitives: primitives, tracks: nil)
    }

    func testSaturateZeroFullyDesaturatesToLuminance() {
        // Pure red (255,0,0) fully desaturated should land on its luma
        // value (~54 per the W3C saturate matrix's red-channel weight,
        // 0.213) on every channel.
        let source = solidColorImage(r: 1, g: 0, b: 0)
        let filter = makeFilter(primitives: [.feColorMatrix(base(result: "out"), kind: "saturate", values: [0])])

        let result = FilterRenderer.apply(filter, to: source)
        XCTAssertNotNil(result)
        let p = pixel(of: result!)

        let expected = Double(Int(0.213 * 255))
        XCTAssertEqual(Double(p.r), expected, accuracy: 2)
        XCTAssertEqual(Double(p.g), expected, accuracy: 2)
        XCTAssertEqual(Double(p.b), expected, accuracy: 2)
    }

    func testSaturateOneIsIdentity() {
        let source = solidColorImage(r: 0.4, g: 0.6, b: 0.2)
        let filter = makeFilter(primitives: [.feColorMatrix(base(result: "out"), kind: "saturate", values: [1])])

        let result = FilterRenderer.apply(filter, to: source)
        let original = pixel(of: source)
        let p = pixel(of: result!)

        XCTAssertEqual(Double(p.r), Double(original.r), accuracy: 2)
        XCTAssertEqual(Double(p.g), Double(original.g), accuracy: 2)
        XCTAssertEqual(Double(p.b), Double(original.b), accuracy: 2)
    }

    func testHueRotate360DegreesIsIdentity() {
        let source = solidColorImage(r: 0.4, g: 0.6, b: 0.2)
        let filter = makeFilter(primitives: [.feColorMatrix(base(result: "out"), kind: "hueRotate", values: [360])])

        let result = FilterRenderer.apply(filter, to: source)
        let original = pixel(of: source)
        let p = pixel(of: result!)

        XCTAssertEqual(Double(p.r), Double(original.r), accuracy: 2)
        XCTAssertEqual(Double(p.g), Double(original.g), accuracy: 2)
        XCTAssertEqual(Double(p.b), Double(original.b), accuracy: 2)
    }

    func testComponentTransferLinearAppliesSlopeAndIntercept() {
        // 0.5 gray -> slope 0.5, intercept 0.25 -> 0.5*0.5+0.25 = 0.5 (no visible change here on purpose:
        // pick values that *do* change it to make the assertion meaningful).
        let source = solidColorImage(r: 0.5, g: 0.5, b: 0.5)
        let functions = V2ComponentTransferFunctions(
            r: .linear(slope: 1, intercept: 0.2), g: .linear(slope: 1, intercept: 0.2), b: .linear(slope: 1, intercept: 0.2), a: nil
        )
        let filter = makeFilter(primitives: [.feComponentTransfer(base(result: "out"), functions: functions)])

        let result = FilterRenderer.apply(filter, to: source)
        let p = pixel(of: result!)

        let expected = Double(Int((0.5 + 0.2) * 255))
        XCTAssertEqual(Double(p.r), expected, accuracy: 2)
        XCTAssertEqual(Double(p.g), expected, accuracy: 2)
        XCTAssertEqual(Double(p.b), expected, accuracy: 2)
    }

    func testChainedPrimitivesFeedForwardThroughNamedResults() {
        // saturate(0) then a +0.2 brightness bump — confirms `in`/`result`
        // wiring actually chains (not just applying the last primitive to
        // the original source).
        let source = solidColorImage(r: 1, g: 0, b: 0)
        let satBase = base(result: "sat")
        var toneBase = base(result: "tone")
        toneBase.in = "sat"
        let functions = V2ComponentTransferFunctions(
            r: .linear(slope: 1, intercept: 0.1), g: .linear(slope: 1, intercept: 0.1), b: .linear(slope: 1, intercept: 0.1), a: nil
        )
        let filter = makeFilter(primitives: [
            .feColorMatrix(satBase, kind: "saturate", values: [0]),
            .feComponentTransfer(toneBase, functions: functions),
        ])

        let result = FilterRenderer.apply(filter, to: source)
        let p = pixel(of: result!)

        let expected = Double(Int((0.213 + 0.1) * 255))
        XCTAssertEqual(Double(p.r), expected, accuracy: 2)
        XCTAssertEqual(Double(p.g), expected, accuracy: 2)
        XCTAssertEqual(Double(p.b), expected, accuracy: 2)
    }

    // MARK: - feGaussianBlur (Blur slider)

    func testGaussianBlurLeavesAFlatFieldUnchanged() {
        // `.clampedToExtent()` fills outside the image with the same edge
        // color, so a perfectly flat field is its own fixed point under
        // blur — the cleanest way to confirm the clamp/crop plumbing
        // without needing a non-uniform reference image.
        let source = solidColorImage(r: 0.4, g: 0.6, b: 0.2)
        let filter = makeFilter(primitives: [.feGaussianBlur(base(result: "out"), stdDeviation: V2FilterStdDeviation(x: 10, y: 10))])

        let result = FilterRenderer.apply(filter, to: source)
        XCTAssertNotNil(result)
        let original = pixel(of: source)
        let p = pixel(of: result!)

        XCTAssertEqual(Double(p.r), Double(original.r), accuracy: 2)
        XCTAssertEqual(Double(p.g), Double(original.g), accuracy: 2)
        XCTAssertEqual(Double(p.b), Double(original.b), accuracy: 2)
    }

    // MARK: - feConvolveMatrix (Sharpen slider)

    func testSharpenConvolutionLeavesAFlatFieldUnchanged() {
        // The 3×3 unsharp kernel's weights sum to 1 by construction
        // (center `1+4k`, 4 neighbors `-k`) — on a flat field every
        // neighbor equals the center, so the result is the input
        // unchanged regardless of `amount`.
        let source = solidColorImage(r: 0.5, g: 0.3, b: 0.8)
        let k = 0.6
        let kernel: [Double] = [0, -k, 0, -k, 1 + 4 * k, -k, 0, -k, 0]
        let filter = makeFilter(primitives: [
            .feConvolveMatrix(base(result: "out"), order: V2XYInt(x: 3, y: 3), kernelMatrix: kernel, divisor: nil, bias: nil, target: nil, edgeMode: "duplicate", preserveAlpha: true),
        ])

        let result = FilterRenderer.apply(filter, to: source)
        XCTAssertNotNil(result)
        let original = pixel(of: source)
        let p = pixel(of: result!)

        XCTAssertEqual(Double(p.r), Double(original.r), accuracy: 3)
        XCTAssertEqual(Double(p.g), Double(original.g), accuracy: 3)
        XCTAssertEqual(Double(p.b), Double(original.b), accuracy: 3)
    }

    // MARK: - feComposite arithmetic (Clarity slider)

    func testClarityArithmeticCompositeLeavesAFlatFieldUnchanged() {
        // Clarity's formula is `(1+amount)*original - amount*blurred`; on a
        // flat field `blurred == original`, so this reduces to
        // `(1+amount)*c - amount*c == c` for any `amount`.
        let source = solidColorImage(r: 0.6, g: 0.5, b: 0.1)
        let blurBase = base(result: "blur")
        var compositeBase = base(result: "composite")
        compositeBase.in = "SourceGraphic"
        let amount = 0.7
        let filter = makeFilter(primitives: [
            .feGaussianBlur(blurBase, stdDeviation: V2FilterStdDeviation(x: 20, y: 20)),
            .feComposite(compositeBase, in2: "blur", operator_: "arithmetic", k1: 0, k2: 1 + amount, k3: -amount, k4: 0),
        ])

        let result = FilterRenderer.apply(filter, to: source)
        XCTAssertNotNil(result)
        let original = pixel(of: source)
        let p = pixel(of: result!)

        XCTAssertEqual(Double(p.r), Double(original.r), accuracy: 3)
        XCTAssertEqual(Double(p.g), Double(original.g), accuracy: 3)
        XCTAssertEqual(Double(p.b), Double(original.b), accuracy: 3)
    }

    // MARK: - feComponentTransfer "table" via CIToneCurve (Tone Curve sliders)

    func testIdentityToneCurveLeavesTheImageUnchanged() {
        let source = solidColorImage(r: 0.3, g: 0.7, b: 0.9)
        let identity: [Double] = [0, 0.25, 0.5, 0.75, 1]
        let functions = V2ComponentTransferFunctions(
            r: .table(values: identity), g: .table(values: identity), b: .table(values: identity), a: nil
        )
        let filter = makeFilter(primitives: [.feComponentTransfer(base(result: "out"), functions: functions)])

        let result = FilterRenderer.apply(filter, to: source)
        let original = pixel(of: source)
        let p = pixel(of: result!)

        XCTAssertEqual(Double(p.r), Double(original.r), accuracy: 3)
        XCTAssertEqual(Double(p.g), Double(original.g), accuracy: 3)
        XCTAssertEqual(Double(p.b), Double(original.b), accuracy: 3)
    }

    func testFlatBlackToneCurveCrushesEveryChannelToZero() {
        let source = solidColorImage(r: 0.3, g: 0.7, b: 0.9)
        let allZero: [Double] = [0, 0, 0, 0, 0]
        let functions = V2ComponentTransferFunctions(
            r: .table(values: allZero), g: .table(values: allZero), b: .table(values: allZero), a: nil
        )
        let filter = makeFilter(primitives: [.feComponentTransfer(base(result: "out"), functions: functions)])

        let result = FilterRenderer.apply(filter, to: source)
        let p = pixel(of: result!)

        XCTAssertEqual(Double(p.r), 0, accuracy: 2)
        XCTAssertEqual(Double(p.g), 0, accuracy: 2)
        XCTAssertEqual(Double(p.b), 0, accuracy: 2)
    }

    // MARK: - feVignette (Vignette slider)

    func testVignetteWithZeroIntensityLeavesTheImageUnchanged() {
        let source = solidColorImage(r: 0.5, g: 0.5, b: 0.5)
        let filter = makeFilter(primitives: [.feVignette(base(result: "out"), radius: 1, intensity: 0)])

        let result = FilterRenderer.apply(filter, to: source)
        XCTAssertNotNil(result)
        let original = pixel(of: source)
        let p = pixel(of: result!)

        XCTAssertEqual(Double(p.r), Double(original.r), accuracy: 2)
        XCTAssertEqual(Double(p.g), Double(original.g), accuracy: 2)
        XCTAssertEqual(Double(p.b), Double(original.b), accuracy: 2)
    }

    // MARK: - feTurbulence + feMerge (Noise slider)

    func testNoiseChainProducesAnImageOfTheSameExtent() {
        // `CIRandomGenerator`-backed turbulence is non-deterministic by
        // design, so this only confirms the `feTurbulence`→
        // `feComponentTransfer`(alpha)→`feMerge` chain actually renders a
        // real, correctly-sized image rather than asserting exact pixel
        // values.
        let source = solidColorImage(r: 0.5, g: 0.5, b: 0.5)
        let turbulenceBase = base(result: "turb")
        var toneBase = base(result: "tone")
        toneBase.in = "turb"
        var mergeBase = base(result: "merged")
        mergeBase.in = "SourceGraphic"
        let filter = makeFilter(primitives: [
            .feTurbulence(turbulenceBase, baseFrequency: V2XY(x: 0.5, y: 0.5), numOctaves: 1, seed: 1, stitchTiles: nil, noiseType: "fractalNoise"),
            .feComponentTransfer(toneBase, functions: V2ComponentTransferFunctions(r: nil, g: nil, b: nil, a: .linear(slope: 0.3, intercept: 0))),
            .feMerge(mergeBase, nodes: ["SourceGraphic", "tone"]),
        ])

        let result = FilterRenderer.apply(filter, to: source)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.width, source.width)
        XCTAssertEqual(result?.height, source.height)
    }
}
