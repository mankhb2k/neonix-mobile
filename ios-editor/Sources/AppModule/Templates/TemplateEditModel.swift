import Foundation
import Observation

/// State behind the template result screen: which media is in each slot, the typed texts, music on/off, and the
/// project built from all of it. Every change rebuilds the project from the creator's document (nothing is patched
/// in place), then bumps `revision` so the player reloads it.
@MainActor
@Observable
final class TemplateEditModel {
    struct SlotEntry: Identifiable {
        let slot: TemplateManifest.Slot
        /// When the slot's clip starts on the template's timeline, ms.
        let startMs: Double
        var pick: PickedMedia?
        var fill: SlotFill?
        var id: String { slot.id }
        var durationMs: Int { slot.durationMs ?? 0 }
    }

    let package: TemplatePackage
    private(set) var entries: [SlotEntry]
    private(set) var texts: [String: String]
    private(set) var project: V2Project
    private(set) var revision = 0
    var errorMessage: String?
    private(set) var isImporting = false

    var musicOn = true {
        didSet { if musicOn != oldValue { rebuild() } }
    }

    /// The soundtrack's label from the manifest.
    var musicTitle: String { package.manifest.music?.title ?? "Original" }

    var textSlots: [TemplateManifest.Slot] { package.manifest.slots.filter { $0.kind == "text" } }

    /// Imports the picked media of every slot, then builds the first project.
    static func make(package: TemplatePackage, picks: [PickedMedia?], slots: [TemplateManifest.Slot]) async throws -> TemplateEditModel {
        var entries: [SlotEntry] = []
        for slot in package.manifest.slots where slot.kind == "media" {
            let start = package.document.layers.first { $0.id == slot.layerId }?.timing.start ?? 0
            var entry = SlotEntry(slot: slot, startMs: start, pick: nil, fill: nil)
            if let index = slots.firstIndex(where: { $0.id == slot.id }), index < picks.count, let pick = picks[index] {
                entry.pick = pick
                entry.fill = try await fill(for: slot, pick: pick)
            }
            entries.append(entry)
        }
        var texts: [String: String] = [:]
        for slot in package.manifest.slots where slot.kind == "text" {
            if let text = package.document.layers.first(where: { $0.id == slot.layerId })?.text?.text { texts[slot.id] = text }
        }
        return TemplateEditModel(package: package, entries: entries, texts: texts)
    }

    private init(package: TemplatePackage, entries: [SlotEntry], texts: [String: String]) {
        self.package = package
        self.entries = entries
        self.texts = texts
        self.project = (try? TemplateBuild.project(package: package, fills: entries.compactMap(\.fill), texts: texts, musicOn: true))
            ?? compile(package.document)
    }

    private static func fill(for slot: TemplateManifest.Slot, pick: PickedMedia) async throws -> SlotFill {
        let asset = try await PhotoImporter.importMedia(pick.asset, kind: pick.kind, assetId: "media-\(slot.id)-\(UUID().uuidString.prefix(6))")
        return SlotFill(slotId: slot.id, kind: pick.kind, asset: asset, trimStartMs: pick.kind == .video ? pick.cropStartMs : 0)
    }

    // MARK: Changes

    func replace(slot id: String, with pick: PickedMedia) async {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        isImporting = true
        defer { isImporting = false }
        do {
            entries[index].fill = try await Self.fill(for: entries[index].slot, pick: pick)
            entries[index].pick = pick
            rebuild()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setCrop(slot id: String, startMs: Double) {
        guard let index = entries.firstIndex(where: { $0.id == id }), var pick = entries[index].pick, let fill = entries[index].fill else { return }
        pick.cropStartMs = SlotRules.clampedCropStart(startMs, mediaMs: pick.durationMs, slotMs: entries[index].durationMs)
        entries[index].pick = pick
        entries[index].fill = SlotFill(slotId: fill.slotId, kind: fill.kind, asset: fill.asset, trimStartMs: pick.cropStartMs)
        rebuild()
    }

    func setText(slot id: String, _ text: String) {
        texts[id] = text
        rebuild()
    }

    func text(for slot: TemplateManifest.Slot) -> String { texts[slot.id] ?? "" }

    func entry(at playheadMs: Double) -> SlotEntry? {
        entries.first { playheadMs >= $0.startMs && playheadMs < $0.startMs + Double($0.durationMs) }
    }

    private func rebuild() {
        do {
            project = try TemplateBuild.project(package: package, fills: entries.compactMap(\.fill), texts: texts, musicOn: musicOn)
            revision += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
