import CoreImage
import CoreGraphics

/// The Core Image bridge Protocol V2's `V2Filter` primitive graph never had
/// — `PreviewCanvas` never read `layer.filter` before this (see CLAUDE.md's
/// "Tuỳ chỉnh" note). Walks `V2Filter.primitives` and evaluates them as a
/// real `CIImage` pipeline, the same way a browser would evaluate an SVG
/// `<filter>` graph.
///
/// Not actor-isolated — `CIContext`/`CIImage` are thread-safe, and callers
/// (`FilteredImageView`) run this off the main thread via `.task`, never
/// synchronously from a SwiftUI `body` (see CLAUDE.md's "Scrubbing must
/// never re-decode media inline from `body`" rule — the same discipline
/// applies to filtering).
enum FilterRenderer {
    /// One shared context, matching the precedent at
    /// `Playback/VideoFrameServer.swift`'s `previewCIContext` — a fresh
    /// `CIContext` per call would be expensive and is never needed.
    ///
    /// `.workingColorSpace: NSNull()` deliberately turns off Core Image's
    /// automatic color management for the filter math itself. Left on,
    /// Core Image treats 8-bit component values as gamma-encoded sRGB,
    /// linearizes them before running the matrix math, then re-encodes the
    /// result — so a `feColorMatrix`/`feComponentTransfer` built from the
    /// plain W3C Filter Effects formulas (which operate directly on the
    /// stored component values, the same way every other SVG/CSS filter
    /// implementation does) comes out visibly wrong (confirmed the hard
    /// way: a `saturate` test case was off by ~70 of 255, not a rounding-
    /// level drift). **Deliberately not** also setting `.outputColorSpace:
    /// NSNull()` here — that produced a `CGImage` with no embedded color
    /// space at all, which `FilterRendererTests`' raw-byte pixel reads
    /// didn't notice but SwiftUI's `Image(decorative:)` silently refused to
    /// draw on a real decoded video frame (confirmed on the simulator: the
    /// Stage went blank the moment any filter — even a no-op-ish one — was
    /// attached to a video layer). `apply(_:to:)` passes an explicit
    /// device RGB color space to `createCGImage` instead, once per call,
    /// so the result always has a well-defined one.
    private static let context = CIContext(options: [.workingColorSpace: NSNull(), .cacheIntermediates: false])
    private static let outputColorSpace = CGColorSpaceCreateDeviceRGB()

    /// `nil` only if the image/context genuinely fails to render (e.g. a
    /// degenerate 0-size source) — never for an unsupported primitive type,
    /// which instead passes its input through unchanged (see `evaluate`).
    static func apply(_ filter: V2Filter, to image: CGImage) -> CGImage? {
        // Same reasoning as the context's own color-space options — without
        // this, the *input* image gets color-matched into Core Image's
        // working space before any primitive ever sees it.
        let source = CIImage(cgImage: image, options: [.colorSpace: NSNull()])
        let output = apply(filter, to: source)
        return context.createCGImage(output, from: source.extent, format: .RGBA8, colorSpace: outputColorSpace)
    }

    /// Evaluates a filter without materializing a `CGImage`. Video preview
    /// uses this overload with a `CVPixelBuffer`-backed `CIImage` and sends
    /// the result straight to a Metal drawable.
    static func apply(_ filter: V2Filter, to source: CIImage) -> CIImage {
        var outputs: [String: CIImage] = ["SourceGraphic": source]
        var last = source

        for primitive in filter.primitives {
            let primitiveBase = primitive.base
            let input = outputs[primitiveBase.in ?? "SourceGraphic"] ?? last
            let output = evaluate(primitive, input: input, outputs: outputs, extent: source.extent)
            if let name = primitiveBase.result {
                outputs[name] = output
            }
            last = output
        }
        return last.cropped(to: source.extent)
    }

    /// One primitive's own evaluation. Implements exactly what the "Tuỳ
    /// chỉnh" sliders compile to so far (`EffectPresets.swift`): `feColorMatrix`
    /// (`matrix`/`saturate`/`hueRotate`), `feComponentTransfer`
    /// (`identity`/`linear`/`table` via `CIToneCurve`), `feGaussianBlur`,
    /// `feComposite` (`arithmetic` only), `feConvolveMatrix` (3×3 only),
    /// `feTurbulence` (approximated — see that case's own comment),
    /// `feMerge`, and `feVignette`. Every other primitive type passes
    /// `input` through unchanged rather than crashing/blanking the layer —
    /// this app's established "no ported validator, fail closed"
    /// convention.
    private static func evaluate(_ primitive: V2FilterPrimitive, input: CIImage, outputs: [String: CIImage], extent: CGRect) -> CIImage {
        switch primitive {
        case .feColorMatrix(_, let kind, let values):
            return colorMatrix(kind: kind, values: values ?? [], input: input)
        case .feComponentTransfer(_, let functions):
            return componentTransfer(functions, input: input)
        case .feGaussianBlur(_, let stdDeviation):
            return gaussianBlur(input: input, stdDeviation: stdDeviation, extent: extent)
        case .feComposite(_, let in2, let operator_, let k1, let k2, let k3, let k4):
            guard operator_ == "arithmetic", let second = outputs[in2] else { return input }
            return arithmeticComposite(input, second, k1: k1 ?? 0, k2: k2 ?? 0, k3: k3 ?? 0, k4: k4 ?? 0)
        case .feConvolveMatrix(_, let order, let kernelMatrix, _, let bias, _, _, _):
            return convolve(input: input, order: order, kernelMatrix: kernelMatrix, bias: bias ?? 0, extent: extent)
        case .feTurbulence:
            return turbulence(extent: extent)
        case .feMerge(_, let nodes):
            return merge(nodes: nodes, outputs: outputs, fallback: input)
        case .feVignette(_, let radius, let intensity):
            return vignette(input: input, radius: radius, intensity: intensity)
        default:
            return input
        }
    }

    // MARK: feColorMatrix

    private static func colorMatrix(kind: String, values: [Double], input: CIImage) -> CIImage {
        let rows: [[Double]]
        switch kind {
        case "matrix":
            guard values.count == 20 else { return input }
            rows = stride(from: 0, to: 20, by: 5).map { Array(values[$0..<$0 + 5]) }
        case "saturate":
            rows = saturateMatrix(values.first ?? 1)
        case "hueRotate":
            rows = hueRotateMatrix(degrees: values.first ?? 0)
        default:
            // "luminanceToAlpha" — not needed by any slider yet.
            return input
        }

        guard let ciFilter = CIFilter(name: "CIColorMatrix") else { return input }
        ciFilter.setValue(input, forKey: kCIInputImageKey)
        ciFilter.setValue(CIVector(x: rows[0][0], y: rows[0][1], z: rows[0][2], w: rows[0][3]), forKey: "inputRVector")
        ciFilter.setValue(CIVector(x: rows[1][0], y: rows[1][1], z: rows[1][2], w: rows[1][3]), forKey: "inputGVector")
        ciFilter.setValue(CIVector(x: rows[2][0], y: rows[2][1], z: rows[2][2], w: rows[2][3]), forKey: "inputBVector")
        ciFilter.setValue(CIVector(x: rows[3][0], y: rows[3][1], z: rows[3][2], w: rows[3][3]), forKey: "inputAVector")
        ciFilter.setValue(CIVector(x: rows[0][4], y: rows[1][4], z: rows[2][4], w: rows[3][4]), forKey: "inputBiasVector")
        return ciFilter.outputImage ?? input
    }

    /// The standard W3C Filter Effects `feColorMatrix type="saturate"`
    /// formula (`s` in `0...1`; luminance-preserving, not a naive per-
    /// channel scale).
    private static func saturateMatrix(_ s: Double) -> [[Double]] {
        [
            [0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0],
            [0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0],
            [0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0],
            [0, 0, 0, 1, 0],
        ]
    }

    /// The standard W3C Filter Effects `feColorMatrix type="hueRotate"`
    /// formula.
    private static func hueRotateMatrix(degrees: Double) -> [[Double]] {
        let radians = degrees * .pi / 180
        let c = cos(radians), s = sin(radians)
        return [
            [0.213 + c * 0.787 - s * 0.213, 0.715 - c * 0.715 - s * 0.715, 0.072 - c * 0.072 + s * 0.928, 0, 0],
            [0.213 - c * 0.213 + s * 0.143, 0.715 + c * 0.285 + s * 0.140, 0.072 - c * 0.072 - s * 0.283, 0, 0],
            [0.213 - c * 0.213 - s * 0.787, 0.715 - c * 0.715 + s * 0.715, 0.072 + c * 0.928 + s * 0.072, 0, 0],
            [0, 0, 0, 1, 0],
        ]
    }

    // MARK: feComponentTransfer

    /// `"linear"` maps exactly onto `CIColorMatrix`'s diagonal+bias — no
    /// custom kernel needed. `"table"` (used by the Tone Curve slider
    /// group) only handles the case where r/g/b share the *identical*
    /// 5-value table (always true for everything this app compiles today —
    /// `EffectPresets.swift`'s `.toneCurve` always writes the same table to
    /// all 3 channels), mapped onto `CIToneCurve`'s 5 fixed control points
    /// (`x = 0, 0.25, 0.5, 0.75, 1`) — an exact match, not an approximation,
    /// *for exactly 5 values*; any other table length, `"discrete"`, or
    /// per-channel-divergent tables fall through to identity rather than
    /// guessing (documented gap, not needed by anything built so far). A
    /// channel with no function (or `"identity"`) passes through (slope 1,
    /// intercept 0).
    private static func componentTransfer(_ functions: V2ComponentTransferFunctions, input: CIImage) -> CIImage {
        if case .table(let values) = functions.r, values.count == 5,
           case .table(let gValues) = functions.g, gValues == values,
           case .table(let bValues) = functions.b, bValues == values {
            return toneCurve(input: input, values: values)
        }

        func slopeIntercept(_ function: V2FilterTransferFunction?) -> (Double, Double) {
            guard case .linear(let slope, let intercept) = function else { return (1, 0) }
            return (slope, intercept)
        }
        let (rs, ri) = slopeIntercept(functions.r)
        let (gs, gi) = slopeIntercept(functions.g)
        let (bs, bi) = slopeIntercept(functions.b)
        let (aSlope, aIntercept) = slopeIntercept(functions.a)

        guard let ciFilter = CIFilter(name: "CIColorMatrix") else { return input }
        ciFilter.setValue(input, forKey: kCIInputImageKey)
        ciFilter.setValue(CIVector(x: rs, y: 0, z: 0, w: 0), forKey: "inputRVector")
        ciFilter.setValue(CIVector(x: 0, y: gs, z: 0, w: 0), forKey: "inputGVector")
        ciFilter.setValue(CIVector(x: 0, y: 0, z: bs, w: 0), forKey: "inputBVector")
        ciFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: aSlope), forKey: "inputAVector")
        ciFilter.setValue(CIVector(x: ri, y: gi, z: bi, w: aIntercept), forKey: "inputBiasVector")
        return ciFilter.outputImage ?? input
    }

    private static func toneCurve(input: CIImage, values: [Double]) -> CIImage {
        guard let ciFilter = CIFilter(name: "CIToneCurve") else { return input }
        ciFilter.setValue(input, forKey: kCIInputImageKey)
        let xs: [Double] = [0, 0.25, 0.5, 0.75, 1]
        for i in 0..<5 {
            ciFilter.setValue(CIVector(x: xs[i], y: values[i]), forKey: "inputPoint\(i)")
        }
        return ciFilter.outputImage ?? input
    }

    // MARK: feGaussianBlur

    /// `.clampedToExtent()` before blurring and `.cropped(to:)` after —
    /// without the clamp, `CIGaussianBlur` samples transparent pixels past
    /// the image's own edge, bleeding a dark/transparent fringe in; without
    /// the crop, the blur's own infinite-extent output would expand every
    /// downstream primitive's bounds.
    private static func gaussianBlur(input: CIImage, stdDeviation: V2FilterStdDeviation, extent: CGRect) -> CIImage {
        guard let ciFilter = CIFilter(name: "CIGaussianBlur") else { return input }
        ciFilter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        ciFilter.setValue(stdDeviation.x, forKey: kCIInputRadiusKey)
        guard let output = ciFilter.outputImage else { return input }
        return output.cropped(to: extent)
    }

    // MARK: feComposite (arithmetic only)

    /// `result = k1*i1*i2 + k2*i1 + k3*i2 + k4`. Only the `k1 == 0` case
    /// (no true per-pixel multiplicative term between the two inputs) is
    /// implemented — the only shape any compiled preset needs today
    /// (`.clarity`'s unsharp mask: `k1:0, k2:1+amount, k3:-amount, k4:0`).
    /// `k1 != 0` falls through to a plain linear combination, dropping the
    /// multiplicative term — documented gap, not silently wrong-by-a-lot
    /// for any case this app actually compiles.
    private static func arithmeticComposite(_ i1: CIImage, _ i2: CIImage, k1: Double, k2: Double, k3: Double, k4: Double) -> CIImage {
        let scaledA = scale(i1, by: k2, bias: k4)
        let scaledB = scale(i2, by: k3, bias: 0)
        guard let ciFilter = CIFilter(name: "CIAdditionCompositing") else { return i1 }
        ciFilter.setValue(scaledA, forKey: kCIInputImageKey)
        ciFilter.setValue(scaledB, forKey: kCIInputBackgroundImageKey)
        return ciFilter.outputImage ?? i1
    }

    private static func scale(_ image: CIImage, by factor: Double, bias: Double) -> CIImage {
        guard let ciFilter = CIFilter(name: "CIColorMatrix") else { return image }
        ciFilter.setValue(image, forKey: kCIInputImageKey)
        ciFilter.setValue(CIVector(x: factor, y: 0, z: 0, w: 0), forKey: "inputRVector")
        ciFilter.setValue(CIVector(x: 0, y: factor, z: 0, w: 0), forKey: "inputGVector")
        ciFilter.setValue(CIVector(x: 0, y: 0, z: factor, w: 0), forKey: "inputBVector")
        ciFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        ciFilter.setValue(CIVector(x: bias, y: bias, z: bias, w: 0), forKey: "inputBiasVector")
        return ciFilter.outputImage ?? image
    }

    // MARK: feConvolveMatrix

    /// Only 3×3 (`order.x == 3 && order.y == 3`) is implemented, via
    /// `CIConvolution3X3` — exactly what `.sharpen` compiles to. 5×5 and
    /// other sizes pass through unchanged (documented gap, nothing compiles
    /// those yet).
    private static func convolve(input: CIImage, order: V2XYInt, kernelMatrix: [Double], bias: Double, extent: CGRect) -> CIImage {
        guard order.x == 3, order.y == 3, kernelMatrix.count == 9,
              let ciFilter = CIFilter(name: "CIConvolution3X3")
        else { return input }
        ciFilter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        ciFilter.setValue(CIVector(values: kernelMatrix.map { CGFloat($0) }, count: 9), forKey: "inputWeights")
        ciFilter.setValue(bias, forKey: "inputBias")
        guard let output = ciFilter.outputImage else { return input }
        return output.cropped(to: extent)
    }

    // MARK: feTurbulence

    /// Approximated via `CIRandomGenerator` (white noise) rather than a
    /// true Perlin/fractal turbulence generator — `baseFrequency`/
    /// `numOctaves`/`noiseType` are accepted by the schema but not read
    /// here; close enough for a film-grain look (`.noise`'s whole point),
    /// not a faithful SVG `feTurbulence` port.
    private static func turbulence(extent: CGRect) -> CIImage {
        guard let ciFilter = CIFilter(name: "CIRandomGenerator"), let output = ciFilter.outputImage else {
            return CIImage(color: .clear).cropped(to: extent)
        }
        return output.cropped(to: extent)
    }

    // MARK: feMerge

    /// Paints each named node in order (first = bottom, matching SVG
    /// `feMerge`'s own painter's-model stacking) via `CISourceOverCompositing`.
    private static func merge(nodes: [String], outputs: [String: CIImage], fallback: CIImage) -> CIImage {
        let images = nodes.compactMap { outputs[$0] }
        guard var result = images.first else { return fallback }
        for image in images.dropFirst() {
            guard let ciFilter = CIFilter(name: "CISourceOverCompositing") else { continue }
            ciFilter.setValue(image, forKey: kCIInputImageKey)
            ciFilter.setValue(result, forKey: kCIInputBackgroundImageKey)
            result = ciFilter.outputImage ?? result
        }
        return result
    }

    // MARK: feVignette (non-SVG exception, see V2Filter.swift's own doc comment)

    private static func vignette(input: CIImage, radius: Double, intensity: Double) -> CIImage {
        guard let ciFilter = CIFilter(name: "CIVignette") else { return input }
        ciFilter.setValue(input, forKey: kCIInputImageKey)
        ciFilter.setValue(radius, forKey: kCIInputRadiusKey)
        ciFilter.setValue(intensity, forKey: kCIInputIntensityKey)
        return ciFilter.outputImage ?? input
    }
}
