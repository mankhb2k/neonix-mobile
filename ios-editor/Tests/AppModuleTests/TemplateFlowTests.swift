import XCTest
@testable import NeonixEditor

@MainActor
final class TemplateFlowTests: XCTestCase {
    private func repoTemplate(_ slug: String) throws -> TemplatePackage {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("templates/\(slug)")
        return try TemplatePackageLoader.load(directory: directory)
    }

    private func photo(_ id: String) -> V2Asset { .image(V2ImageAsset(id: id, uri: "\(id).jpg", width: 1000, height: 1500)) }
    private func video(_ id: String) -> V2Asset { .video(V2VideoAsset(id: id, uri: "\(id).mov", width: 1080, height: 1920, duration: 20_000)) }

    // MARK: Slot rules

    func testSlotRulesForPhotosAndVideos() {
        XCTAssertTrue(SlotRules.canUse(.photo, durationMs: 0, forSlotMs: 3000))
        XCTAssertTrue(SlotRules.canUse(.video, durationMs: 3000, forSlotMs: 3000))
        XCTAssertTrue(SlotRules.canUse(.video, durationMs: 2970, forSlotMs: 3000), "a few ms short is rounding, not a short video")
        XCTAssertFalse(SlotRules.canUse(.video, durationMs: 2500, forSlotMs: 3000))
        XCTAssertTrue(SlotRules.needsCrop(.video, durationMs: 9000, slotMs: 3000))
        XCTAssertFalse(SlotRules.needsCrop(.video, durationMs: 3000, slotMs: 3000))
        XCTAssertFalse(SlotRules.needsCrop(.photo, durationMs: 0, slotMs: 3000))
        XCTAssertEqual(SlotRules.clampedCropStart(8000, mediaMs: 9000, slotMs: 3000), 6000)
        XCTAssertEqual(SlotRules.clampedCropStart(-5, mediaMs: 9000, slotMs: 3000), 0)
    }

    // MARK: Filling

    func testFillingPhotoSlotsKeepsEverythingElse() throws {
        let package = try repoTemplate("photo-slideshow")
        let fills = (1...4).map { SlotFill(slotId: "photo-\($0)", kind: .photo, asset: photo("m\($0)"), trimStartMs: 0) }
        let filled = try TemplateFiller.fill(package, with: fills)

        let slot2 = try XCTUnwrap(filled.document.layers.first { $0.id == "slot-2" })
        XCTAssertEqual(slot2.kind, "image")
        XCTAssertEqual(slot2.assetId, "m2")
        XCTAssertEqual(slot2.timing.start, 3000, "timing is the creator's")
        XCTAssertEqual(slot2.inPreset?.kind, .zoom, "presets are the creator's")
        XCTAssertFalse(filled.document.assets.contains { $0.id == "photo" }, "the placeholder photo is gone")
        XCTAssertTrue(filled.document.assets.contains { $0.id == "bgm" }, "the music stays")
        XCTAssertEqual(filled.document.audio?.tracks.first?.clips.count, 1)
        XCTAssertTrue(filled.document.layers.contains { $0.id == "title" }, "text layer stays")
    }

    func testVideoIntoAPhotoSlotBecomesAVideoLayerWithItsCrop() throws {
        let package = try repoTemplate("photo-slideshow")
        let filled = try TemplateFiller.fill(package, with: [
            SlotFill(slotId: "photo-1", kind: .video, asset: video("clip"), trimStartMs: 4000),
            SlotFill(slotId: "photo-2", kind: .photo, asset: photo("p"), trimStartMs: 0),
        ])
        XCTAssertEqual(filled.document.layers.first { $0.id == "slot-1" }?.kind, "video")
        XCTAssertEqual(filled.trims, ["slot-1": 4000])

        let project = TemplateProjectBuilder.project(document: filled.document, trims: filled.trims)
        let layer = try XCTUnwrap(project.layers.first { $0.id == "slot-1" })
        guard case .video(let payload) = layer.payload else { return XCTFail("expected a video layer") }
        XCTAssertEqual(payload.trimStart, 4000)
        XCTAssertEqual(payload.assetId, "clip")
    }

    func testEmptyOptionalSlotsAreDroppedButRequiredOnesMustBeFilled() throws {
        let package = try repoTemplate("photo-slideshow")   // photo-1 and photo-2 required, 3 and 4 optional
        let two = (1...2).map { SlotFill(slotId: "photo-\($0)", kind: .photo, asset: photo("m\($0)"), trimStartMs: 0) }
        let filled = try TemplateFiller.fill(package, with: two)
        XCTAssertNil(filled.document.layers.first { $0.id == "slot-3" })
        XCTAssertNil(filled.document.layers.first { $0.id == "slot-4" })
        XCTAssertNotNil(filled.document.layers.first { $0.id == "slot-2" })

        XCTAssertThrowsError(try TemplateFiller.fill(package, with: [two[0]])) { error in
            guard case TemplateFillError.missing(let id) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(id, "photo-2")
        }
        XCTAssertThrowsError(try TemplateFiller.fill(package, with: [SlotFill(slotId: "nope", kind: .photo, asset: photo("x"), trimStartMs: 0)]))
    }

    func testBuiltProjectKeepsTheMusicAndPutsTextOnItsOwnLane() throws {
        let package = try repoTemplate("video-highlights")
        let fills = (1...3).map { SlotFill(slotId: "clip-\($0)", kind: .video, asset: video("v\($0)"), trimStartMs: Double($0) * 1000) }
        let filled = try TemplateFiller.fill(package, with: fills)
        let project = TemplateProjectBuilder.project(document: filled.document, trims: filled.trims)

        XCTAssertEqual(project.audio.tracks.first?.clips.count, 1, "soundtrack survives")
        let text = project.layers.filter { if case .text = $0.payload { return true } else { return false } }
        XCTAssertEqual(text.first?.order, 1)
        XCTAssertTrue(project.layers.filter { if case .video = $0.payload { return true } else { return false } }.allSatisfy { $0.order == 0 })
    }

    // MARK: Result screen changes (texts, music)

    func testTypedTextReplacesTheCreatorsTextAndNothingElse() throws {
        let package = try repoTemplate("photo-slideshow")
        let fills = (1...4).map { SlotFill(slotId: "photo-\($0)", kind: .photo, asset: photo("m\($0)"), trimStartMs: 0) }
        let filled = try TemplateFiller.fill(package, with: fills, texts: ["title": "Hello Da Nang"])
        let title = try XCTUnwrap(filled.document.layers.first { $0.id == "title" })
        XCTAssertEqual(title.text?.text, "Hello Da Nang")
        XCTAssertEqual(title.text?.fontFamily, "Helvetica", "style stays the creator's")
        XCTAssertEqual(title.text?.fontSize, 84)

        let untouched = try TemplateFiller.fill(package, with: fills)
        XCTAssertEqual(untouched.document.layers.first { $0.id == "title" }?.text?.text, "Summer Memories")
    }

    func testBuildTurnsMusicOffWithoutTouchingTheRest() throws {
        let package = try repoTemplate("photo-slideshow")
        let fills = (1...4).map { SlotFill(slotId: "photo-\($0)", kind: .photo, asset: photo("m\($0)"), trimStartMs: 0) }
        let on = try TemplateBuild.project(package: package, fills: fills, texts: [:], musicOn: true)
        let off = try TemplateBuild.project(package: package, fills: fills, texts: [:], musicOn: false)

        XCTAssertEqual(on.audio.tracks.map(\.muted), [false])
        XCTAssertEqual(off.audio.tracks.map(\.muted), [true])
        XCTAssertEqual(off.audio.tracks.first?.clips.count, 1, "the clip is still there, just muted")
        XCTAssertEqual(on.layers.count, off.layers.count)
    }

    func testBuildAppliesTextAndTrimsTogether() throws {
        let package = try repoTemplate("video-highlights")
        let fills = (1...3).map { SlotFill(slotId: "clip-\($0)", kind: .video, asset: video("v\($0)"), trimStartMs: 2500) }
        let project = try TemplateBuild.project(package: package, fills: fills, texts: ["caption": "Road trip"], musicOn: true)
        guard case .text(let payload)? = project.layers.first(where: { $0.id == "caption" })?.payload else { return XCTFail("caption layer missing") }
        XCTAssertEqual(payload.source.text, "Road trip")
        let trims = project.layers.compactMap { layer -> Double? in
            if case .video(let p) = layer.payload { return p.trimStart } else { return nil }
        }
        XCTAssertEqual(trims, [2500, 2500, 2500])
    }

    // MARK: Package assets

    func testPackageMusicIsCopiedIntoTheMediaFolderAndRewritten() throws {
        let package = try repoTemplate("photo-slideshow")
        let media = FileManager.default.temporaryDirectory.appendingPathComponent("media-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: media) }

        let relocated = try TemplateInstaller.relocatingAssets(of: package, templateId: "2d698750-0f4d", version: 1, into: media)
        let music = try XCTUnwrap(relocated.document.assets.first { $0.id == "bgm" })
        XCTAssertEqual(music.uri, "tpl-2d698750-v1-bgm.m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: media.appendingPathComponent(music.uri).path))
        XCTAssertEqual(relocated.document.assets.first { $0.id == "photo" }?.uri, "pexels-followingnyc-38428141.jpg", "bundled media is untouched")
    }

    // MARK: Export credit gate

    private func result(charged: Bool, balance: Int) throws -> APIExportResult {
        try NeonixAPIClient.decoder.decode(APIExportResult.self, from: Data(
            #"{"purchaseId":"p","owned":true,"charged":\#(charged),"creditsCharged":\#(charged ? 6 : 0),"balance":\#(balance)}"#.utf8))
    }

    private struct StubExporter: ProjectExporter {
        let available: Bool
        let log: ExportLog
        var isAvailable: Bool { available }
        func export(_ project: V2Project) async throws { log.exported += 1 }
    }
    final class ExportLog { var charged = 0; var exported = 0 }

    private let context = TemplateExportContext(templateId: "t", versionId: nil, creditCost: 6)

    func testOutOfCreditsStopsBeforeRendering() async throws {
        let log = ExportLog()
        let gate = ExportGate(
            charge: { _ in throw APIError.http(status: 402, code: "INSUFFICIENT_CREDITS", message: "Not enough credits") },
            exporter: StubExporter(available: true, log: log), chargesWithoutExporter: false)
        let project = compile(try repoTemplate("photo-slideshow").document)

        await gate.export(project: project, context: context)
        XCTAssertEqual(gate.alert?.title, "Not enough credits")
        XCTAssertEqual(log.exported, 0, "nothing is rendered without credits")
        XCTAssertFalse(gate.completed)
        XCTAssertFalse(gate.isWorking, "the button is released again")
    }

    func testChargeThenRender() async throws {
        let log = ExportLog()
        let paid = try result(charged: true, balance: 14)
        let gate = ExportGate(charge: { _ in log.charged += 1; return paid }, exporter: StubExporter(available: true, log: log), chargesWithoutExporter: false)
        await gate.export(project: compile(try repoTemplate("photo-slideshow").document), context: context)
        XCTAssertEqual(log.charged, 1)
        XCTAssertEqual(log.exported, 1)
        XCTAssertTrue(gate.completed)
        XCTAssertNil(gate.alert)
    }

    func testNetworkFailureDoesNotRender() async throws {
        let log = ExportLog()
        let gate = ExportGate(charge: { _ in throw URLError(.notConnectedToInternet) }, exporter: StubExporter(available: true, log: log), chargesWithoutExporter: false)
        await gate.export(project: compile(try repoTemplate("photo-slideshow").document), context: context)
        XCTAssertEqual(gate.alert?.title, "Couldn't check your credits")
        XCTAssertEqual(log.exported, 0)
    }

    func testReleaseBehaviourDoesNotTakeCreditsForAVideoItCannotMake() async throws {
        let log = ExportLog()
        let paid = try result(charged: true, balance: 14)
        let gate = ExportGate(charge: { _ in log.charged += 1; return paid }, exporter: UnavailableExporter(), chargesWithoutExporter: false)
        await gate.export(project: compile(try repoTemplate("photo-slideshow").document), context: context)
        XCTAssertEqual(log.charged, 0)
        XCTAssertEqual(gate.alert?.title, "Export isn't available yet")
    }

    func testDebugBehaviourChargesEvenWithoutAnExporter() async throws {
        let log = ExportLog()
        let paid = try result(charged: true, balance: 14)
        let gate = ExportGate(charge: { _ in log.charged += 1; return paid }, exporter: UnavailableExporter(), chargesWithoutExporter: true)
        await gate.export(project: compile(try repoTemplate("photo-slideshow").document), context: context)
        XCTAssertEqual(log.charged, 1, "the credit flow can be tried before the renderer exists")
        XCTAssertEqual(gate.alert?.title, "Export failed")
    }
}
