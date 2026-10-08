import Foundation

// The Editor-tier counterpart to the old Protocol-level `V2Effect` (ported
// from effects.ts, then removed from Protocol/ — see CLAUDE.md's "Protocol
// V2 stays atomic" rule). A named effect (glow, blur, sepia, ...) is editor
// authoring intent; `filterPrimitives(for:idPrefix:input:)` is the compiler
// step expanding it into a real `V2FilterPrimitive` chain, exactly mirroring
// how `PresetCompiler.swift` expands an animation preset into keyframe
// tracks. Multiple stacked presets on one layer chain sequentially — preset
// N+1 reads preset N's output, matching CSS `filter: a(...) b(...)` list
// semantics.
//
// These primitive graphs are reasonable, best-effort constructions (the
// well-known SVG techniques for drop-shadow/glow/sepia etc.), not verified
// against an actual filter renderer — this app doesn't have an SVG filter
// rendering engine yet, a known, separate gap from the architecture change
// itself (see CLAUDE.md).

enum EffectPresetKind: Codable {
    case colorAdjust(brightness: Double, contrast: Double, saturation: Double, hueRotate: Double)
    case grayscale(amount: Double)
    case sepia(amount: Double)
    case invert(amount: Double)
    case filterOpacity(amount: Double)
    case blur(radius: Double)
    case shadow(offset: V2Vec2, blur: Double, spread: Double, color: V2Color, inset: Bool)
    case outerGlow(radius: Double, color: V2Color, opacity: Double)
    case innerGlow(radius: Double, color: V2Color, opacity: Double)
    case noise(scale: Double, amount: Double, opacity: Double, seed: Int)

    private enum CodingKeys: String, CodingKey {
        case kind, brightness, contrast, saturation, hueRotate, amount, radius
        case offset, blur, spread, color, inset, opacity, scale, seed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "colorAdjust":
            self = .colorAdjust(
                brightness: try c.decode(Double.self, forKey: .brightness), contrast: try c.decode(Double.self, forKey: .contrast),
                saturation: try c.decode(Double.self, forKey: .saturation), hueRotate: try c.decode(Double.self, forKey: .hueRotate)
            )
        case "grayscale": self = .grayscale(amount: try c.decode(Double.self, forKey: .amount))
        case "sepia": self = .sepia(amount: try c.decode(Double.self, forKey: .amount))
        case "invert": self = .invert(amount: try c.decode(Double.self, forKey: .amount))
        case "filterOpacity": self = .filterOpacity(amount: try c.decode(Double.self, forKey: .amount))
        case "blur": self = .blur(radius: try c.decode(Double.self, forKey: .radius))
        case "shadow":
            self = .shadow(
                offset: try c.decode(V2Vec2.self, forKey: .offset), blur: try c.decode(Double.self, forKey: .blur),
                spread: try c.decode(Double.self, forKey: .spread), color: try c.decode(V2Color.self, forKey: .color),
                inset: try c.decode(Bool.self, forKey: .inset)
            )
        case "outerGlow":
            self = .outerGlow(radius: try c.decode(Double.self, forKey: .radius), color: try c.decode(V2Color.self, forKey: .color), opacity: try c.decode(Double.self, forKey: .opacity))
        case "innerGlow":
            self = .innerGlow(radius: try c.decode(Double.self, forKey: .radius), color: try c.decode(V2Color.self, forKey: .color), opacity: try c.decode(Double.self, forKey: .opacity))
        case "noise":
            self = .noise(
                scale: try c.decode(Double.self, forKey: .scale), amount: try c.decode(Double.self, forKey: .amount),
                opacity: try c.decode(Double.self, forKey: .opacity), seed: try c.decode(Int.self, forKey: .seed)
            )
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "Unknown effect preset: \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .colorAdjust(let brightness, let contrast, let saturation, let hueRotate):
            try c.encode("colorAdjust", forKey: .kind)
            try c.encode(brightness, forKey: .brightness); try c.encode(contrast, forKey: .contrast)
            try c.encode(saturation, forKey: .saturation); try c.encode(hueRotate, forKey: .hueRotate)
        case .grayscale(let amount): try c.encode("grayscale", forKey: .kind); try c.encode(amount, forKey: .amount)
        case .sepia(let amount): try c.encode("sepia", forKey: .kind); try c.encode(amount, forKey: .amount)
        case .invert(let amount): try c.encode("invert", forKey: .kind); try c.encode(amount, forKey: .amount)
        case .filterOpacity(let amount): try c.encode("filterOpacity", forKey: .kind); try c.encode(amount, forKey: .amount)
        case .blur(let radius): try c.encode("blur", forKey: .kind); try c.encode(radius, forKey: .radius)
        case .shadow(let offset, let blur, let spread, let color, let inset):
            try c.encode("shadow", forKey: .kind)
            try c.encode(offset, forKey: .offset); try c.encode(blur, forKey: .blur)
            try c.encode(spread, forKey: .spread); try c.encode(color, forKey: .color); try c.encode(inset, forKey: .inset)
        case .outerGlow(let radius, let color, let opacity):
            try c.encode("outerGlow", forKey: .kind); try c.encode(radius, forKey: .radius); try c.encode(color, forKey: .color); try c.encode(opacity, forKey: .opacity)
        case .innerGlow(let radius, let color, let opacity):
            try c.encode("innerGlow", forKey: .kind); try c.encode(radius, forKey: .radius); try c.encode(color, forKey: .color); try c.encode(opacity, forKey: .opacity)
        case .noise(let scale, let amount, let opacity, let seed):
            try c.encode("noise", forKey: .kind)
            try c.encode(scale, forKey: .scale); try c.encode(amount, forKey: .amount); try c.encode(opacity, forKey: .opacity); try c.encode(seed, forKey: .seed)
        }
    }
}

/// Expands one effect preset into its primitive chain. `input` is the SVG
/// filter `in` reference to read from — `"SourceGraphic"` for the first
/// preset on a layer, or the previous preset's `output` when stacking.
/// Returns the chain plus the `result` name of its final primitive, so the
/// caller can feed it as the next preset's `input`.
func filterPrimitives(for kind: EffectPresetKind, idPrefix: String, input: String) -> (primitives: [V2FilterPrimitive], output: String) {
    func base(_ suffix: String, in input: String) -> V2FilterPrimitiveBase {
        V2FilterPrimitiveBase(id: "\(idPrefix)-\(suffix)", in: input, result: "\(idPrefix)-\(suffix)", region: nil, colorInterpolationFilters: nil)
    }

    switch kind {
    case .blur(let radius):
        let b = base("blur", in: input)
        return ([.feGaussianBlur(b, stdDeviation: V2FilterStdDeviation(x: radius, y: radius))], b.result!)

    case .grayscale(let amount):
        let b = base("grayscale", in: input)
        return ([.feColorMatrix(b, kind: "saturate", values: [1 - amount])], b.result!)

    case .sepia(let amount):
        // Standard CSS sepia() color matrix, lerped from identity by `amount`.
        let a = amount
        let values: [Double] = [
            0.393 + 0.607 * (1 - a), 0.769 - 0.769 * (1 - a), 0.189 - 0.189 * (1 - a), 0, 0,
            0.349 - 0.349 * (1 - a), 0.686 + 0.314 * (1 - a), 0.168 - 0.168 * (1 - a), 0, 0,
            0.272 - 0.272 * (1 - a), 0.534 - 0.534 * (1 - a), 0.131 + 0.869 * (1 - a), 0, 0,
            0, 0, 0, 1, 0,
        ]
        let b = base("sepia", in: input)
        return ([.feColorMatrix(b, kind: "matrix", values: values)], b.result!)

    case .invert(let amount):
        let table: [Double] = [amount, 1 - amount]
        let functions = V2ComponentTransferFunctions(
            r: .table(values: table), g: .table(values: table), b: .table(values: table), a: nil
        )
        let b = base("invert", in: input)
        return ([.feComponentTransfer(b, functions: functions)], b.result!)

    case .filterOpacity(let amount):
        let functions = V2ComponentTransferFunctions(r: nil, g: nil, b: nil, a: .linear(slope: amount, intercept: 0))
        let b = base("opacity", in: input)
        return ([.feComponentTransfer(b, functions: functions)], b.result!)

    case .colorAdjust(let brightness, let contrast, let saturation, let hueRotate):
        let hue = base("hue", in: input)
        let sat = base("sat", in: hue.result!)
        let tone = base("tone", in: sat.result!)
        let toneFunctions = V2ComponentTransferFunctions(
            r: .linear(slope: contrast, intercept: brightness + 0.5 * (1 - contrast)),
            g: .linear(slope: contrast, intercept: brightness + 0.5 * (1 - contrast)),
            b: .linear(slope: contrast, intercept: brightness + 0.5 * (1 - contrast)),
            a: nil
        )
        return (
            [
                .feColorMatrix(hue, kind: "hueRotate", values: [hueRotate]),
                .feColorMatrix(sat, kind: "saturate", values: [saturation]),
                .feComponentTransfer(tone, functions: toneFunctions),
            ],
            tone.result!
        )

    case .shadow(let offset, let blurRadius, let spread, let color, _):
        // `inset` is a known simplification — always an outer/drop shadow
        // here; real inset compositing needs an inverted mask, not built yet.
        //
        // No `spread`: `feDropShadow` is a built-in macro primitive for
        // exactly this (blur+offset+flood+composite in one step, already
        // merged with its own input — no separate feMerge needed).
        // `spread` needs `feMorphology` first, which `feDropShadow` has no
        // room for, so that case falls back to the manual primitive chain.
        guard spread != 0 else {
            let dropShadowBase = base("shadow", in: input)
            return ([.feDropShadow(dropShadowBase, dx: offset.x, dy: offset.y, stdDeviation: V2FilterStdDeviation(x: blurRadius, y: blurRadius), floodColor: color, floodOpacity: nil)], dropShadowBase.result!)
        }
        let offsetBase = base("shadow-offset", in: input)
        let spreadBase = base("shadow-spread", in: offsetBase.result!)
        let blurBase = base("shadow-blur", in: spreadBase.result!)
        let floodBase = base("shadow-flood", in: blurBase.result!)
        let compositeBase = base("shadow-clip", in: floodBase.result!)
        let mergeBase = base("shadow-merge", in: input)
        return (
            [
                .feOffset(offsetBase, dx: offset.x, dy: offset.y),
                .feMorphology(spreadBase, operator_: spread > 0 ? "dilate" : "erode", radius: V2XY(x: abs(spread), y: abs(spread))),
                .feGaussianBlur(blurBase, stdDeviation: V2FilterStdDeviation(x: blurRadius, y: blurRadius)),
                .feFlood(floodBase, color: color, opacity: nil),
                .feComposite(compositeBase, in2: blurBase.result!, operator_: "in", k1: nil, k2: nil, k3: nil, k4: nil),
                .feMerge(mergeBase, nodes: [compositeBase.result!, input]),
            ],
            mergeBase.result!
        )

    case .outerGlow(let radius, let color, let opacity):
        let blurBase = base("glow-blur", in: input)
        let floodBase = base("glow-flood", in: blurBase.result!)
        let compositeBase = base("glow-clip", in: floodBase.result!)
        let mergeBase = base("glow-merge", in: input)
        return (
            [
                .feGaussianBlur(blurBase, stdDeviation: V2FilterStdDeviation(x: radius, y: radius)),
                .feFlood(floodBase, color: color, opacity: opacity),
                .feComposite(compositeBase, in2: blurBase.result!, operator_: "in", k1: nil, k2: nil, k3: nil, k4: nil),
                .feMerge(mergeBase, nodes: [compositeBase.result!, input]),
            ],
            mergeBase.result!
        )

    case .innerGlow(let radius, let color, let opacity):
        let floodBase = base("iglow-flood", in: input)
        let clip1Base = base("iglow-clip1", in: floodBase.result!)
        let blurBase = base("iglow-blur", in: clip1Base.result!)
        let clip2Base = base("iglow-clip2", in: blurBase.result!)
        let mergeBase = base("iglow-merge", in: input)
        return (
            [
                .feFlood(floodBase, color: color, opacity: opacity),
                .feComposite(clip1Base, in2: input, operator_: "in", k1: nil, k2: nil, k3: nil, k4: nil),
                .feGaussianBlur(blurBase, stdDeviation: V2FilterStdDeviation(x: radius, y: radius)),
                .feComposite(clip2Base, in2: input, operator_: "in", k1: nil, k2: nil, k3: nil, k4: nil),
                .feMerge(mergeBase, nodes: [input, clip2Base.result!]),
            ],
            mergeBase.result!
        )

    case .noise(let scale, let amount, let opacity, let seed):
        let turbulenceBase = base("noise-turbulence", in: input)
        let toneBase = base("noise-tone", in: turbulenceBase.result!)
        let mergeBase = base("noise-merge", in: input)
        return (
            [
                .feTurbulence(turbulenceBase, baseFrequency: V2XY(x: 1 / max(scale, 1), y: 1 / max(scale, 1)), numOctaves: 1, seed: Double(seed), stitchTiles: nil, noiseType: "fractalNoise"),
                .feComponentTransfer(toneBase, functions: V2ComponentTransferFunctions(r: nil, g: nil, b: nil, a: .linear(slope: amount * opacity, intercept: 0))),
                .feMerge(mergeBase, nodes: [input, toneBase.result!]),
            ],
            mergeBase.result!
        )
    }
}

/// Compiles every effect preset stacked on one layer into a single `V2Filter`
/// definition (chained sequentially, matching CSS `filter: a(...) b(...)`
/// list semantics), to be added to the project's root `filters[]` and
/// referenced from the layer via `filter`/`backdropFilter`.
func compileFilter(id: String, presets: [EffectPresetKind]) -> V2Filter {
    var primitives: [V2FilterPrimitive] = []
    var input = "SourceGraphic"
    for (index, preset) in presets.enumerated() {
        let (chain, output) = filterPrimitives(for: preset, idPrefix: "\(id)-\(index)", input: input)
        primitives.append(contentsOf: chain)
        input = output
    }
    return V2Filter(id: id, x: nil, y: nil, width: nil, height: nil, filterUnits: nil, primitiveUnits: nil, colorInterpolationFilters: nil, primitives: primitives, tracks: nil)
}
