import XCTest
import UIKit
@testable import NeonixEditor

/// Which tools the Edit row shows for each kind of selection, and in what order (`ClipTool`).
final class ClipToolTests: XCTestCase {
    func testAVideoFollowsTheUsersList() {
        XCTAssertEqual(ClipTool.tools(for: .video), [
            .split, .transform, .volume, .delete, .animation, .graph, .speed, .adjust, .filter, .opacity, .mask, .crop,
            .replace, .duplicate, .overlay, .removeBackground, .freeze, .reverse, .unlink,
        ])
    }

    func testAPhotoHasNoSoundOrSpeedTools() {
        XCTAssertNil(ClipTool(rawValue: "extract-audio"), "Extract Audio was removed from the row (user 2026-10-12)")
        XCTAssertEqual(ClipTool.tools(for: .image), [
            .split, .transform, .animation, .delete, .graph, .adjust, .filter, .opacity, .mask, .crop, .replace, .duplicate, .overlay, .removeBackground,
        ])
    }

    func testATextClipFollowsTheUsersList() {
        // Edit text stays first (the only way to change the words), then Split, Transform, Delete 4th.
        XCTAssertEqual(ClipTool.tools(for: .text), [.editText, .split, .transform, .delete, .style, .animation, .graph, .duplicate])
        XCTAssertNil(ClipTool(rawValue: "lasting-text"), "Lasting text was dropped (user 2026-10-12)")
        XCTAssertTrue(ClipTool.style.isBuilt(for: .text), "Style opens the Text sheet on its Style tab")
    }

    func testAnAudioClipHasSoundTools() {
        XCTAssertEqual(ClipTool.tools(for: .audio), [.split, .volume, .fade, .delete, .duplicate, .beat, .speed])
    }

    func testGraphIsOnEveryRowButAudio() {
        for kind in [ClipKind.video, .image, .text, .sticker, .other] {
            XCTAssertTrue(ClipTool.tools(for: kind).contains(.graph), "\(kind)")
        }
        XCTAssertFalse(ClipTool.tools(for: .audio).contains(.graph))
    }

    func testDeleteIsAlwaysTheFourthTool() {
        for kind in [ClipKind.video, .image, .text, .sticker, .audio, .other] {
            XCTAssertEqual(ClipTool.tools(for: kind).firstIndex(of: .delete), 3, "\(kind)")
        }
    }

    func testEveryToolHasAnExistingSymbolAndAUniqueId() {
        let ids = ClipTool.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for tool in ClipTool.allCases {
            XCTAssertNotNil(UIImage(systemName: tool.symbol), "\(tool): \(tool.symbol)")
            XCTAssertFalse(tool.title.isEmpty)
        }
    }

    func testOnlyTheToolsThatWorkAreMarkedBuilt() {
        XCTAssertTrue(ClipTool.split.isBuilt(for: .video))
        XCTAssertTrue(ClipTool.filter.isBuilt(for: .video), "Filter is built (grid + Intensity)")
        XCTAssertTrue(ClipTool.opacity.isBuilt(for: .image))
        XCTAssertTrue(ClipTool.volume.isBuilt(for: .audio))
        XCTAssertTrue(ClipTool.volume.isBuilt(for: .video), "video volume is built (Volume only, no Fade)")
        XCTAssertFalse(ClipTool.fade.isBuilt(for: .video))
        XCTAssertTrue(ClipTool.animation.isBuilt(for: .video) && ClipTool.animation.isBuilt(for: .text) && ClipTool.animation.isBuilt(for: .sticker))
        XCTAssertFalse(ClipTool.animation.isBuilt(for: .audio))
        for kind in [ClipKind.video, .image, .text, .sticker] { XCTAssertTrue(ClipTool.duplicate.isBuilt(for: kind), "\(kind)") }
        XCTAssertFalse(ClipTool.duplicate.isBuilt(for: .audio), "audio duplicate waits for the audio batch")
        for kind in [ClipKind.video, .image] { XCTAssertTrue(ClipTool.replace.isBuilt(for: kind) && ClipTool.overlay.isBuilt(for: kind)) }
        XCTAssertFalse(ClipTool.replace.isBuilt(for: .text))
        XCTAssertTrue(ClipTool.speed.isBuilt(for: .video))
        XCTAssertFalse(ClipTool.speed.isBuilt(for: .audio), "audio speed is not built yet")
        XCTAssertTrue(ClipTool.fade.isBuilt(for: .audio), "audio fade opens the Volume / Fade popup on Fade")
        XCTAssertFalse(ClipTool.beat.isBuilt(for: .audio), "audio beat is a label only")
        XCTAssertTrue(ClipTool.crop.isBuilt(for: .video) && ClipTool.crop.isBuilt(for: .image), "Crop is built for video and photo")
        XCTAssertFalse(ClipTool.crop.isBuilt(for: .text))
        XCTAssertTrue(ClipTool.mask.isBuilt(for: .video) && ClipTool.mask.isBuilt(for: .image), "Mask is built for video and photo")
        XCTAssertFalse(ClipTool.mask.isBuilt(for: .text))
        XCTAssertTrue(ClipTool.removeBackground.isBuilt(for: .video))
        for notYet in [ClipTool.unlink] {
            XCTAssertFalse(notYet.isBuilt(for: .video), "\(notYet)")
        }
    }
}
