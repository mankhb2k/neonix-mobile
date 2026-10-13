import SwiftUI

/// A cubic-bezier easing curve (CSS `cubic-bezier(x1, y1, x2, y2)`): the graph between two keyframes. `y` may leave 0...1
/// for overshoot ("Back"). Fake-data model for the Keyframe lab; the real one would compile to V2 cubic-bezier tracks.
struct LabBezier: Equatable {
    var x1: Double, y1: Double, x2: Double, y2: Double

    static let linear = LabBezier(x1: 0, y1: 0, x2: 1, y2: 1)

    /// Eased progress for time `t` in 0...1 (bisection on x, since x(s) is monotone while x1, x2 stay in 0...1).
    func value(at t: Double) -> Double {
        let t = min(max(t, 0), 1)
        if t == 0 || t == 1 { return t }
        var lo = 0.0, hi = 1.0
        for _ in 0..<28 {
            let mid = (lo + hi) / 2
            if Self.axis(mid, x1, x2) < t { lo = mid } else { hi = mid }
        }
        return Self.axis((lo + hi) / 2, y1, y2)
    }

    private static func axis(_ s: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - s
        return 3 * u * u * s * a + 3 * u * s * s * b + s * s * s
    }
}

enum LabEasingFamily: String, CaseIterable, Identifiable {
    case basic = "Basic", quad = "Quad", cubic = "Cubic", expo = "Expo", back = "Back"
    var id: String { rawValue }
}

struct LabEasing: Identifiable, Equatable {
    let id: String
    let name: String
    let family: LabEasingFamily?   // nil = the user's own curve
    var bezier: LabBezier

    static let original = LabEasing(id: "original", name: "Original", family: nil, bezier: .linear)
    static let linear = LabEasing(id: "linear", name: "Linear", family: .basic, bezier: .linear)

    static func custom(_ bezier: LabBezier) -> LabEasing { LabEasing(id: "custom", name: "Custom", family: nil, bezier: bezier) }

    /// The standard easing set (easings.net values as cubic-beziers).
    static let catalogue: [LabEasing] = {
        func e(_ id: String, _ name: String, _ f: LabEasingFamily, _ a: Double, _ b: Double, _ c: Double, _ d: Double) -> LabEasing {
            LabEasing(id: id, name: name, family: f, bezier: LabBezier(x1: a, y1: b, x2: c, y2: d))
        }
        return [
            linear,
            e("ease-in", "Ease In", .basic, 0.42, 0, 1, 1), e("ease-out", "Ease Out", .basic, 0, 0, 0.58, 1), e("ease-in-out", "Ease In Out", .basic, 0.42, 0, 0.58, 1),
            e("quad-in", "Quad In", .quad, 0.11, 0, 0.5, 0), e("quad-out", "Quad Out", .quad, 0.5, 1, 0.89, 1), e("quad-in-out", "Quad In Out", .quad, 0.45, 0, 0.55, 1),
            e("cubic-in", "Cubic In", .cubic, 0.32, 0, 0.67, 0), e("cubic-out", "Cubic Out", .cubic, 0.33, 1, 0.68, 1), e("cubic-in-out", "Cubic In Out", .cubic, 0.65, 0, 0.35, 1),
            e("expo-in", "Expo In", .expo, 0.7, 0, 0.84, 0), e("expo-out", "Expo Out", .expo, 0.16, 1, 0.3, 1), e("expo-in-out", "Expo In Out", .expo, 0.87, 0, 0.13, 1),
            e("back-in", "Back In", .back, 0.36, 0, 0.66, -0.56), e("back-out", "Back Out", .back, 0.34, 1.56, 0.64, 1), e("back-in-out", "Back In Out", .back, 0.68, -0.6, 0.32, 1.6),
        ]
    }()

    static func list(in family: LabEasingFamily?) -> [LabEasing] {
        guard let family else { return catalogue }
        return catalogue.filter { $0.family == family }
    }
}

/// The curve drawn inside a unit box; the vertical range is -0.3...1.3 so overshoot is never cut off.
struct LabCurveShape: Shape {
    let bezier: LabBezier
    var range: ClosedRange<Double> = -0.3...1.3

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 48
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let y = (bezier.value(at: t) - range.lowerBound) / (range.upperBound - range.lowerBound)
            let point = CGPoint(x: rect.minX + t * rect.width, y: rect.maxY - y * rect.height)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
