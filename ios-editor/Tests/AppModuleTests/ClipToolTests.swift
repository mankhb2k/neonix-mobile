import XCTest
import UIKit
@testable import NeonixEditor

/// Which tools the Edit row shows for each kind of selection, and in what order (`ClipTool`).
final class ClipToolTests: XCTestCase {
    func testAVideoWithSoundShowsEverythingInPriorityOrder() {
        XCTAssertEqual(ClipTool.tools(for: .video, hasAudio: true), [
            .split, .volume, .speed, .animation, .adjust, .filter, .transform, .opacity, .crop,
            .replace, .duplicate, .overlay, .removeBackground, .unlink,
        ])
    }

    func testAVideoWithoutSoundHasNoVolumeOrUnlink() {
        let tools = ClipTool.tools(for: .video, hasAudio: false)
        for hidden in [ClipTool.volume, .unlink] { XCTAssertFalse(tools.contains(hidden), "\(hidden)") }
        XCTAssertEqual(tools.first, .split)
        XCTAssertTrue(tools.contains(.speed))
    }

    func testAPhotoHasNoSoundOrSpeedTools() {
        XCTAssertNil(ClipTool(rawValue: "extract-audio"), "Extract Audio was removed from the row (user 2026-10-12)")
        XCTAssertEqual(ClipTool.tools(for: .image, hasAudio: true), [
            .split, .animation, .adjust, .filter, .transform, .opacity, .crop, .replace, .duplicate, .overlay, .removeBackground,
        ])
    }

    func testATextClipFollowsTheUsersList() {
        // Split, Style, Animation, Duplicate, Transform (Delete pinned); Edit text stays first.
        XCTAssertEqual(ClipTool.tools(for: .text, hasAudio: false), [.editText, .split, .style, .animation, .duplicate, .transform])
        XCTAssertNil(ClipTool(rawValue: "lasting-text"), "Lasting text was dropped (user 2026-10-12)")
        XCTAssertFalse(ClipTool.style.isBuilt(for: .text))
    }

    func testAnAudioClipHasSoundTools() {
        XCTAssertEqual(ClipTool.tools(for: .audio, hasAudio: false), [.split, .volume, .speed, .duplicate])
    }

    func testDeleteIsPinnedNotPartOfTheScrollingRow() {
        for kind in [ClipKind.video, .image, .text, .audio, .other] {
            XCTAssertFalse(ClipTool.tools(for: kind, hasAudio: true).contains(.delete), "\(kind)")
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
