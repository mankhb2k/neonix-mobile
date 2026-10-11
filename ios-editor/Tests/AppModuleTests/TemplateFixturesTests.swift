import XCTest
@testable import NeonixEditor

/// The starter and demo templates in /templates are generated from the builders below with the app's own
/// Codable types, so the JSON can never drift from what the app decodes. Regenerate after editing:
///   TEST_RUNNER_WRITE_TEMPLATES=1 xcodebuild … test -only-testing:NeonixEditorTests/TemplateFixturesTests
/// Both use media the app already bundles as slot placeholders (users replace them), so packages need no assets/.
private enum StarterTemplates {
    static let composition = V2Composition(width: 1080, height: 1920, fps: 30, background: "#101820")
    static let frame = V2Frame(width: 1080, height: 1920)
    static let centered = EditorTextLayoutIntent(textAlign: "center", wrap: "word")

    /// Real music, 12 s, shipped inside each package as assets/bgm.m4a.
    static let music: V2Asset = .audio(V2AudioAsset(id: "bgm", uri: "assets/bgm.m4a", mimeType: "audio/mp4", duration: 12000))
    static let soundtrack = V2AudioDomain(sampleRate: 48000, tracks: [
        V2AudioTrack(id: "music", pan: 0, muted: false, clips: [
            V2AudioClip(id: "bgm-clip", assetId: "bgm", timing: V2AudioClipTiming(start: 0, duration: 12000), trim: V2AudioClipTrim(start: 0, end: nil), playbackRate: 1),
        ]),
    ])

    static let photo: V2Asset = .image(V2ImageAsset(id: "photo", uri: "pexels-followingnyc-38428141.jpg", width: 3648, height: 5472))
    static let video: V2Asset = .video(V2VideoAsset(id: "video-a", uri: "13792197_1080_1920_30fps.mp4", width: 1080, height: 1920, duration: 31200))

    struct Template {
        let slug: String
        let manifest: TemplateManifest
        let document: EditorDocument
    }

    static func manifest(name: String, durationMs: Int, music: TemplateManifest.Music, slots: [TemplateManifest.Slot]) -> TemplateManifest {
        TemplateManifest(
            formatVersion: 2, minAppVersion: "1.0", name: name,
            composition: .init(width: 1080, height: 1920, durationMs: durationMs),
            fonts: ["Helvetica"], builtinAssets: [], music: music, slots: slots
        )
    }

    /// 4 photo slots of 3 s (zoom in, fade out) with a title over the whole 12 s.
    static var photoSlideshow: Template {
        let layers = (0..<4).map { index in
            EditorLayer(
                id: "slot-\(index + 1)", kind: "image", assetId: "photo", fill: nil, frame: frame,
                timing: V2Timing(start: Double(index) * 3000, duration: 3000),
                inPreset: PresetBinding(kind: .zoom, durationMs: 600, easing: "easeOut"),
                outPreset: PresetBinding(kind: .fade, durationMs: 400, easing: nil)
            )
        } + [
            EditorLayer(
                id: "title", kind: "text", frame: V2Frame(width: 1080, height: 200), timing: V2Timing(start: 0, duration: 12000),
                text: EditorTextLayer(text: "Summer Memories", fontFamily: "Helvetica", fontSize: 84, color: "#FFFFFFff", layout: centered)
            ),
        ]
        let slots = (0..<4).map {
            TemplateManifest.Slot(id: "photo-\($0 + 1)", kind: "media", layerId: "slot-\($0 + 1)", label: "Photo \($0 + 1)", durationMs: 3000, required: $0 < 2)
        } + [TemplateManifest.Slot(id: "title", kind: "text", layerId: "title", label: "Title", durationMs: nil, required: true)]
        return Template(
            slug: "photo-slideshow",
            manifest: manifest(name: "Photo Slideshow", durationMs: 12000, music: .init(title: "Demo Track", artist: "Neonix"), slots: slots),
            document: EditorDocument(id: "photo-slideshow", composition: composition, assets: [photo, music], layers: layers, audio: soundtrack)
        )
    }

    /// 3 video slots (4 s, 5 s, 3 s; slide in, fade out, the middle one in sepia) plus a typewriter caption.
    static var videoHighlights: Template {
        let durations: [Double] = [4000, 5000, 3000]
        var start = 0.0
        var layers: [EditorLayer] = []
        for (index, duration) in durations.enumerated() {
            layers.append(EditorLayer(
                id: "slot-\(index + 1)", kind: "video", assetId: "video-a", fill: nil, frame: frame,
                timing: V2Timing(start: start, duration: duration),
                inPreset: PresetBinding(kind: .slide, durationMs: 500, easing: "easeOut"),
                outPreset: PresetBinding(kind: .fade, durationMs: 400, easing: nil),
                effectPresets: index == 1 ? [.sepia(amount: 0.6)] : nil
            ))
            start += duration
        }
        layers.append(EditorLayer(
            id: "caption", kind: "text", frame: V2Frame(width: 1080, height: 160), timing: V2Timing(start: 500, duration: 3500),
            text: EditorTextLayer(
                text: "My Highlights", fontFamily: "Helvetica", fontSize: 72, color: "#FFFFFFff", layout: centered,
                typewriter: EditorTypewriterIntent(perUnitDelayMs: 70, direction: "forward", reveal: "fade")
            )
        ))
        let slots = durations.indices.map {
            TemplateManifest.Slot(id: "clip-\($0 + 1)", kind: "media", layerId: "slot-\($0 + 1)", label: "Clip \($0 + 1)", durationMs: Int(durations[$0]), required: true)
        } + [TemplateManifest.Slot(id: "caption", kind: "text", layerId: "caption", label: "Caption", durationMs: nil, required: false)]
        return Template(
            slug: "video-highlights",
            manifest: manifest(name: "Video Highlights", durationMs: 12000, music: .init(title: "Demo Track", artist: "Neonix"), slots: slots),
            document: EditorDocument(id: "video-highlights", composition: composition, assets: [video, music], layers: layers, audio: soundtrack)
        )
    }

    // MARK: Demo templates for Home (structure here; preview video, music and price in templates/demo.json)

    private struct DemoSpec {
        enum Placeholder { case photo, video }
        let slug: String
        let name: String
        let width: Double
        let height: Double
        /// One entry per media slot, in ms; slots play one after another.
        let slots: [Double]
        let placeholder: Placeholder
        let inPreset: PresetKind?
        let inMs: Double
        let outPreset: PresetKind?
        let outMs: Double
        let effects: [EffectPresetKind]?
        /// Slot indexes the effects apply to (nil = all).
        let effectSlots: Set<Int>?
        let title: String?
        let titleSize: Double
        let typewriter: Bool
    }

    private static let demoSpecs: [DemoSpec] = [
        DemoSpec(slug: "moody-walk", name: "Moody Walk", width: 1080, height: 1920, slots: [3000, 3000, 3000, 3000], placeholder: .video,
                 inPreset: .slide, inMs: 500, outPreset: .fade, outMs: 400, effects: [.sepia(amount: 0.3)], effectSlots: [1],
                 title: "Moody Walk", titleSize: 96, typewriter: false),
        DemoSpec(slug: "city-weekend", name: "City Weekend", width: 1080, height: 1920, slots: Array(repeating: 2000, count: 6), placeholder: .photo,
                 inPreset: .zoom, inMs: 400, outPreset: .fade, outMs: 300, effects: nil, effectSlots: nil,
                 title: "Weekend Story", titleSize: 84, typewriter: true),
        DemoSpec(slug: "soft-diary", name: "Soft Diary", width: 1080, height: 1440, slots: Array(repeating: 4000, count: 3), placeholder: .photo,
                 inPreset: .fade, inMs: 700, outPreset: .fade, outMs: 700, effects: [.sepia(amount: 0.4)], effectSlots: nil,
                 title: "Soft Diary", titleSize: 80, typewriter: false),
        DemoSpec(slug: "fast-cuts", name: "Fast Cuts", width: 1080, height: 1920, slots: Array(repeating: 1500, count: 8), placeholder: .video,
                 inPreset: .slide, inMs: 250, outPreset: nil, outMs: 0, effects: nil, effectSlots: nil,
                 title: nil, titleSize: 0, typewriter: false),
        DemoSpec(slug: "travel-reel", name: "Travel Reel", width: 1080, height: 1920, slots: [5000, 4000, 4000, 3000], placeholder: .video,
                 inPreset: .zoom, inMs: 600, outPreset: .slide, outMs: 400, effects: [.sepia(amount: 0.5)], effectSlots: [2],
                 title: "Wanderlust", titleSize: 92, typewriter: true),
        DemoSpec(slug: "memory-frames", name: "Memory Frames", width: 1080, height: 1620, slots: Array(repeating: 3000, count: 5), placeholder: .photo,
                 inPreset: .fade, inMs: 600, outPreset: .fade, outMs: 600, effects: nil, effectSlots: nil,
                 title: "Memories", titleSize: 88, typewriter: false),
        DemoSpec(slug: "golden-hour", name: "Golden Hour", width: 1080, height: 1920, slots: Array(repeating: 4000, count: 3), placeholder: .video,
                 inPreset: .fade, inMs: 500, outPreset: .fade, outMs: 500, effects: [.sepia(amount: 0.55)], effectSlots: nil,
                 title: "Golden Hour", titleSize: 90, typewriter: false),
        DemoSpec(slug: "night-out", name: "Night Out", width: 1080, height: 1920, slots: Array(repeating: 2500, count: 6), placeholder: .video,
                 inPreset: .slide, inMs: 300, outPreset: .zoom, outMs: 300,
                 effects: [.colorAdjust(brightness: 0, contrast: 1.25, saturation: 1.3, exposure: 0, hueRotate: 0, lightness: 0)], effectSlots: nil,
                 title: "Night Out", titleSize: 96, typewriter: true),
        DemoSpec(slug: "mono-diary", name: "Mono Diary", width: 1080, height: 1440, slots: Array(repeating: 3500, count: 4), placeholder: .photo,
                 inPreset: .fade, inMs: 600, outPreset: .fade, outMs: 500, effects: [.grayscale(amount: 1)], effectSlots: nil,
                 title: "Mono Diary", titleSize: 84, typewriter: false),
        DemoSpec(slug: "quick-intro", name: "Quick Intro", width: 1080, height: 1920, slots: [3000, 3000], placeholder: .video,
                 inPreset: .zoom, inMs: 500, outPreset: .fade, outMs: 400, effects: nil, effectSlots: nil,
                 title: "Hello!", titleSize: 110, typewriter: true),
    ]

    private static func demo(_ spec: DemoSpec) -> Template {
        let total = spec.slots.reduce(0, +)
        let frame = V2Frame(width: spec.width, height: spec.height)
        let placeholderAsset = spec.placeholder == .photo ? photo : video
        let placeholderId = placeholderAsset.id

        var start = 0.0
        var layers: [EditorLayer] = []
        for (index, duration) in spec.slots.enumerated() {
            layers.append(EditorLayer(
                id: "slot-\(index + 1)", kind: spec.placeholder == .photo ? "image" : "video", assetId: placeholderId, fill: nil, frame: frame,
                timing: V2Timing(start: start, duration: duration),
                inPreset: spec.inPreset.map { PresetBinding(kind: $0, durationMs: spec.inMs, easing: "easeOut") },
                outPreset: spec.outPreset.map { PresetBinding(kind: $0, durationMs: spec.outMs, easing: nil) },
                effectPresets: (spec.effectSlots?.contains(index) ?? true) ? spec.effects : nil
            ))
            start += duration
        }
        var slots = spec.slots.enumerated().map { index, duration in
            TemplateManifest.Slot(id: "clip-\(index + 1)", kind: "media", layerId: "slot-\(index + 1)",
                                  label: spec.placeholder == .photo ? "Photo \(index + 1)" : "Clip \(index + 1)",
                                  durationMs: Int(duration), required: index < max(2, spec.slots.count - 2))
        }
        if let title = spec.title {
            layers.append(EditorLayer(
                id: "title", kind: "text", frame: V2Frame(width: spec.width, height: 200),
                timing: V2Timing(start: spec.typewriter ? 400 : 0, duration: spec.typewriter ? min(total - 400, 4500) : total),
                text: EditorTextLayer(
                    text: title, fontFamily: "Helvetica", fontSize: spec.titleSize, color: "#FFFFFFff", layout: centered,
                    typewriter: spec.typewriter ? EditorTypewriterIntent(perUnitDelayMs: 70, direction: "forward", reveal: "fade") : nil
                )
            ))
            slots.append(TemplateManifest.Slot(id: "title", kind: "text", layerId: "title", label: "Title", durationMs: nil, required: false))
        }
        let music: V2Asset = .audio(V2AudioAsset(id: "bgm", uri: "assets/bgm.m4a", mimeType: "audio/mp4", duration: total))
        let soundtrack = V2AudioDomain(sampleRate: 48000, tracks: [
            V2AudioTrack(id: "music", pan: 0, muted: false, clips: [
                V2AudioClip(id: "bgm-clip", assetId: "bgm", timing: V2AudioClipTiming(start: 0, duration: total), trim: V2AudioClipTrim(start: 0, end: nil), playbackRate: 1),
            ]),
        ])
        return Template(
            slug: spec.slug,
            manifest: TemplateManifest(
                formatVersion: 2, minAppVersion: "1.0", name: spec.name,
                composition: .init(width: Int(spec.width), height: Int(spec.height), durationMs: Int(total)),
                fonts: ["Helvetica"], builtinAssets: [], music: .init(title: "Demo Track", artist: "Neonix"), slots: slots
            ),
            document: EditorDocument(
                id: spec.slug,
                composition: V2Composition(width: spec.width, height: spec.height, fps: 30, background: "#101820"),
                assets: [placeholderAsset, music], layers: layers, audio: soundtrack
            )
        )
    }

    static var demos: [Template] { demoSpecs.map(demo) }

    // MARK: Collage (uses layer transforms: position, rotation, scale)

    /// Three polaroid frames, tilted and overlapping, appearing one after another and then staying; a title on top.
    /// A white frame is a shape layer and the photo sits inside it with the same tilt, so the photo's own transform
    /// is computed from the frame's (`EditorTransform.canvasPoint`). Only the photos are slots.
    static var polaroidCollage: Template {
        let width = 1080.0, height = 1920.0, total = 9000.0
        let frameSize = V2Frame(width: 700, height: 860)
        let photoSize = V2Frame(width: 620, height: 620)
        // (centre x, centre y, tilt degrees, appears at ms)
        let polaroids: [(x: Double, y: Double, tilt: Double, at: Double)] = [
            (-110, -370, -7, 0),
            (130, 90, 5, 1500),
            (-70, 500, -3, 3000),
        ]
        var layers: [EditorLayer] = []
        var slots: [TemplateManifest.Slot] = []
        for (index, p) in polaroids.enumerated() {
            let frameTransform = EditorTransform(x: p.x, y: p.y, scale: 1, rotation: p.tilt)
            let enter = PresetBinding(kind: .zoom, durationMs: 500, easing: "easeOut")
            layers.append(EditorLayer(
                id: "frame-\(index + 1)", kind: "shape", fill: "#FFFFFFff", frame: frameSize,
                timing: V2Timing(start: p.at, duration: total - p.at), inPreset: enter, transform: frameTransform
            ))
            // The photo sits 70 px above the frame's centre (a thicker white border at the bottom, like a polaroid).
            let photoCentre = frameTransform.canvasPoint(dx: 0, dy: -70)
            layers.append(EditorLayer(
                id: "slot-\(index + 1)", kind: "image", assetId: "photo", fill: nil, frame: photoSize,
                timing: V2Timing(start: p.at, duration: total - p.at), inPreset: enter,
                transform: EditorTransform(x: photoCentre.x, y: photoCentre.y, scale: 1, rotation: p.tilt)
            ))
            slots.append(TemplateManifest.Slot(id: "photo-\(index + 1)", kind: "media", layerId: "slot-\(index + 1)",
                                               label: "Photo \(index + 1)", durationMs: Int(total - p.at), required: true))
        }
        layers.append(EditorLayer(
            id: "title", kind: "text", frame: V2Frame(width: 900, height: 200), timing: V2Timing(start: 0, duration: total),
            text: EditorTextLayer(text: "Our Day", fontFamily: "Helvetica", fontSize: 96, color: "#1B1B1Bff", layout: centered),
            transform: EditorTransform(x: 0, y: -850, scale: 1, rotation: 0)
        ))
        slots.append(TemplateManifest.Slot(id: "title", kind: "text", layerId: "title", label: "Title", durationMs: nil, required: false))
        let music: V2Asset = .audio(V2AudioAsset(id: "bgm", uri: "assets/bgm.m4a", mimeType: "audio/mp4", duration: total))
        let soundtrack = V2AudioDomain(sampleRate: 48000, tracks: [
            V2AudioTrack(id: "music", pan: 0, muted: false, clips: [
                V2AudioClip(id: "bgm-clip", assetId: "bgm", timing: V2AudioClipTiming(start: 0, duration: total), trim: V2AudioClipTrim(start: 0, end: nil), playbackRate: 1),
            ]),
        ])
        return Template(
            slug: "polaroid-collage",
            manifest: TemplateManifest(
                formatVersion: 2, minAppVersion: "1.0", name: "Polaroid Collage",
                composition: .init(width: Int(width), height: Int(height), durationMs: Int(total)),
                fonts: ["Helvetica"], builtinAssets: [], music: .init(title: "Demo Track", artist: "Neonix"), slots: slots
            ),
            document: EditorDocument(
                id: "polaroid-collage", composition: V2Composition(width: width, height: height, fps: 30, background: "#F1E6D3"),
                assets: [photo, music], layers: layers, audio: soundtrack
            )
        )
    }

    static var all: [Template] { [photoSlideshow, videoHighlights] + demos + [polaroidCollage] }
}

final class TemplateFixturesTests: XCTestCase {
    /// <repo>/templates, found from this file's path (tests run on the Mac, so the repo is readable).
    private var templatesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("templates", isDirectory: true)
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value) + Data("\n".utf8)
    }

    func testStarterTemplatesAreValidAndMatchFilesOnDisk() throws {
        let write = ProcessInfo.processInfo.environment["WRITE_TEMPLATES"] == "1"
        for template in StarterTemplates.all {
            try TemplatePackageLoader.validate(manifest: template.manifest, document: template.document)  // documents only; files are checked by load(directory:) below

            // The real compile pipeline accepts it. Presets wrap a layer in an invisible group (CLAUDE.md,
            // "Group layers compose by real nesting"), so there can be more compiled layers than authored ones,
            // but every authored layer must survive under its own id.
            let compiledIds = Set(compile(template.document).layers.map(\.id))
            for layer in template.document.layers {
                XCTAssertTrue(compiledIds.contains(layer.id), "\(template.slug): \(layer.id) missing after compile")
            }

            let directory = templatesDirectory.appendingPathComponent(template.slug, isDirectory: true)
            let files = [("manifest.json", try encoded(template.manifest)), ("document.json", try encoded(template.document))]
            for (name, data) in files {
                let url = directory.appendingPathComponent(name)
                if write {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try data.write(to: url)
                } else {
                    XCTAssertEqual(try Data(contentsOf: url), data, "\(template.slug)/\(name) is stale — regenerate (see file header)")
                }
            }

            // And the files on disk load exactly like a downloaded package would.
            if !write {
                let package = try TemplatePackageLoader.load(directory: directory)
                XCTAssertEqual(package.manifest.slots.count, template.manifest.slots.count)
                XCTAssertEqual(package.document.layers.count, template.document.layers.count)
            }
        }
    }

    func testLoaderRejectsBadPackages() throws {
        let good = StarterTemplates.photoSlideshow

        var wrongKind = good.manifest
        wrongKind.slots[0].kind = "text"
        XCTAssertThrowsError(try TemplatePackageLoader.validate(manifest: wrongKind, document: good.document))

        var dangling = good.manifest
        dangling.slots[0].layerId = "missing"
        XCTAssertThrowsError(try TemplatePackageLoader.validate(manifest: dangling, document: good.document))

        var remote = good.document
        remote.assets = [.image(V2ImageAsset(id: "photo", uri: "https://evil.example/x.jpg", width: 10, height: 10))]
        XCTAssertThrowsError(try TemplatePackageLoader.validate(manifest: good.manifest, document: remote))

        XCTAssertTrue(TemplatePackageLoader.isSafeAssetURI("assets/bgm.m4a"))
        XCTAssertTrue(TemplatePackageLoader.isSafeAssetURI("photo.jpg"))
        for bad in ["../x.jpg", "/etc/passwd", "a/../../b", "file:///x", "a\\b"] {
            XCTAssertFalse(TemplatePackageLoader.isSafeAssetURI(bad), bad)
        }
    }
}
