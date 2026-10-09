import Foundation

/// Hiệu ứng âm thanh — a small built-in library of one-tap sound effects,
/// not a DSP processing effect (reverb/EQ/etc. — that's a different,
/// bigger feature the user explicitly ruled out: "hiệu ứng âm thanh chỉ là
/// sound effect giống chọn audio thôi"). Tapping one works exactly like
/// Thêm nhạc — it places a `V2AudioClip` at the playhead via the same
/// `AddAudioClipCommand` — the only difference is the file comes from this
/// bundled catalog instead of the user's own Files app.
///
/// **Placeholder content**: these 6 `.wav` files (`Resources/Media/
/// SoundEffects/`) are synthesized tones/noise bursts generated for this
/// pass (no licensed/real SFX library exists in this repo yet) — a stand-in
/// so the feature is real and testable end to end, not a mocked UI. Swap in
/// a real licensed sound pack later by replacing the files and this list;
/// nothing else about the feature needs to change.
struct SoundEffectPreset: Identifiable {
    let id: String
    let title: String
    let filename: String
    let durationMs: Double
    let systemImage: String
}

enum SoundEffectCatalog {
    static let presets: [SoundEffectPreset] = [
        SoundEffectPreset(id: "sfx-pop", title: "Pop", filename: "sfx-pop.wav", durationMs: 150, systemImage: "circle.fill"),
        SoundEffectPreset(id: "sfx-whoosh", title: "Whoosh", filename: "sfx-whoosh.wav", durationMs: 400, systemImage: "wind"),
        SoundEffectPreset(id: "sfx-ding", title: "Notification", filename: "sfx-ding.wav", durationMs: 600, systemImage: "bell.fill"),
        SoundEffectPreset(id: "sfx-boing", title: "Boing", filename: "sfx-boing.wav", durationMs: 300, systemImage: "waveform.path"),
        SoundEffectPreset(id: "sfx-alert", title: "Alert", filename: "sfx-alert.wav", durationMs: 350, systemImage: "exclamationmark.triangle.fill"),
        SoundEffectPreset(id: "sfx-drumhit", title: "Drum Hit", filename: "sfx-drumhit.wav", durationMs: 250, systemImage: "metronome.fill"),
    ]

    /// Each preset's own asset, minted fresh every call (cheap, no I/O) —
    /// stable `id` (not a UUID like `MediaImportService.importAudio`'s)
    /// matters here: `AddAudioClipCommand` dedupes by asset id, so tapping
    /// the same effect twice shares one `project.assets` entry instead of
    /// appending a duplicate every time.
    static func asset(for preset: SoundEffectPreset) -> V2AudioAsset {
        V2AudioAsset(id: preset.id, uri: preset.filename, mimeType: "audio/wav", duration: preset.durationMs)
    }
}
