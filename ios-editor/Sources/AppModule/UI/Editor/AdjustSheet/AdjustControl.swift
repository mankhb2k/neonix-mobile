import SwiftUI

/// The Adjust tool's 16 scalar controls (Curves keeps its own graph editor), grouped like the Photos app, with the
/// ruler configuration and the readout of each. Shared by the editor's `AdjustSheet` and the Design Lab.
/// List and order set by the user 2026-10-12: Exposure, Brilliance, Highlights, Shadows, Contrast, Brightness, Black
/// point, Saturation, Vibrance, Temperature, Hue, Tint, Vignette, Sharpen, Clarity, Noise (Blur moved to Effects).
enum AdjustGroup: String, CaseIterable, Identifiable {
    case light = "Light", color = "Color", detail = "Detail"
    var id: String { rawValue }
}

enum AdjustControl: String, CaseIterable, Identifiable {
    case exposure, brilliance, highlights, shadows, contrast, brightness, blackPoint
    case saturation, vibrance, temperature, hue, tint
    case vignette, sharpen, clarity, noise

    var id: String { rawValue }

    var group: AdjustGroup {
        switch self {
        case .exposure, .brilliance, .highlights, .shadows, .contrast, .brightness, .blackPoint: return .light
        case .saturation, .vibrance, .temperature, .hue, .tint: return .color
        case .vignette, .sharpen, .clarity, .noise: return .detail
        }
    }

    var title: String {
        if self == .blackPoint { return "Black point" }
        return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    /// Where this control's value lives in the real `AdjustValues` (what `SetAdjustCommand` compiles).
    var keyPath: WritableKeyPath<AdjustValues, Double> {
        switch self {
        case .exposure: return \.exposure
        case .brilliance: return \.brilliance
        case .highlights: return \.highlights
        case .shadows: return \.shadows
        case .contrast: return \.contrast
        case .brightness: return \.brightness
        case .blackPoint: return \.blackPoint
        case .saturation: return \.saturation
        case .vibrance: return \.vibrance
        case .temperature: return \.temperature
        case .hue: return \.hue
        case .tint: return \.tint
        case .vignette: return \.vignette
        case .sharpen: return \.sharpen
        case .clarity: return \.clarity
        case .noise: return \.noise
        }
    }

    var symbol: String {
        switch self {
        case .exposure: return "plusminus.circle"
        case .brilliance: return "sparkle"
        case .highlights: return "circle.tophalf.filled"
        case .shadows: return "circle.bottomhalf.filled"
        case .contrast: return "circle.lefthalf.filled"
        case .brightness: return "sun.max"
        case .blackPoint: return "circle.fill"
        case .saturation: return "drop"
        case .vibrance: return "sparkles"
        case .temperature: return "thermometer.medium"
        case .hue: return "paintpalette"
        case .tint: return "eyedropper"
        case .vignette: return "smallcircle.filled.circle"
        case .sharpen: return "triangle"
        case .clarity: return "diamond"
        case .noise: return "circle.grid.3x3"
        }
    }

    var neutral: Double {
        switch self {
        case .contrast, .saturation: return 1
        default: return 0
        }
    }

    var mapping: RulerMapping {
        switch self {
        case .exposure: return .linear(-2...2, step: 0.05, majorEvery: 10)
        case .brilliance, .highlights, .shadows, .brightness, .blackPoint, .vibrance, .temperature, .tint, .clarity:
            return .linear(-1...1, step: 0.02, majorEvery: 10)
        case .contrast: return .linear(0.5...1.5, step: 0.01, majorEvery: 10)
        case .saturation: return .linear(0...2, step: 0.02, majorEvery: 10)
        case .hue: return .linear(-180...180, step: 1, majorEvery: 30)
        case .sharpen, .noise: return .linear(0...1, step: 0.01, majorEvery: 10)
        case .vignette: return .linear(0...2, step: 0.02, majorEvery: 10)
        }
    }

    /// Photos-style readout: centred controls read -100...+100 around neutral.
    func display(_ value: Double) -> String {
        func signed(_ x: Double, _ decimals: Int = 0) -> String {
            let rounded = (x * pow(10, Double(decimals))).rounded() / pow(10, Double(decimals))
            return rounded == 0 ? "0" : String(format: "%+.\(decimals)f", rounded)
        }
        switch self {
        case .brilliance, .highlights, .shadows, .brightness, .blackPoint, .vibrance, .temperature, .tint, .clarity:
            return signed(value * 100)
        case .contrast: return signed((value - 1) * 200)
        case .saturation: return signed((value - 1) * 100)
        case .exposure: return signed(value, 1)
        case .hue: return signed(value) == "0" ? "0°" : signed(value) + "°"
        case .sharpen, .noise: return String(format: "%.0f", value * 100)
        case .vignette: return String(format: "%.0f", value * 50)
        }
    }
}

extension AdjustValues {
    func isChanged(_ control: AdjustControl) -> Bool { abs(self[keyPath: control.keyPath] - control.neutral) > 0.0001 }
    var curvesChanged: Bool { curvePoints != AdjustValues().curvePoints }
}
