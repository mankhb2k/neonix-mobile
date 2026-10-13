import XCTest
import UIKit
@testable import NeonixEditor

/// Which tools the Edit row shows for each kind of selection, and in what order (`ClipTool`).
final class ClipToolTests: XCTestCase {
    func testAVideoFollowsTheUsersList() {
        XCTAssertEqual(ClipTool.tools(for: .video), [
            .split, .transform, .volume, .delete, .animation, .graph, .speed, .adjust, .filter, .opacity, .crop,
            .replace, .duplicate, .overlay, .removeBackground, .unlink,
        ])
    }

    func testAPhotoHasNoSoundOrSpeedTools() {
        XCTAssertNil(ClipTool(rawValue: "extract-audio"), "Extract Audio was removed from the row (user 2026-10-12)")
        XCTAssertEqual(ClipTool.tools(for: .image), [
            .split, .transform, .animation, .delete, .graph, .adjust, .filter, .opacity, .crop, .replace, .duplicate, .overlay, .removeBackground,
        ])
    }

    func testATextClipFollowsTheUsersList() {
        // Edit text stays first (the only way to change the words), then Split, Transform, Delete 4th.
        XCTAssertEqual(ClipTool.tools(for: .text), [.editText, .split, .transform, .delete, .style, .animation, .graph, .duplicate])
        XCTAssertNil(ClipTool(rawValue: "lasting-text"), "Lasting text was dropped (user 2026-10-12)")
        XCTAssertFalse(ClipTool.style.isBuilt(for: .text))
    }

    func testAnAudioClipHasSoundTools() {
        XCTAssertEqual(ClipTool.tools(for: .audio), [.split, .volume, .speed, .delete, .duplicate])
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
        XCTAssertFalse(ClipTool.volume.isBuilt(for: .video), "video volume is not built yet")
        for notYet in [ClipTool.speed, .animation, .crop, .replace, .duplicate, .overlay, .removeBackground, .unlink, .style] {
            XCTAssertFalse(notYet.isBuilt(for: .video), "\(notYet)")
        }
    }
}
