import SwiftUI

/// Fake filters for the Filter lab: each is a *look* (a handful of SwiftUI-expressible numbers) so the grid, the stage
/// and the Intensity ruler can be judged on a real photo. The real filters will be named bundles of Adjust values.
enum LabFilterCategory: String, CaseIterable, Identifiable {
    case all = "All", basic = "Basic", film = "Film", blackAndWhite = "B&W", vintage = "Vintage"
    var id: String { rawValue }
}

/// What a filter does at full strength; `LabFilterLook` scales it by the Intensity (0...1).
struct LabFilterValues: Equatable {
    var brightness = 0.0      // SwiftUI `.brightness`
    var contrast = 1.0
    var saturation = 1.0
    var hue = 0.0             // degrees
    var tint: Color = .clear  // overlaid in `.overlay` blend
    var tintOpacity = 0.0
    var vignette = 0.0

    /// The same filter at strength `t` (0 = neutral, 1 = full): each number moves linearly from its neutral value.
    func scaled(_ t: Double) -> LabFilterValues {
        let t = min(max(t, 0), 1)
        return LabFilterValues(
            brightness: brightness * t, contrast: 1 + (contrast - 1) * t, saturation: 1 + (saturation - 1) * t,
            hue: hue * t, tint: tint, tintOpacity: tintOpacity * t, vignette: vignette * t
        )
    }
}

struct LabFilter: Identifiable, Equatable {
    let id: String
    let name: String
    let category: LabFilterCategory
    let values: LabFilterValues

    static let none = LabFilter(id: "none", name: "None", category: .all, values: LabFilterValues())

    /// Everything after `none`, in display order.
    static let catalogue: [LabFilter] = [
        LabFilter(id: "warm", name: "Warm", category: .basic, values: .init(brightness: 0.03, contrast: 1.05, saturation: 1.1, tint: Color(red: 1, green: 0.6, blue: 0.2), tintOpacity: 0.28)),
        LabFilter(id: "cool", name: "Cool", category: .basic, values: .init(contrast: 1.05, saturation: 1.05, tint: Color(red: 0.2, green: 0.5, blue: 1), tintOpacity: 0.28)),
        LabFilter(id: "vivid", name: "Vivid", category: .basic, values: .init(contrast: 1.15, saturation: 1.45)),
        LabFilter(id: "soft", name: "Soft", category: .basic, values: .init(brightness: 0.05, contrast: 0.85, saturation: 0.9)),
        LabFilter(id: "crisp", name: "Crisp", category: .basic, values: .init(contrast: 1.3, saturation: 1.1)),
        LabFilter(id: "film400", name: "Film 400", category: .film, values: .init(contrast: 1.12, saturation: 0.85, tint: Color(red: 0.9, green: 0.7, blue: 0.4), tintOpacity: 0.14, vignette: 0.35)),
        LabFilter(id: "kodak", name: "Warm Roll", category: .film, values: .init(brightness: 0.02, contrast: 1.1, saturation: 1.2, tint: Color(red: 1, green: 0.55, blue: 0.25), tintOpacity: 0.2, vignette: 0.25)),
        LabFilter(id: "fuji", name: "Green Roll", category: .film, values: .init(contrast: 1.08, saturation: 1.1, hue: -8, tint: Color(red: 0.3, green: 0.8, blue: 0.5), tintOpacity: 0.12, vignette: 0.2)),
        LabFilter(id: "cinema", name: "Teal Orange", category: .film, values: .init(contrast: 1.18, saturation: 1.15, tint: Color(red: 0.1, green: 0.55, blue: 0.7), tintOpacity: 0.22, vignette: 0.3)),
        LabFilter(id: "mono", name: "Mono", category: .blackAndWhite, values: .init(contrast: 1.1, saturation: 0)),
        LabFilter(id: "noir", name: "Noir", category: .blackAndWhite, values: .init(brightness: -0.04, contrast: 1.45, saturation: 0, vignette: 0.45)),
        LabFilter(id: "silver", name: "Silver", category: .blackAndWhite, values: .init(brightness: 0.06, contrast: 0.9, saturation: 0)),
        LabFilter(id: "fade", name: "Fade", category: .vintage, values: .init(brightness: 0.08, contrast: 0.78, saturation: 0.8)),
        LabFilter(id: "retro", name: "Retro", category: .vintage, values: .init(brightness: 0.03, contrast: 0.95, saturation: 0.75, hue: 6, tint: Color(red: 1, green: 0.8, blue: 0.5), tintOpacity: 0.22, vignette: 0.3)),
        LabFilter(id: "sepia", name: "Sepia", category: .vintage, values: .init(contrast: 1.0, saturation: 0.35, tint: Color(red: 0.75, green: 0.5, blue: 0.2), tintOpacity: 0.4, vignette: 0.2)),
        LabFilter(id: "dream", name: "Dream", category: .vintage, values: .init(brightness: 0.06, contrast: 0.88, saturation: 1.1, hue: -10, tint: Color(red: 1, green: 0.6, blue: 0.85), tintOpacity: 0.16)),
    ]

    /// `none` first, then the catalogue (or just one category of it).
    static func list(in category: LabFilterCategory) -> [LabFilter] {
        [none] + catalogue.filter { category == .all || $0.category == category }
    }
}

/// Applies a filter's values at `intensity` (0 = the original photo, 1 = full). Every value moves linearly from its
/// neutral one, which is also how the real filters (bundles of Adjust values) will be scaled.
struct LabFilterLook: ViewModifier {
    let filter: LabFilter
    let intensity: Double

    func body(content: Content) -> some View {
        let v = filter.values.scaled(intensity)
        content
            .brightness(v.brightness)
            .contrast(v.contrast)
            .saturation(v.saturation)
            .hueRotation(.degrees(v.hue))
            .overlay(v.tint.opacity(v.tintOpacity).blendMode(.overlay).allowsHitTesting(false))
            .overlay(
                RadialGradient(colors: [.clear, .black.opacity(v.vignette)], center: .center, startRadius: 20, endRadius: 260)
                    .allowsHitTesting(false)
            )
    }
}

extension View {
    func labFilterLook(_ filter: LabFilter, intensity: Double) -> some View { modifier(LabFilterLook(filter: filter, intensity: intensity)) }
}
