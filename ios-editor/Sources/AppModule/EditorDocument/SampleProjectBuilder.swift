import Foundation

/// A placeholder media choice for a sample/starter project — the same
/// bundled assets the app has always shipped as fixtures, now used to seed
/// a real project's initial content (`ProjectsView`) rather than a
/// dev-only picker. Extracted 2026-10-08 from the old `EditorDemoView`
/// fixture screen when that screen was deleted — `ProjectsView` depended on
/// its `makeDocument(_:)` for every sample project's placeholder video
/// layer, so that logic moved here instead of disappearing with the UI
/// around it.
enum SampleMedia: String, CaseIterable, Identifiable {
    case photo, videoPortrait, videoLandscape
    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo: return "Photo"
        case .videoPortrait: return "Video A (portrait)"
        case .videoLandscape: return "Video B (landscape)"
        }
    }

    var layerKind: String { self == .photo ? "image" : "video" }
    var isVideo: Bool { self != .photo }

    var asset: V2Asset {
        switch self {
        case .photo:
            return .image(V2ImageAsset(id: "photo", uri: "pexels-followingnyc-38428141.jpg", width: 3648, height: 5472))
        case .videoPortrait:
            if let override = SampleClipOverride.current {
                return .video(V2VideoAsset(id: "video-a", uri: override.uri, width: override.width, height: override.height, duration: override.durationMs))
            }
            return .video(V2VideoAsset(id: "video-a", uri: "13792197_1080_1920_30fps.mp4", width: 1080, height: 1920, duration: 31200))
        case .videoLandscape:
            return .video(V2VideoAsset(id: "video-b", uri: "12253998_1920_1080_30fps.mp4", width: 1920, height: 1080, duration: 12345))
        }
    }
}

/// Exercises the Editor-tier effect presets from `EffectPresets.swift` —
/// see CLAUDE.md's "Protocol V2 stays atomic" rule: picking one of these
/// compiles to a `V2Filter` primitive chain, never a named effect field on
/// the layer itself.
enum EffectOption: String, CaseIterable, Identifiable {
    case none, blur, outerGlow, sepia
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "None"
        case .blur: return "Blur"
        case .outerGlow: return "Outer glow"
        case .sepia: return "Sepia"
        }
    }
    var preset: EffectPresetKind? {
        switch self {
        case .none: return nil
        case .blur: return .blur(radius: 6)
        case .outerGlow: return .outerGlow(radius: 12, color: "#FFD60Aff", opacity: 0.9)
        case .sepia: return .sepia(amount: 0.8)
        }
    }
}

enum PresetOption: String, CaseIterable, Identifiable {
    case none, fade, slide, zoom
    var id: String { rawValue }
    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    var kind: PresetKind? {
        switch self {
        case .none: return nil
        case .fade: return .fade
        case .slide: return .slide
        case .zoom: return .zoom
        }
    }
}

/// A named shorthand for a `V2Easing.cubicBezier` curve — see
/// `PresetBinding.easing`'s doc comment and CLAUDE.md's "Protocol V2 must
/// stay atomic" rule: the name lives only here, at the Editor tier.
enum EasingOption: String, CaseIterable, Identifiable {
    case linear, easeIn, easeOut, easeInOut
    var id: String { rawValue }
    var title: String {
        switch self {
        case .linear: return "Linear"
        case .easeIn: return "Ease In"
        case .easeOut: return "Ease Out"
        case .easeInOut: return "Ease In Out"
        }
    }
    /// `nil` for "linear" — `PresetBinding.easing` stores `nil` the same
    /// way for "no easing chosen", so there's one representation for
    /// linear, not two.
    var bindingValue: String? { self == .linear ? nil : rawValue }
}

/// Builds an `EditorDocument` for a single placeholder media layer — the
/// starter content `ProjectsView` compiles into every sample project (and
/// whatever a "New Project" starts from, until real import/authoring
/// exists). Not a UI, just the document-construction logic a fixture
/// screen used to own alongside its own picker controls.
enum SampleProjectBuilder {
    /// `composition`/`frame` default to a square (1:1) canvas; pass both
    /// explicitly for a caller that wants a different canvas shape (e.g.
    /// `ProjectsView`'s 9:16 placeholder project).
    static func makeDocument(
        media: SampleMedia, inOption: PresetOption, outOption: PresetOption,
        effectOption: EffectOption, easingOption: EasingOption,
        composition: V2Composition = V2Composition(width: 320, height: 320, fps: 30, background: "#101820"),
        frame: V2Frame = V2Frame(width: 240, height: 320)
    ) -> EditorDocument {
        let asset = media.asset
        let layer = EditorLayer(
            id: "demo-layer",
            kind: media.layerKind,
            assetId: asset.id,
            fill: nil,
            frame: frame,
            timing: V2Timing(start: 0, duration: 2500),
            inPreset: inOption.kind.map { PresetBinding(kind: $0, durationMs: 500, easing: easingOption.bindingValue) },
            outPreset: outOption.kind.map { PresetBinding(kind: $0, durationMs: 500, easing: easingOption.bindingValue) },
            effectPresets: effectOption.preset.map { [$0] }
        )
        return EditorDocument(
            id: "sample-project",
            composition: composition,
            assets: [asset],
            layers: [layer]
        )
    }
}
