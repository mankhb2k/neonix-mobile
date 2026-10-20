import XCTest
@testable import NeonixEditor

/// `AnimationPreview`: what the Animation sheet's tiles show of a preset at a moment.
final class AnimationPreviewTests: XCTestCase {
    private func preset(_ id: String) throws -> AnimationPreset { try XCTUnwrap(AnimationCatalog.preset(id: id)) }

    func testAnEntranceRunsFromTheOffsetStartToRest() throws {
        let slide = try preset("slide-left")
        let start = AnimationPreview.pose(of: slide, slot: .in, progress: 0)
        XCTAssertEqual(start.x, -0.4, accuracy: 1e-9, "starts off to the left")
        XCTAssertEqual(start.opacity, 0, accuracy: 1e-9)
        let rest = AnimationPreview.pose(of: slide, slot: .in, progress: 1)
        XCTAssertEqual(rest, AnimationPreview.Pose(), "ends exactly at rest")
        let middle = AnimationPreview.pose(of: slide, slot: .in, progress: 0.5)
        XCTAssertTrue(middle.x > -0.4 && middle.x < 0, "in between")
    }

    func testAnExitIsTheEntrancePlayedBackwards() throws {
        let zoom = try preset("zoom-in")
        XCTAssertEqual(AnimationPreview.pose(of: zoom, slot: .out, progress: 0), AnimationPreview.Pose(), "an exit starts at rest")
        let end = AnimationPreview.pose(of: zoom, slot: .out, progress: 1)
        XCTAssertEqual(end.scaleX, 0.5, accuracy: 1e-9, "and ends where the entrance began")
        XCTAssertEqual(end.opacity, 0, accuracy: 1e-9)
    }

    func testAComboIsOneCycleThatComesBackToWhereItStarted() throws {
        let pulse = try preset("pulse")
        XCTAssertEqual(AnimationPreview.pose(of: pulse, slot: .combo, progress: 0).scaleX, 1, accuracy: 1e-9)
        XCTAssertEqual(AnimationPreview.pose(of: pulse, slot: .combo, progress: 0.5).scaleX, 1.08, accuracy: 1e-9)
        XCTAssertEqual(AnimationPreview.pose(of: pulse, slot: .combo, progress: 1).scaleX, 1, accuracy: 1e-9)
        let sway = try preset("sway")
        XCTAssertEqual(AnimationPreview.pose(of: sway, slot: .combo, progress: 0.5).rotation, 5, accuracy: 1e-9)
    }

    func testEveryPresetHasAPoseAtBothEndsAndOnlyKnownChannels() {
        let known: Set<String> = ["opacity", "transform.scale.x", "transform.scale.y", "transform.translate.x", "transform.translate.y", "transform.rotate.z"]
        for preset in AnimationCatalog.all {
            XCTAssertTrue(preset.channels.allSatisfy { known.contains($0.path) }, "\(preset.id) uses a channel the preview does not draw")
            for slot in preset.slots {
                for progress in [0.0, 0.5, 1.0] {
                    let pose = AnimationPreview.pose(of: preset, slot: slot, progress: progress)
                    XCTAssertTrue(pose.opacity >= 0 && pose.opacity <= 1.0001, "\(preset.id) \(slot) \(progress)")
                }
            }
        }
    }

    func testTheLoopHoldsAtRestBeforeRepeatingAndTheExitWaitsFirst() throws {
        let fade = try preset("fade")
        XCTAssertEqual(AnimationPreview.progress(of: fade, slot: .in, atSeconds: 0), 0)
        XCTAssertEqual(AnimationPreview.progress(of: fade, slot: .in, atSeconds: 0.7), 1, accuracy: 1e-9)
        XCTAssertEqual(AnimationPreview.progress(of: fade, slot: .in, atSeconds: 1.2), 1, "a beat at rest before it loops")
        XCTAssertEqual(AnimationPreview.progress(of: fade, slot: .out, atSeconds: 0.2), 0, "the exit waits at rest first")
        XCTAssertEqual(AnimationPreview.progress(of: fade, slot: .out, atSeconds: 1.2), 1, accuracy: 1e-9)
        XCTAssertNotNil(bundledURL(filename: "preview-animation.png"), "the preview picture is in the app bundle")
    }
}
