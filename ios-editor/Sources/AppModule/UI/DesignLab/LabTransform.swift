import SwiftUI

/// The numbers a transform control edits, in composition units (a 1080-wide canvas), like `EditorTransform`.
struct LabTransform: Equatable {
    var x = 0.0
    var y = 0.0
    var scale = 1.0
    var rotation = 0.0
    var opacity = 1.0
}

/// One adjustable thing in the Transform lab, with everything a control needs to edit it.
enum LabParam: String, CaseIterable, Identifiable {
    case x, y, scale, rotation, opacity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .x: return "Position X"
        case .y: return "Position Y"
        case .scale: return "Scale"
        case .rotation: return "Rotate"
        case .opacity: return "Opacity"
        }
    }

    var symbol: String {
        switch self {
        case .x: return "arrow.left.and.right"
        case .y: return "arrow.up.and.down"
        case .scale: return "arrow.up.left.and.arrow.down.right"
        case .rotation: return "rotate.right"
        case .opacity: return "circle.lefthalf.filled"
        }
    }

    var neutral: Double {
        switch self {
        case .x, .y, .rotation: return 0
        case .scale, .opacity: return 1
        }
    }

    var mapping: RulerMapping {
        switch self {
        case .x: return .linear(-1080...1080, step: 10, majorEvery: 10)
        case .y: return .linear(-1920...1920, step: 10, majorEvery: 10)
        case .scale: return .logarithmic(0.25...4, ticksPerDoubling: 12)
        case .rotation: return .linear(-180...180, step: 1, majorEvery: 15)
        case .opacity: return .linear(0...1, step: 0.01, majorEvery: 10)
        }
    }

    /// Values that give a stronger tick of haptics: centre, 100 %, upright and quarter turns.
    var detents: [Double] {
        switch self {
        case .x, .y: return [0]
        case .scale, .opacity: return [1]
        case .rotation: return [-90, -45, 0, 45, 90]
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .x, .y: return String(format: "%+.0f", value == 0 ? 0 : value).replacingOccurrences(of: "+0", with: "0")
        case .scale, .opacity: return String(format: "%.0f%%", value * 100)
        case .rotation: return String(format: "%.0f°", value == 0 ? 0 : value)
        }
    }

    func get(_ t: LabTransform) -> Double {
        switch self {
        case .x: return t.x
        case .y: return t.y
        case .scale: return t.scale
        case .rotation: return t.rotation
        case .opacity: return t.opacity
        }
    }

    func set(_ t: inout LabTransform, _ value: Double) {
        switch self {
        case .x: t.x = value
        case .y: t.y = value
        case .scale: t.scale = value
        case .rotation: t.rotation = value
        case .opacity: t.opacity = value
        }
    }
}
