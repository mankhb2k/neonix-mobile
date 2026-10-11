import Observation
import Photos

struct PickedMedia {
    let asset: PHAsset
    let kind: MediaKind
    let durationMs: Double
    /// Start of the crop window for a video longer than the slot.
    var cropStartMs: Double = 0
}

/// State of the slot-filling screen: which slot is current and what is in each.
@MainActor
@Observable
final class SlotPickerModel {
    struct SlotState: Identifiable {
        let slot: TemplateManifest.Slot
        var media: PickedMedia?
        var id: String { slot.id }
        var durationMs: Int { slot.durationMs ?? 0 }
    }

    private(set) var slots: [SlotState]
    private(set) var currentIndex = 0
    var message: String?

    init(slots: [TemplateManifest.Slot]) {
        self.slots = slots.filter { $0.kind == "media" }.map { SlotState(slot: $0, media: nil) }
    }

    var current: SlotState? { slots.indices.contains(currentIndex) ? slots[currentIndex] : nil }
    var canContinue: Bool { slots.allSatisfy { $0.media != nil || !$0.slot.required } && slots.contains { $0.media != nil } }

    func select(slot index: Int) { if slots.indices.contains(index) { currentIndex = index } }

    /// Whether the asset can go into the current slot (drives the dimmed state in the grid).
    func canUse(_ asset: PHAsset) -> Bool {
        guard let current else { return false }
        return SlotRules.canUse(asset.mediaType == .video ? .video : .photo, durationMs: asset.duration * 1000, forSlotMs: current.durationMs)
    }

    /// Puts the asset in the current slot and moves on to the next empty one.
    func pick(_ asset: PHAsset) {
        guard let current else { return }
        let kind: MediaKind = asset.mediaType == .video ? .video : .photo
        let durationMs = asset.duration * 1000
        guard SlotRules.canUse(kind, durationMs: durationMs, forSlotMs: current.durationMs) else {
            message = "Pick a video of at least \(String(format: "%.1f", Double(current.durationMs) / 1000)) s for this slot"
            return
        }
        message = nil
        slots[currentIndex].media = PickedMedia(asset: asset, kind: kind, durationMs: durationMs)
        if let next = slots.indices.first(where: { $0 > currentIndex && slots[$0].media == nil }) ?? slots.indices.first(where: { slots[$0].media == nil }) {
            currentIndex = next
        }
    }

    func clear(slot index: Int) {
        guard slots.indices.contains(index) else { return }
        slots[index].media = nil
        currentIndex = index
    }

    func setCrop(slot index: Int, startMs: Double) {
        guard slots.indices.contains(index), var media = slots[index].media else { return }
        media.cropStartMs = SlotRules.clampedCropStart(startMs, mediaMs: media.durationMs, slotMs: slots[index].durationMs)
        slots[index].media = media
    }

    func needsCrop(slot index: Int) -> Bool {
        guard slots.indices.contains(index), let media = slots[index].media else { return false }
        return SlotRules.needsCrop(media.kind, durationMs: media.durationMs, slotMs: slots[index].durationMs)
    }
}
