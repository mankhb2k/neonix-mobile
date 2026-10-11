import SwiftUI

/// The Adjust tool's 13 scalar controls (Curves keeps its own graph editor), grouped like the Photos app, with the ruler
/// configuration and the readout of each. Shared by the editor's `AdjustSheet` and the Design Lab.
enum AdjustGroup: String, CaseIterable, Identifiable {
    case light = "Light", color = "Color", detail = "Detail"
    var id: String { rawValue }
}

enum AdjustControl: String, CaseIterable, Identifiable {
    case brightness, contrast, exposure, lightness
    case saturation, hue, temperature, tint
    case sharpen, clarity, blur, vignette, noise

    var id: String { rawValue }

    var group: AdjustGroup {
        switch self {
        case .brightness, .contrast, .exposure, .lightness: return .light
        case .saturation, .hue, .temperature, .tint: return .color
        case .sharpen, .clarity, .blur, .vignette, .noise: return .detail
        }
    }

    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// Where this control's value lives in the real `AdjustValues` (what `SetAdjustCommand` compiles).
    var keyPath: WritableKeyPath<AdjustValues, Double> {
        switch self {
        case .brightness: return \.brightness
        case .contrast: return \.contrast
        case .exposure: return \.exposure
        case .lightness: return \.lightness
        case .saturation: return \.saturation
        case .hue: return \.hue
        case .temperature: return \.temperature
        case .tint: return \.tint
        case .sharpen: return \.sharpen
        case .clarity: return \.clarity
        case .blur: return \.blur
        case .vignette: return \.vignette
        case .noise: return \.noise
        }
    }

    var symbol: String {
        switch self {
        case .brightness: return "sun.max"
        case .contrast: return "circle.lefthalf.filled"
        case .exposure: return "plusminus.circle"
        case .lightness: return "sun.min"
        case .saturation: return "drop"
        case .hue: return "paintpalette"
        case .temperature: return "thermometer.medium"
        case .tint: return "eyedropper"
        case .sharpen: return "triangle"
        case .clarity: return "diamond"
        case .blur: return "circle.dotted"
        case .vignette: return "smallcircle.filled.circle"
        case .noise: return "circle.grid.3x3"
        }
    }

    var neutral: Double {
        switch self {
        case .contrast, .saturation: return 1
        default: return 0
        }
    }

    /// Same ranges as the editor's Adjust sliders.
    var mapping: RulerMapping {
        switch self {
        case .brightness, .lightness: return .linear(-0.5...0.5, step: 0.01, majorEvery: 10)
        case .contrast: return .linear(0.5...1.5, step: 0.01, majorEvery: 10)
        case .exposure: return .linear(-2...2, step: 0.05, majorEvery: 10)
        case .saturation: return .linear(0...2, step: 0.02, majorEvery: 10)
        case .hue: return .linear(-180...180, step: 1, majorEvery: 30)
        case .temperature, .tint, .clarity: return .linear(-1...1, step: 0.02, majorEvery: 10)
        case .sharpen, .noise: return .linear(0...1, step: 0.01, majorEvery: 10)
        case .blur: return .linear(0...20, step: 0.2, majorEvery: 10)
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
        case .brightness, .lightness: return signed(value * 200)
        case .contrast: return signed((value - 1) * 200)
        case .saturation: return signed((value - 1) * 100)
        case .exposure: return signed(value, 1)
        case .hue: return signed(value) == "0" ? "0°" : signed(value) + "°"
        case .temperature, .tint, .clarity: return signed(value * 100)
        case .sharpen, .noise: return String(format: "%.0f", value * 100)
        case .blur: return String(format: "%.1f", value)
        case .vignette: return String(format: "%.0f", value * 50)
        }
    }
}

extension AdjustValues {
    func isChanged(_ control: AdjustControl) -> Bool { abs(self[keyPath: control.keyPath] - control.neutral) > 0.0001 }
    var curvesChanged: Bool { curvePoints != AdjustValues().curvePoints }
}
