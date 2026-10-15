import Foundation

/// The Speed tool's curve (user 2026-10-15): the clip's playback speed as a smooth function of the position in its *source* footage.
/// Between the points `ln(rate)` follows a monotone cubic (Fritsch-Carlson), so the speed never overshoots its points, stays positive and
/// has no corners; at 1x everywhere it is the identity. The output time at a source position is the integral of `1 / rate`: a table of
/// that integral (`resolution` cells) gives both directions - source -> output and output -> source - without solving anything per frame.
struct SpeedCurve: Equatable {
    /// 0.1x ... 9x like the Normal ruler (`SpeedScale`).
    static let rateRange = SpeedScale.minimum...SpeedScale.maximum
    static let resolution = 640

    let points: [V2SpeedPoint]
    /// Source stretch the curve covers, in ms.
    let span: Double
    private let xs: [Double]
    private let logRates: [Double]
    private let slopes: [Double]
    /// Output ms at `span * k / resolution`.
    private let table: [Double]

    /// nil for fewer than two points or a non-positive span. Points are sorted, clamped to the rate range and forced to start at 0 and end at `span`.
    init?(points raw: [V2SpeedPoint], span: Double) {
        guard raw.count >= 2, span > 0 else { return nil }
        var sorted = raw.sorted { $0.sourceMs < $1.sourceMs }.map { V2SpeedPoint(sourceMs: min(max($0.sourceMs, 0), span), rate: SpeedScale.clamped($0.rate), slope: $0.slope) }
        sorted[0].sourceMs = 0
        sorted[sorted.count - 1].sourceMs = span
        // Two points at the same place would make a vertical step: nudge the later one.
        for i in 1..<sorted.count where sorted[i].sourceMs <= sorted[i - 1].sourceMs { sorted[i].sourceMs = sorted[i - 1].sourceMs + 1e-3 }
        self.points = sorted
        self.span = span
        let positions = sorted.map(\.sourceMs)
        let logs = sorted.map { log($0.rate) }
        let automatic = Self.monotoneSlopes(xs: positions, ys: logs)
        let slopes = sorted.indices.map { sorted[$0].slope ?? automatic[$0] }
        self.xs = positions
        self.logRates = logs
        self.slopes = slopes
        // The table: trapezoids of 1 / rate over `resolution` cells.
        var table = [Double](repeating: 0, count: Self.resolution + 1)
        var previous = 1 / exp(Self.logRate(0, positions, logs, slopes))
        for k in 1...Self.resolution {
            let x = span * Double(k) / Double(Self.resolution)
            let current = 1 / exp(Self.logRate(x, positions, logs, slopes))
            table[k] = table[k - 1] + (previous + current) / 2 * (span / Double(Self.resolution))
            previous = current
        }
        self.table = table
    }

    /// A constant speed as a curve (two points).
    static func constant(rate: Double, span: Double) -> SpeedCurve? {
        SpeedCurve(points: [V2SpeedPoint(sourceMs: 0, rate: rate), V2SpeedPoint(sourceMs: span, rate: rate)], span: span)
    }

    static func == (lhs: SpeedCurve, rhs: SpeedCurve) -> Bool { lhs.span == rhs.span && lhs.points == rhs.points }

    private static let cache: NSCache<NSString, Box> = { let c = NSCache<NSString, Box>(); c.countLimit = 64; return c }()
    private final class Box { let curve: SpeedCurve; init(_ curve: SpeedCurve) { self.curve = curve } }

    /// The same curve for the same points: `VideoTimeMapping` is built for every layer on every frame, the table only once.
    static func cached(points: [V2SpeedPoint], span: Double) -> SpeedCurve? {
        let key = (points.map { "\($0.sourceMs):\($0.rate)" }.joined(separator: ",") + "|\(span)") as NSString
        if let hit = cache.object(forKey: key) { return hit.curve }
        guard let curve = SpeedCurve(points: points, span: span) else { return nil }
        cache.setObject(Box(curve), forKey: key)
        return curve
    }

    // MARK: Evaluation

    /// The speed at a source position (clamped into the curve).
    func rate(atSource x: Double) -> Double {
        exp(Self.logRate(min(max(x, 0), span), xs, logRates, slopes))
    }

    /// How long the whole stretch takes to play.
    var outputDuration: Double { table[Self.resolution] }

    /// Output ms at which the source position `x` is shown.
    func outputMs(atSource x: Double) -> Double {
        let position = min(max(x, 0), span) / span * Double(Self.resolution)
        let cell = min(Int(position), Self.resolution - 1)
        return table[cell] + (table[cell + 1] - table[cell]) * (position - Double(cell))
    }

    /// The source position shown at output ms `t` (clamped to the clip).
    func sourceMs(atOutput t: Double) -> Double {
        let t = min(max(t, 0), outputDuration)
        var low = 0, high = Self.resolution
        while high - low > 1 {
            let mid = (low + high) / 2
            if table[mid] <= t { low = mid } else { high = mid }
        }
        let width = table[high] - table[low]
        let fraction = width > 0 ? (t - table[low]) / width : 0
        return (Double(low) + fraction) / Double(Self.resolution) * span
    }

    // MARK: Cutting

    /// d ln(rate) / d source ms at `x` (numerically).
    func slope(atSource x: Double) -> Double {
        let h = min(span / 4000, 0.5)
        let low = max(x - h, 0), high = min(x + h, span)
        return high > low ? (Self.logRate(high, xs, logRates, slopes) - Self.logRate(low, xs, logRates, slopes)) / (high - low) : 0
    }

    /// A point of this curve with its effective slope written in, so a piece cut out of the curve is the same function.
    private func fixedPoint(at index: Int) -> V2SpeedPoint {
        V2SpeedPoint(sourceMs: points[index].sourceMs, rate: points[index].rate, slope: slopes[index])
    }

    /// The curve split at source position `x`: the first half on `[0, x]`, the second re-based to start at 0. Both keep the shape exactly
    /// (a point is added at the cut with the speed and the slope there).
    func splitting(atSource x: Double) -> (first: SpeedCurve, second: SpeedCurve)? {
        guard x > 1e-3, x < span - 1e-3 else { return nil }
        let cut = V2SpeedPoint(sourceMs: x, rate: rate(atSource: x), slope: slope(atSource: x))
        let head = points.indices.filter { points[$0].sourceMs < x - 1e-3 }.map(fixedPoint) + [cut]
        let tail = [cut] + points.indices.filter { points[$0].sourceMs > x + 1e-3 }.map(fixedPoint)
        guard let first = SpeedCurve(points: head, span: x),
              let second = SpeedCurve(points: tail.map { V2SpeedPoint(sourceMs: $0.sourceMs - x, rate: $0.rate, slope: $0.slope) }, span: span - x) else { return nil }
        return (first, second)
    }

    /// The curve after trimming the head by `head` ms of *source* (positive = remove, negative = extend with the first speed) and the tail by
    /// `tail` ms of source (positive = extend with the last speed, negative = remove). A cut keeps the shape exactly; an extension is flat.
    /// Nil when nothing is left.
    func trimmed(headSource head: Double, tailSource tail: Double) -> SpeedCurve? {
        let newSpan = span - head + tail
        guard newSpan > 1e-3 else { return nil }
        let low = head, high = span + tail
        var kept: [V2SpeedPoint] = []
        if head < 0 {
            kept.append(V2SpeedPoint(sourceMs: low, rate: points[0].rate, slope: 0))
            kept.append(V2SpeedPoint(sourceMs: 0, rate: points[0].rate, slope: 0))
        } else {
            kept.append(V2SpeedPoint(sourceMs: low, rate: rate(atSource: low), slope: slope(atSource: low)))
        }
        for i in points.indices where points[i].sourceMs > max(low, 0) + 1e-3 && points[i].sourceMs < min(high, span) - 1e-3 { kept.append(fixedPoint(at: i)) }
        if tail > 0 {
            kept.append(V2SpeedPoint(sourceMs: span, rate: points[points.count - 1].rate, slope: 0))
            kept.append(V2SpeedPoint(sourceMs: high, rate: points[points.count - 1].rate, slope: 0))
        } else {
            kept.append(V2SpeedPoint(sourceMs: high, rate: rate(atSource: high), slope: slope(atSource: high)))
        }
        return SpeedCurve(points: kept.map { V2SpeedPoint(sourceMs: $0.sourceMs - low, rate: $0.rate, slope: $0.slope) }, span: newSpan)
    }

    // MARK: Interpolation (monotone cubic Hermite on ln(rate))

    private static func monotoneSlopes(xs: [Double], ys: [Double]) -> [Double] {
        let n = xs.count
        var delta = [Double](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) { delta[i] = (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]) }
        var m = [Double](repeating: 0, count: n)
        m[0] = delta[0]; m[n - 1] = delta[n - 2]
        if n > 2 { for i in 1..<(n - 1) { m[i] = delta[i - 1] * delta[i] <= 0 ? 0 : (delta[i - 1] + delta[i]) / 2 } }
        for i in 0..<(n - 1) {
            if delta[i] == 0 { m[i] = 0; m[i + 1] = 0; continue }
            let a = m[i] / delta[i], b = m[i + 1] / delta[i]
            let radius = a * a + b * b
            if radius > 9 { let tau = 3 / radius.squareRoot(); m[i] = tau * a * delta[i]; m[i + 1] = tau * b * delta[i] }
        }
        return m
    }

    private static func logRate(_ x: Double, _ xs: [Double], _ ys: [Double], _ m: [Double]) -> Double {
        var i = 0
        while i < xs.count - 2 && x > xs[i + 1] { i += 1 }
        let h = xs[i + 1] - xs[i]
        let t = min(max((x - xs[i]) / h, 0), 1)
        let t2 = t * t, t3 = t2 * t
        return (2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h * m[i] + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h * m[i + 1]
    }
}
