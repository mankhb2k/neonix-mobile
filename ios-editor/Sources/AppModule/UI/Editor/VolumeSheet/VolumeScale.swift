import Foundation

/// The Volume tool's scale (user 2026-10-17): what the user sees is a **multiplier of the clip's own level** - 0 is silence, **1 is the clip as
/// recorded (the mark in the middle of the slider, where the thumb opens)**, 10 is ten times the amplitude (+20 dB). Left of the mark the steps are
/// 0.01 (... 0.91, 0.92 ... up to 1), right of it 0.1 (1.1, 1.2 ... 10). The clip stores `V2AudioClip.gainDb` (absent = 0), so the multiplier is
/// converted: dB = 20 log10(multiplier), and a multiplier of 0 is stored as `muteDb` (-60 dB and below is silence).
/// The slider is two linear stretches: 0...1 over 0...0.5 and 1...10 over 0.5...1. A boost can clip a loud file (the engine adds the gain after the
/// file's own peak).
enum VolumeScale {
    static let minimum = 0.0
    static let unity = 1.0
    static let maximum = 10.0
    /// Where 1x sits on the slider (0...1): the middle.
    static let unityPosition = 0.5
    /// The stored dB for a multiplier of 0 (silence).
    static let muteDb = -60.0

    static func clamped(_ multiplier: Double) -> Double { min(max(multiplier, minimum), maximum) }

    /// Notched: 0.01 below 1, 0.1 from 1 up.
    static func snapped(_ multiplier: Double) -> Double {
        let m = clamped(multiplier)
        return m < 1 ? (m * 100).rounded() / 100 : (m * 10).rounded() / 10
    }

    /// The multiplier at a slider position 0...1 (notched).
    static func multiplier(forPosition position: Double) -> Double {
        let p = min(max(position, 0), 1)
        let raw = p <= unityPosition ? p / unityPosition : 1 + 9 * (p - unityPosition) / (1 - unityPosition)
        return snapped(raw)
    }

    /// The slider position 0...1 of a multiplier.
    static func position(forMultiplier multiplier: Double) -> Double {
        let m = clamped(multiplier)
        return m <= 1 ? unityPosition * m : unityPosition + (1 - unityPosition) * (m - 1) / 9
    }

    /// The dB to store for a multiplier (0 -> `muteDb`).
    static func gainDb(forMultiplier multiplier: Double) -> Double {
        let m = clamped(multiplier)
        return m <= 0.001 ? muteDb : max(20 * log10(m), muteDb)
    }

    /// The multiplier (notched) a stored dB shows as.
    static func multiplier(forGainDb db: Double) -> Double { db <= muteDb ? 0 : snapped(pow(10, db / 20)) }

    /// The linear gain the engine applies for a stored dB: 0 at `muteDb` and below, 1 at 0 dB, 10 at +20 dB.
    static func linearGain(_ db: Double) -> Double { db <= muteDb ? 0 : pow(10, db / 20) }

    /// "Mute", "0.91x", "1x", "1.2x", "10x" (with the multiplication sign).
    static func label(_ multiplier: Double) -> String {
        let m = snapped(multiplier)
        if m <= 0 { return "Mute" }
        if m == m.rounded() { return "\(Int(m))×" }
        return m < 1 ? String(format: "%.2f×", m) : String(format: "%.1f×", m)
    }
}
