import Foundation

/// `manifest.json` inside a template package (spec: api/docs/template-package.md). The package is
/// `manifest.json` + `document.json` (an `EditorDocument`) + optional `assets/`; fonts are never packaged,
/// they ship in the app and are only named here.
struct TemplateManifest: Codable {
    struct Composition: Codable {
        var width: Int
        var height: Int
        var durationMs: Int
    }

    /// A layer the user fills with their own media/text. `layerId` points into `document.json`.
    struct Slot: Codable {
        var id: String
        /// "media" (a photo or a video) | "text". A media slot's layer is an image or video layer; the user's
        /// choice decides which. A text slot's layer is a text layer.
        var kind: String
        var layerId: String
        var label: String
        /// How long the slot's clip plays. A photo is held that long; a video must be at least this long and is
        /// cropped to a window of exactly this length.
        var durationMs: Int?
        var required: Bool
    }

    struct Music: Codable {
        var title: String
        var artist: String?
    }

    /// Version of the EditorDocument format this package was written for.
    var formatVersion: Int
    var minAppVersion: String
    var name: String
    var composition: Composition
    var fonts: [String]
    var builtinAssets: [String]
    /// Label for the soundtrack, shown on the template page. The audio itself is in `document.json`.
    var music: Music?
    var slots: [Slot]
}
