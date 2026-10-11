import Foundation

enum MediaKind { case photo, video }

/// What a media slot accepts. Photos always fit (they are held for the slot's length); a video must be at least as
/// long as the slot, and if longer it is cropped to a window of exactly the slot's length.
enum SlotRules {
    static let toleranceMs = 50.0

    static func canUse(_ kind: MediaKind, durationMs: Double, forSlotMs slotMs: Int) -> Bool {
        kind == .photo || durationMs + toleranceMs >= Double(slotMs)
    }

    static func needsCrop(_ kind: MediaKind, durationMs: Double, slotMs: Int) -> Bool {
        kind == .video && durationMs > Double(slotMs) + toleranceMs
    }

    /// Keeps a crop window inside the video.
    static func clampedCropStart(_ startMs: Double, mediaMs: Double, slotMs: Int) -> Double {
        min(max(0, startMs), max(0, mediaMs - Double(slotMs)))
    }
}
