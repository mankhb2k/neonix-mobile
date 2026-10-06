import Foundation

// Port of packages/motion-protocol/src/v2/filter.ts. The most complex single
// file in the schema: 17 SVG filter primitives as one discriminated union.
// No validation ported (duplicate id/result checks, feColorMatrix's 20-value
// requirement, feConvolveMatrix kernel/order match, isotropic blur/shadow
// lockstep) — see ARCHITECTURE.md's "valid by construction" note.

enum V2FilterUnits: String, Codable {
    case objectBoundingBox, userSpaceOnUse
}

enum V2FilterColorInterpolation: String, Codable {
    case sRGB, linearRGB
}

struct V2FilterRegion: Codable {
    var x: V2SvgLength?
    var y: V2SvgLength?
    var width: V2SvgLength?
    var height: V2SvgLength?
}

struct V2FilterStdDeviation: Codable {
    var x: Double
    var y: Double
}

struct V2XY: Codable {
    var x: Double
    var y: Double
}

struct V2XYInt: Codable {
    var x: Int
    var y: Int
}

enum V2FilterTransferFunction: Codable {
    case identity
    case table(values: [Double])
    case discrete(values: [Double])
    case linear(slope: Double, intercept: Double)
    case gamma(amplitude: Double, exponent: Double, offset: Double)

    private enum CodingKeys: String, CodingKey { case type, values, slope, intercept, amplitude, exponent, offset }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "identity": self = .identity
        case "table": self = .table(values: try c.decode([Double].self, forKey: .values))
        case "discrete": self = .discrete(values: try c.decode([Double].self, forKey: .values))
        case "linear": self = .linear(slope: try c.decode(Double.self, forKey: .slope), intercept: try c.decode(Double.self, forKey: .intercept))
        case "gamma": self = .gamma(amplitude: try c.decode(Double.self, forKey: .amplitude), exponent: try c.decode(Double.self, forKey: .exponent), offset: try c.decode(Double.self, forKey: .offset))
        case let other: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown transfer function: \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .identity: try c.encode("identity", forKey: .type)
        case .table(let values): try c.encode("table", forKey: .type); try c.encode(values, forKey: .values)
        case .discrete(let values): try c.encode("discrete", forKey: .type); try c.encode(values, forKey: .values)
        case .linear(let slope, let intercept): try c.encode("linear", forKey: .type); try c.encode(slope, forKey: .slope); try c.encode(intercept, forKey: .intercept)
        case .gamma(let amplitude, let exponent, let offset): try c.encode("gamma", forKey: .type); try c.encode(amplitude, forKey: .amplitude); try c.encode(exponent, forKey: .exponent); try c.encode(offset, forKey: .offset)
        }
    }
}

struct V2ComponentTransferFunctions: Codable {
    var r: V2FilterTransferFunction?
    var g: V2FilterTransferFunction?
    var b: V2FilterTransferFunction?
    var a: V2FilterTransferFunction?
}

enum V2FilterLight: Codable {
    case distant(azimuth: Double, elevation: Double)
    case point(x: Double, y: Double, z: Double)
    case spot(x: Double, y: Double, z: Double, pointsAtX: Double, pointsAtY: Double, pointsAtZ: Double, specularExponent: Double?, limitingConeAngle: Double?)

    private enum CodingKeys: String, CodingKey { case type, azimuth, elevation, x, y, z, pointsAtX, pointsAtY, pointsAtZ, specularExponent, limitingConeAngle }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "feDistantLight":
            self = .distant(azimuth: try c.decode(Double.self, forKey: .azimuth), elevation: try c.decode(Double.self, forKey: .elevation))
        case "fePointLight":
            self = .point(x: try c.decode(Double.self, forKey: .x), y: try c.decode(Double.self, forKey: .y), z: try c.decode(Double.self, forKey: .z))
        case "feSpotLight":
            self = .spot(
                x: try c.decode(Double.self, forKey: .x), y: try c.decode(Double.self, forKey: .y), z: try c.decode(Double.self, forKey: .z),
                pointsAtX: try c.decode(Double.self, forKey: .pointsAtX), pointsAtY: try c.decode(Double.self, forKey: .pointsAtY), pointsAtZ: try c.decode(Double.self, forKey: .pointsAtZ),
                specularExponent: try c.decodeIfPresent(Double.self, forKey: .specularExponent), limitingConeAngle: try c.decodeIfPresent(Double.self, forKey: .limitingConeAngle)
            )
        case let other: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown light: \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .distant(let azimuth, let elevation):
            try c.encode("feDistantLight", forKey: .type); try c.encode(azimuth, forKey: .azimuth); try c.encode(elevation, forKey: .elevation)
        case .point(let x, let y, let z):
            try c.encode("fePointLight", forKey: .type); try c.encode(x, forKey: .x); try c.encode(y, forKey: .y); try c.encode(z, forKey: .z)
        case .spot(let x, let y, let z, let pax, let pay, let paz, let se, let lca):
            try c.encode("feSpotLight", forKey: .type)
            try c.encode(x, forKey: .x); try c.encode(y, forKey: .y); try c.encode(z, forKey: .z)
            try c.encode(pax, forKey: .pointsAtX); try c.encode(pay, forKey: .pointsAtY); try c.encode(paz, forKey: .pointsAtZ)
            try c.encodeIfPresent(se, forKey: .specularExponent); try c.encodeIfPresent(lca, forKey: .limitingConeAngle)
        }
    }
}

/// Shared fields every `fe*` primitive carries.
struct V2FilterPrimitiveBase: Codable {
    var id: String
    var `in`: String?
    var result: String?
    var region: V2FilterRegion?
    var colorInterpolationFilters: V2FilterColorInterpolation?
}

indirect enum V2FilterPrimitive: Codable {
    case feBlend(V2FilterPrimitiveBase, in2: String, mode: V2BlendMode?)
    case feColorMatrix(V2FilterPrimitiveBase, kind: String, values: [Double]?)
    case feComponentTransfer(V2FilterPrimitiveBase, functions: V2ComponentTransferFunctions)
    case feComposite(V2FilterPrimitiveBase, in2: String, operator_: String?, k1: Double?, k2: Double?, k3: Double?, k4: Double?)
    case feConvolveMatrix(V2FilterPrimitiveBase, order: V2XYInt, kernelMatrix: [Double], divisor: Double?, bias: Double?, target: V2XYInt?, edgeMode: String?, preserveAlpha: Bool?)
    case feDisplacementMap(V2FilterPrimitiveBase, in2: String, scale: Double, xChannelSelector: String?, yChannelSelector: String?)
    case feDropShadow(V2FilterPrimitiveBase, dx: Double, dy: Double, stdDeviation: V2FilterStdDeviation, floodColor: V2Color, floodOpacity: Double?)
    case feFlood(V2FilterPrimitiveBase, color: V2Color, opacity: Double?)
    case feGaussianBlur(V2FilterPrimitiveBase, stdDeviation: V2FilterStdDeviation)
    case feImage(V2FilterPrimitiveBase, href: String)
    case feMerge(V2FilterPrimitiveBase, nodes: [String])
    case feMorphology(V2FilterPrimitiveBase, operator_: String?, radius: V2XY)
    case feOffset(V2FilterPrimitiveBase, dx: Double, dy: Double)
    case feTile(V2FilterPrimitiveBase)
    case feTurbulence(V2FilterPrimitiveBase, baseFrequency: V2XY, numOctaves: Int?, seed: Double?, stitchTiles: Bool?, noiseType: String?)
    case feDiffuseLighting(V2FilterPrimitiveBase, surfaceScale: Double, diffuseConstant: Double, kernelUnitLength: V2XY?, lightingColor: V2Color?, light: V2FilterLight)
    case feSpecularLighting(V2FilterPrimitiveBase, surfaceScale: Double, specularConstant: Double, specularExponent: Double, kernelUnitLength: V2XY?, lightingColor: V2Color?, light: V2FilterLight)

    var base: V2FilterPrimitiveBase {
        switch self {
        case .feBlend(let b, _, _), .feColorMatrix(let b, _, _), .feComponentTransfer(let b, _),
             .feComposite(let b, _, _, _, _, _, _), .feConvolveMatrix(let b, _, _, _, _, _, _, _),
             .feDisplacementMap(let b, _, _, _, _), .feDropShadow(let b, _, _, _, _, _), .feFlood(let b, _, _),
             .feGaussianBlur(let b, _), .feImage(let b, _), .feMerge(let b, _), .feMorphology(let b, _, _),
             .feOffset(let b, _, _), .feTile(let b), .feTurbulence(let b, _, _, _, _, _),
             .feDiffuseLighting(let b, _, _, _, _, _), .feSpecularLighting(let b, _, _, _, _, _, _):
            return b
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, `in`, result, region, colorInterpolationFilters
        case in2, mode, kind, values, functions, operator_ = "operator", k1, k2, k3, k4
        case order, kernelMatrix, divisor, bias, target, edgeMode, preserveAlpha
        case scale, xChannelSelector, yChannelSelector
        case dx, dy, stdDeviation, floodColor, floodOpacity
        case color, opacity, href, nodes, radius
        case baseFrequency, numOctaves, seed, stitchTiles, noiseType
        case surfaceScale, diffuseConstant, specularConstant, specularExponent, kernelUnitLength, lightingColor, light
    }
    private enum NodeKeys: String, CodingKey { case `in` }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = V2FilterPrimitiveBase(
            id: try c.decode(String.self, forKey: .id),
            in: try c.decodeIfPresent(String.self, forKey: .in),
            result: try c.decodeIfPresent(String.self, forKey: .result),
            region: try c.decodeIfPresent(V2FilterRegion.self, forKey: .region),
            colorInterpolationFilters: try c.decodeIfPresent(V2FilterColorInterpolation.self, forKey: .colorInterpolationFilters)
        )
        switch try c.decode(String.self, forKey: .type) {
        case "feBlend":
            self = .feBlend(base, in2: try c.decode(String.self, forKey: .in2), mode: try c.decodeIfPresent(V2BlendMode.self, forKey: .mode))
        case "feColorMatrix":
            self = .feColorMatrix(base, kind: try c.decode(String.self, forKey: .kind), values: try c.decodeIfPresent([Double].self, forKey: .values))
        case "feComponentTransfer":
            self = .feComponentTransfer(base, functions: try c.decode(V2ComponentTransferFunctions.self, forKey: .functions))
        case "feComposite":
            self = .feComposite(
                base, in2: try c.decode(String.self, forKey: .in2), operator_: try c.decodeIfPresent(String.self, forKey: .operator_),
                k1: try c.decodeIfPresent(Double.self, forKey: .k1), k2: try c.decodeIfPresent(Double.self, forKey: .k2),
                k3: try c.decodeIfPresent(Double.self, forKey: .k3), k4: try c.decodeIfPresent(Double.self, forKey: .k4)
            )
        case "feConvolveMatrix":
            self = .feConvolveMatrix(
                base, order: try c.decode(V2XYInt.self, forKey: .order), kernelMatrix: try c.decode([Double].self, forKey: .kernelMatrix),
                divisor: try c.decodeIfPresent(Double.self, forKey: .divisor), bias: try c.decodeIfPresent(Double.self, forKey: .bias),
                target: try c.decodeIfPresent(V2XYInt.self, forKey: .target), edgeMode: try c.decodeIfPresent(String.self, forKey: .edgeMode),
                preserveAlpha: try c.decodeIfPresent(Bool.self, forKey: .preserveAlpha)
            )
        case "feDisplacementMap":
            self = .feDisplacementMap(
                base, in2: try c.decode(String.self, forKey: .in2), scale: try c.decode(Double.self, forKey: .scale),
                xChannelSelector: try c.decodeIfPresent(String.self, forKey: .xChannelSelector), yChannelSelector: try c.decodeIfPresent(String.self, forKey: .yChannelSelector)
            )
        case "feDropShadow":
            self = .feDropShadow(
                base, dx: try c.decode(Double.self, forKey: .dx), dy: try c.decode(Double.self, forKey: .dy),
                stdDeviation: try c.decode(V2FilterStdDeviation.self, forKey: .stdDeviation),
                floodColor: try c.decode(V2Color.self, forKey: .floodColor), floodOpacity: try c.decodeIfPresent(Double.self, forKey: .floodOpacity)
            )
        case "feFlood":
            self = .feFlood(base, color: try c.decode(V2Color.self, forKey: .color), opacity: try c.decodeIfPresent(Double.self, forKey: .opacity))
        case "feGaussianBlur":
            self = .feGaussianBlur(base, stdDeviation: try c.decode(V2FilterStdDeviation.self, forKey: .stdDeviation))
        case "feImage":
            self = .feImage(base, href: try c.decode(String.self, forKey: .href))
        case "feMerge":
            let nodes = try c.decode([NodeContainer].self, forKey: .nodes)
            self = .feMerge(base, nodes: nodes.map(\.in))
        case "feMorphology":
            self = .feMorphology(base, operator_: try c.decodeIfPresent(String.self, forKey: .operator_), radius: try c.decode(V2XY.self, forKey: .radius))
        case "feOffset":
            self = .feOffset(base, dx: try c.decode(Double.self, forKey: .dx), dy: try c.decode(Double.self, forKey: .dy))
        case "feTile":
            self = .feTile(base)
        case "feTurbulence":
            self = .feTurbulence(
                base, baseFrequency: try c.decode(V2XY.self, forKey: .baseFrequency), numOctaves: try c.decodeIfPresent(Int.self, forKey: .numOctaves),
                seed: try c.decodeIfPresent(Double.self, forKey: .seed), stitchTiles: try c.decodeIfPresent(Bool.self, forKey: .stitchTiles),
                noiseType: try c.decodeIfPresent(String.self, forKey: .noiseType)
            )
        case "feDiffuseLighting":
            self = .feDiffuseLighting(
                base, surfaceScale: try c.decode(Double.self, forKey: .surfaceScale), diffuseConstant: try c.decode(Double.self, forKey: .diffuseConstant),
                kernelUnitLength: try c.decodeIfPresent(V2XY.self, forKey: .kernelUnitLength), lightingColor: try c.decodeIfPresent(V2Color.self, forKey: .lightingColor),
                light: try c.decode(V2FilterLight.self, forKey: .light)
            )
        case "feSpecularLighting":
            self = .feSpecularLighting(
                base, surfaceScale: try c.decode(Double.self, forKey: .surfaceScale), specularConstant: try c.decode(Double.self, forKey: .specularConstant),
                specularExponent: try c.decode(Double.self, forKey: .specularExponent),
                kernelUnitLength: try c.decodeIfPresent(V2XY.self, forKey: .kernelUnitLength), lightingColor: try c.decodeIfPresent(V2Color.self, forKey: .lightingColor),
                light: try c.decode(V2FilterLight.self, forKey: .light)
            )
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown filter primitive: \(other)")
        }
    }

    private struct NodeContainer: Codable {
        var `in`: String
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let base = self.base
        try c.encode(base.id, forKey: .id)
        try c.encodeIfPresent(base.in, forKey: .in)
        try c.encodeIfPresent(base.result, forKey: .result)
        try c.encodeIfPresent(base.region, forKey: .region)
        try c.encodeIfPresent(base.colorInterpolationFilters, forKey: .colorInterpolationFilters)
        switch self {
        case .feBlend(_, let in2, let mode):
            try c.encode("feBlend", forKey: .type); try c.encode(in2, forKey: .in2); try c.encodeIfPresent(mode, forKey: .mode)
        case .feColorMatrix(_, let kind, let values):
            try c.encode("feColorMatrix", forKey: .type); try c.encode(kind, forKey: .kind); try c.encodeIfPresent(values, forKey: .values)
        case .feComponentTransfer(_, let functions):
            try c.encode("feComponentTransfer", forKey: .type); try c.encode(functions, forKey: .functions)
        case .feComposite(_, let in2, let operator_, let k1, let k2, let k3, let k4):
            try c.encode("feComposite", forKey: .type); try c.encode(in2, forKey: .in2)
            try c.encodeIfPresent(operator_, forKey: .operator_)
            try c.encodeIfPresent(k1, forKey: .k1); try c.encodeIfPresent(k2, forKey: .k2); try c.encodeIfPresent(k3, forKey: .k3); try c.encodeIfPresent(k4, forKey: .k4)
        case .feConvolveMatrix(_, let order, let kernelMatrix, let divisor, let bias, let target, let edgeMode, let preserveAlpha):
            try c.encode("feConvolveMatrix", forKey: .type); try c.encode(order, forKey: .order); try c.encode(kernelMatrix, forKey: .kernelMatrix)
            try c.encodeIfPresent(divisor, forKey: .divisor); try c.encodeIfPresent(bias, forKey: .bias)
            try c.encodeIfPresent(target, forKey: .target); try c.encodeIfPresent(edgeMode, forKey: .edgeMode); try c.encodeIfPresent(preserveAlpha, forKey: .preserveAlpha)
        case .feDisplacementMap(_, let in2, let scale, let xSel, let ySel):
            try c.encode("feDisplacementMap", forKey: .type); try c.encode(in2, forKey: .in2); try c.encode(scale, forKey: .scale)
            try c.encodeIfPresent(xSel, forKey: .xChannelSelector); try c.encodeIfPresent(ySel, forKey: .yChannelSelector)
        case .feDropShadow(_, let dx, let dy, let stdDeviation, let floodColor, let floodOpacity):
            try c.encode("feDropShadow", forKey: .type); try c.encode(dx, forKey: .dx); try c.encode(dy, forKey: .dy)
            try c.encode(stdDeviation, forKey: .stdDeviation); try c.encode(floodColor, forKey: .floodColor); try c.encodeIfPresent(floodOpacity, forKey: .floodOpacity)
        case .feFlood(_, let color, let opacity):
            try c.encode("feFlood", forKey: .type); try c.encode(color, forKey: .color); try c.encodeIfPresent(opacity, forKey: .opacity)
        case .feGaussianBlur(_, let stdDeviation):
            try c.encode("feGaussianBlur", forKey: .type); try c.encode(stdDeviation, forKey: .stdDeviation)
        case .feImage(_, let href):
            try c.encode("feImage", forKey: .type); try c.encode(href, forKey: .href)
        case .feMerge(_, let nodes):
            try c.encode("feMerge", forKey: .type); try c.encode(nodes.map { NodeContainer(in: $0) }, forKey: .nodes)
        case .feMorphology(_, let operator_, let radius):
            try c.encode("feMorphology", forKey: .type); try c.encodeIfPresent(operator_, forKey: .operator_); try c.encode(radius, forKey: .radius)
        case .feOffset(_, let dx, let dy):
            try c.encode("feOffset", forKey: .type); try c.encode(dx, forKey: .dx); try c.encode(dy, forKey: .dy)
        case .feTile:
            try c.encode("feTile", forKey: .type)
        case .feTurbulence(_, let baseFrequency, let numOctaves, let seed, let stitchTiles, let noiseType):
            try c.encode("feTurbulence", forKey: .type); try c.encode(baseFrequency, forKey: .baseFrequency)
            try c.encodeIfPresent(numOctaves, forKey: .numOctaves); try c.encodeIfPresent(seed, forKey: .seed)
            try c.encodeIfPresent(stitchTiles, forKey: .stitchTiles); try c.encodeIfPresent(noiseType, forKey: .noiseType)
        case .feDiffuseLighting(_, let surfaceScale, let diffuseConstant, let kernelUnitLength, let lightingColor, let light):
            try c.encode("feDiffuseLighting", forKey: .type); try c.encode(surfaceScale, forKey: .surfaceScale); try c.encode(diffuseConstant, forKey: .diffuseConstant)
            try c.encodeIfPresent(kernelUnitLength, forKey: .kernelUnitLength); try c.encodeIfPresent(lightingColor, forKey: .lightingColor); try c.encode(light, forKey: .light)
        case .feSpecularLighting(_, let surfaceScale, let specularConstant, let specularExponent, let kernelUnitLength, let lightingColor, let light):
            try c.encode("feSpecularLighting", forKey: .type); try c.encode(surfaceScale, forKey: .surfaceScale)
            try c.encode(specularConstant, forKey: .specularConstant); try c.encode(specularExponent, forKey: .specularExponent)
            try c.encodeIfPresent(kernelUnitLength, forKey: .kernelUnitLength); try c.encodeIfPresent(lightingColor, forKey: .lightingColor); try c.encode(light, forKey: .light)
        }
    }
}

/// `filterUnits`/`primitiveUnits`/`colorInterpolationFilters` mirror Zod
/// `.default(...)` fields — optional here, caller applies the documented
/// fallback.
struct V2Filter: Codable {
    var id: String
    var x: V2SvgLength?
    var y: V2SvgLength?
    var width: V2SvgLength?
    var height: V2SvgLength?
    var filterUnits: V2FilterUnits?
    var primitiveUnits: V2FilterUnits?
    var colorInterpolationFilters: V2FilterColorInterpolation?
    var primitives: [V2FilterPrimitive]
    var tracks: [V2Track]?
}
