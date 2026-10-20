import CoreImage
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

// MARK: Chroma key experiment

/// Lab-only values. The experiment deliberately does not add a Protocol V2 primitive or persist to a project.
struct LabKeyColor: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    static let sampleGreen = LabKeyColor(red: 0.04, green: 0.75, blue: 0.28)

    var hex: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
}

struct LabChromaSettings: Equatable {
    var key = LabKeyColor.sampleGreen
    var intensity = 0.30
    var shadow = 0.0
    var feather = 0.25
    var cleanup = 0.0
}

enum LabChromaMethod: String, CaseIterable, Identifiable {
    case matrix = "Current V2"
    case v2Graph = "V2 graph"
    case colorCube = "Color cube"
    var id: String { rawValue }
}

/// Compares existing V2 primitives with a native Core Image color-cube candidate. CIColorCube makes a grayscale
/// matte from RGB, then CIBlendWithMask applies it to the picture; morphology contracts the matte. The experiment
/// routes its Color Cube candidate through the production Protocol V2 primitive and renderer.
enum LabChromaProcessor {
    private static let outputColorSpace = CGColorSpaceCreateDeviceRGB()

    static func render(_ source: CGImage, settings: LabChromaSettings, method: LabChromaMethod = .colorCube) -> CGImage? {
        if method == .matrix { return renderMatrix(source, settings: settings) }
        if method == .v2Graph { return renderV2Graph(source, settings: settings) }
        let base = V2FilterPrimitiveBase(id: "lab-chroma-key", in: "SourceGraphic", result: nil, region: nil, colorInterpolationFilters: nil)
        let primitive = V2FilterPrimitive.feChromaKey(
            base, keyColor: settings.key.hex, similarity: settings.intensity, smoothness: settings.feather,
            shadow: settings.shadow, edgeCleanup: settings.cleanup
        )
        let filter = V2Filter(id: "lab-color-cube", x: nil, y: nil, width: nil, height: nil, filterUnits: nil,
                              primitiveUnits: nil, colorInterpolationFilters: nil, primitives: [primitive], tracks: nil)
        return FilterRenderer.apply(filter, to: source)
    }

    /// The narrowest useful baseline made from the existing V2 graph: one feColorMatrix preserves RGB and writes
    /// alpha from the projection onto the picked chromatic direction. A matrix cannot model a bounded color range,
    /// darker screen shades, or spatial edge cleanup; those are exactly what this Lab compares against color-cube.
    private static func renderMatrix(_ source: CGImage, settings: LabChromaSettings) -> CGImage? {
        let key = settings.key
        let mean = (key.red + key.green + key.blue) / 3
        let dr = key.red - mean, dg = key.green - mean, db = key.blue - mean
        let lengthSquared = dr * dr + dg * dg + db * db
        guard lengthSquared > 0.005 else { return source }
        let width = 0.12 + settings.feather * 0.45
        let cutoff = 1.02 - settings.intensity * 0.25
        let factor = -1 / (lengthSquared * width)
        let base = V2FilterPrimitiveBase(id: "lab-key", in: "SourceGraphic", result: "keyed", region: nil, colorInterpolationFilters: nil)
        let matrix = [
            1.0, 0, 0, 0, 0,
            0, 1, 0, 0, 0,
            0, 0, 1, 0, 0,
            dr * factor, dg * factor, db * factor, 0, cutoff / width,
        ]
        let filter = V2Filter(id: "lab-matrix", x: nil, y: nil, width: nil, height: nil, filterUnits: nil,
                              primitiveUnits: nil, colorInterpolationFilters: nil,
                              primitives: [.feColorMatrix(base, kind: "matrix", values: matrix)], tracks: nil)
        return FilterRenderer.apply(filter, to: source)
    }

    /// Same chroma projection composed from two already-supported V2 primitives. The matrix keeps RGB intact and
    /// stores the unbounded key score in alpha; component transfer remaps that score to the soft matte. This tests
    /// whether composing current V2 operations changes the result without inventing a new primitive.
    private static func renderV2Graph(_ source: CGImage, settings: LabChromaSettings) -> CGImage? {
        let key = settings.key
        let mean = (key.red + key.green + key.blue) / 3
        let dr = key.red - mean, dg = key.green - mean, db = key.blue - mean
        let lengthSquared = dr * dr + dg * dg + db * db
        guard lengthSquared > 0.005 else { return source }

        let width = 0.12 + settings.feather * 0.45
        let cutoff = 1.02 - settings.intensity * 0.25
        let base = V2FilterPrimitiveBase(id: "lab-key-score", in: "SourceGraphic", result: "score", region: nil, colorInterpolationFilters: nil)
        let score = V2FilterPrimitive.feColorMatrix(base, kind: "matrix", values: [
            1, 0, 0, 0, 0,
            0, 1, 0, 0, 0,
            0, 0, 1, 0, 0,
            -dr / lengthSquared, -dg / lengthSquared, -db / lengthSquared, 0, 1,
        ])
        let remapBase = V2FilterPrimitiveBase(id: "lab-key-remap", in: "score", result: "keyed", region: nil, colorInterpolationFilters: nil)
        let remap = V2FilterPrimitive.feComponentTransfer(
            remapBase,
            functions: V2ComponentTransferFunctions(r: nil, g: nil, b: nil,
                                                    a: .linear(slope: 1 / width, intercept: (cutoff - 1) / width))
        )
        let filter = V2Filter(id: "lab-v2-key", x: nil, y: nil, width: nil, height: nil, filterUnits: nil,
                              primitiveUnits: nil, colorInterpolationFilters: nil,
                              primitives: [score, remap], tracks: nil)
        return FilterRenderer.apply(filter, to: source)
    }

    /// Sample a small patch, so a single noisy pixel does not become the whole key color.
    static func color(in source: CGImage, at point: CGPoint) -> LabKeyColor? {
        let x = min(max(Int(point.x * CGFloat(source.width)), 0), source.width - 1)
        let y = min(max(Int(point.y * CGFloat(source.height)), 0), source.height - 1)
        let rect = CGRect(x: max(0, x - 2), y: max(0, y - 2), width: min(5, source.width - max(0, x - 2)), height: min(5, source.height - max(0, y - 2)))
        guard let patch = source.cropping(to: rect) else { return nil }
        let width = patch.width, height = patch.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let bitmap = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                     space: outputColorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        bitmap.draw(patch, in: CGRect(x: 0, y: 0, width: width, height: height))
        var r = 0.0, g = 0.0, b = 0.0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            r += Double(bytes[i]); g += Double(bytes[i + 1]); b += Double(bytes[i + 2])
        }
        let divisor = Double(width * height * 255)
        return LabKeyColor(red: r / divisor, green: g / divisor, blue: b / divisor)
    }

    static func sampleImage() -> CGImage? {
        let size = CGSize(width: 540, height: 800)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let canvas = CGRect(origin: .zero, size: size)
            UIColor(red: 0.04, green: 0.75, blue: 0.28, alpha: 1).setFill()
            renderer.fill(canvas)
            UIColor(red: 0.025, green: 0.48, blue: 0.17, alpha: 1).setFill()
            renderer.cgContext.fillEllipse(in: CGRect(x: 55, y: 400, width: 380, height: 310))
            UIColor(red: 0.11, green: 0.26, blue: 0.60, alpha: 1).setFill()
            renderer.cgContext.fillEllipse(in: CGRect(x: 110, y: 430, width: 330, height: 500))
            UIColor(red: 0.87, green: 0.60, blue: 0.40, alpha: 1).setFill()
            renderer.cgContext.fillEllipse(in: CGRect(x: 160, y: 210, width: 225, height: 290))
            UIColor(red: 0.12, green: 0.13, blue: 0.14, alpha: 1).setFill()
            renderer.cgContext.fillEllipse(in: CGRect(x: 150, y: 175, width: 240, height: 115))
            UIColor(red: 0.97, green: 0.82, blue: 0.22, alpha: 1).setFill()
            renderer.cgContext.fillEllipse(in: CGRect(x: 345, y: 520, width: 95, height: 95))
        }
        return image.cgImage
    }
}
