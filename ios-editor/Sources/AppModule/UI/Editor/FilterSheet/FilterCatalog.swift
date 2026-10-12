import Foundation

/// The Filter tool's presets (user 2026-10-12): a filter is a **named bundle of Adjust values**, scaled by an Intensity
/// and compiled through the same chain as the Adjust sliders (`SetAdjustCommand`). No LUT files: a bundle can only do
/// global tone and colour work (no per-hue shifts), which is enough for the basic looks; `.cube` support can come later.
enum FilterCategory: String, CaseIterable, Identifiable {
    case all = "All", basic = "Basic", film = "Film", blackAndWhite = "B&W", vintage = "Vintage"
    var id: String { rawValue }
}

struct FilterPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let category: FilterCategory
    /// The look at full strength.
    let values: AdjustValues
}

/// The filter picked for a clip and how strongly (0...1). Session state, like `adjustIntents`: the persisted result is the
/// compiled filter chain on the layer.
struct AppliedFilter: Equatable {
    var id: String
    var intensity: Double = 1
}

extension AdjustValues {
    /// These values at strength `t` (0 = neutral, 1 = unchanged): every number moves linearly from its neutral value.
    func scaled(_ t: Double) -> AdjustValues {
        let t = min(max(t, 0), 1)
        let neutral = AdjustValues()
        func mix(_ base: Double, _ value: Double) -> Double { base + (value - base) * t }
        var result = AdjustValues()
        result.exposure = mix(neutral.exposure, exposure)
        result.brilliance = mix(neutral.brilliance, brilliance)
        result.highlights = mix(neutral.highlights, highlights)
        result.shadows = mix(neutral.shadows, shadows)
        result.contrast = mix(neutral.contrast, contrast)
        result.brightness = mix(neutral.brightness, brightness)
        result.blackPoint = mix(neutral.blackPoint, blackPoint)
        result.saturation = mix(neutral.saturation, saturation)
        result.vibrance = mix(neutral.vibrance, vibrance)
        result.temperature = mix(neutral.temperature, temperature)
        result.hue = mix(neutral.hue, hue)
        result.tint = mix(neutral.tint, tint)
        result.vignette = mix(neutral.vignette, vignette)
        result.sharpen = mix(neutral.sharpen, sharpen)
        result.clarity = mix(neutral.clarity, clarity)
        result.noise = mix(neutral.noise, noise)
        result.curvePoints = zip(neutral.curvePoints, curvePoints).map { mix($0, $1) }
        return result
    }
}

enum FilterCatalog {
    /// In display order. The values are judgement calls, tuned by eye; adjust them freely.
    static let presets: [FilterPreset] = [
        FilterPreset(id: "warm", name: "Warm", category: .basic, values: AdjustValues(contrast: 1.05, brightness: 0.04, saturation: 1.1, temperature: 0.35)),
        FilterPreset(id: "cool", name: "Cool", category: .basic, values: AdjustValues(contrast: 1.05, saturation: 1.05, temperature: -0.35)),
        FilterPreset(id: "vivid", name: "Vivid", category: .basic, values: AdjustValues(contrast: 1.12, saturation: 1.4, vibrance: 0.3)),
        FilterPreset(id: "soft", name: "Soft", category: .basic, values: AdjustValues(highlights: -0.2, shadows: 0.15, contrast: 0.88, brightness: 0.1, clarity: -0.25)),
        FilterPreset(id: "crisp", name: "Crisp", category: .basic, values: AdjustValues(contrast: 1.22, saturation: 1.08, sharpen: 0.35, clarity: 0.3)),
        FilterPreset(id: "film400", name: "Film 400", category: .film, values: AdjustValues(highlights: -0.1, contrast: 1.12, blackPoint: -0.18, saturation: 0.85, temperature: 0.15, vignette: 0.5, noise: 0.15)),
        FilterPreset(id: "warm-roll", name: "Warm Roll", category: .film, values: AdjustValues(contrast: 1.1, blackPoint: -0.1, saturation: 1.2, temperature: 0.3, vignette: 0.4)),
        FilterPreset(id: "green-roll", name: "Green Roll", category: .film, values: AdjustValues(contrast: 1.08, saturation: 1.1, hue: -6, tint: 0.25, vignette: 0.3)),
        FilterPreset(id: "cinema", name: "Cinema", category: .film, values: AdjustValues(highlights: -0.1, shadows: -0.2, contrast: 1.2, saturation: 1.1, temperature: 0.12, tint: -0.05, vignette: 0.5)),
        FilterPreset(id: "mono", name: "Mono", category: .blackAndWhite, values: AdjustValues(contrast: 1.1, saturation: 0)),
        FilterPreset(id: "noir", name: "Noir", category: .blackAndWhite, values: AdjustValues(contrast: 1.45, brightness: -0.1, blackPoint: 0.3, saturation: 0, vignette: 0.9)),
        FilterPreset(id: "silver", name: "Silver", category: .blackAndWhite, values: AdjustValues(highlights: -0.1, contrast: 0.9, brightness: 0.1, saturation: 0)),
        FilterPreset(id: "fade", name: "Fade", category: .vintage, values: AdjustValues(contrast: 0.85, brightness: 0.05, blackPoint: -0.45, saturation: 0.8)),
        FilterPreset(id: "retro", name: "Retro", category: .vintage, values: AdjustValues(contrast: 0.95, blackPoint: -0.3, saturation: 0.75, temperature: 0.25, hue: 5, vignette: 0.6)),
        FilterPreset(id: "sepia", name: "Sepia", category: .vintage, values: AdjustValues(saturation: 0.4, temperature: 0.5, tint: 0.08, vignette: 0.4)),
        FilterPreset(id: "dream", name: "Dream", category: .vintage, values: AdjustValues(highlights: -0.15, contrast: 0.88, brightness: 0.1, saturation: 1.1, temperature: 0.05, tint: -0.15, clarity: -0.35)),
    ]

    static func list(in category: FilterCategory) -> [FilterPreset] {
        presets.filter { category == .all || $0.category == category }
    }

    static func preset(id: String) -> FilterPreset? { presets.first { $0.id == id } }
}
