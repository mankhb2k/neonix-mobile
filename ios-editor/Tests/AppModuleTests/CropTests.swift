import XCTest
@testable import NeonixEditor

/// Crop tool: the command, the maths that places the region in the frame, and the stored shape.
final class CropTests: XCTestCase {
    private func project(image: Bool = false) -> V2Project {
        let asset: V2Asset = image
            ? .image(V2ImageAsset(id: "a", uri: "a.jpg", width: 4000, height: 3000))
            : .video(V2VideoAsset(id: "a", uri: "a.mov", width: 1080, height: 1920, duration: 5000))
        let payload: V2LayerPayload = image ? .image(V2ImagePayload(assetId: "a")) : .video(V2VideoPayload(assetId: "a", trimStart: 0))
        let layer = V2Layer(id: "clip", order: 0, frame: V2Frame(width: 360, height: 640), transform: .identity,
                            timing: V2Timing(start: 0, duration: 3000), payload: payload)
        return V2Project(composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"), assets: [asset], layers: [layer])
    }

    private let half = V2Crop(x: 0.25, y: 0.25, width: 0.5, height: 0.5, rotation: nil, flipped: nil)

    // MARK: Command

    func testTheCommandStoresTheRegionOnAVideoAndAPhoto() {
        XCTAssertEqual(SetClipCropCommand(layerId: "clip", crop: half).apply(to: project()).layers[0].crop, half)
        XCTAssertEqual(SetClipCropCommand(layerId: "clip", crop: half).apply(to: project(image: true)).layers[0].crop, half)
    }

    func testACropThatChangesNothingIsStoredAsNoneAndNilClearsIt() {
        let cropped = SetClipCropCommand(layerId: "clip", crop: half).apply(to: project())
        XCTAssertNil(SetClipCropCommand(layerId: "clip", crop: .full).apply(to: cropped).layers[0].crop)
        XCTAssertNil(SetClipCropCommand(layerId: "clip", crop: nil).apply(to: cropped).layers[0].crop)
    }

    func testARotationOrAFlipAloneIsAnActualCrop() {
        let turned = V2Crop(x: 0, y: 0, width: 1, height: 1, rotation: 5, flipped: nil)
        XCTAssertFalse(turned.isIdentity)
        XCTAssertEqual(SetClipCropCommand(layerId: "clip", crop: turned).apply(to: project()).layers[0].crop, turned)
        XCTAssertFalse(V2Crop(x: 0, y: 0, width: 1, height: 1, rotation: nil, flipped: true).isIdentity)
    }

    func testBadRegionsAndOtherLayersAreLeftAlone() {
        let p = project()
        for bad in [V2Crop(x: 0.8, y: 0, width: 0.5, height: 1, rotation: nil, flipped: nil),
                    V2Crop(x: 0, y: 0, width: 0.01, height: 0.5, rotation: nil, flipped: nil),
                    V2Crop(x: -0.2, y: 0, width: 0.5, height: 0.5, rotation: nil, flipped: nil)] {
            XCTAssertNil(SetClipCropCommand(layerId: "clip", crop: bad).apply(to: p).layers[0].crop)
        }
        XCTAssertNil(SetClipCropCommand(layerId: "nope", crop: half).apply(to: p).layers[0].crop)
        let text = AddTextLayerCommand(layerId: "t", text: "Hi", atMs: 0).apply(to: p)
        let after = SetClipCropCommand(layerId: "t", crop: half).apply(to: text)
        XCTAssertNil(after.layers.first { $0.id == "t" }?.crop)
    }

    func testReplacingTheFootageDropsTheOldRegion() {
        let cropped = SetClipCropCommand(layerId: "clip", crop: half).apply(to: project())
        let other = V2Asset.video(V2VideoAsset(id: "b", uri: "b.mov", width: 1920, height: 1080, duration: 4000))
        XCTAssertNil(ReplaceClipCommand(layerId: "clip", asset: other).apply(to: cropped).layers[0].crop)
    }

    func testTheStoredShapeSurvivesJSON() throws {
        let p = SetClipCropCommand(layerId: "clip", crop: V2Crop(x: 0.1, y: 0.2, width: 0.5, height: 0.6, rotation: -7, flipped: true)).apply(to: project())
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(V2Project.self, from: data)
        XCTAssertEqual(back.layers[0].crop, V2Crop(x: 0.1, y: 0.2, width: 0.5, height: 0.6, rotation: -7, flipped: true))
    }

    // MARK: Layout

    func testTheMiddleHalfOfAFittedPictureFillsTheFrameAsLargeAsItFits() throws {
        // A 9:16 picture in a 360 x 640 frame: its middle half is 180 x 320 points, shown twice as large.
        let plan = try XCTUnwrap(CropLayout.plan(frame: CGSize(width: 360, height: 640), pictureAspect: 9.0 / 16, cover: false, crop: half))
        XCTAssertEqual(plan.scale, 2, accuracy: 0.001)
        XCTAssertEqual(plan.offset.width, 0, accuracy: 0.001)
        XCTAssertEqual(plan.offset.height, 0, accuracy: 0.001)
        XCTAssertEqual(plan.visible.width, 360, accuracy: 0.001)
        XCTAssertEqual(plan.visible.height, 640, accuracy: 0.001)
        XCTAssertEqual(plan.zoom, 1, accuracy: 0.0001)
    }

    func testASquareRegionOfATallPictureShowsAsASquareCentredInTheFrame() throws {
        // The top-left 1:1 region (in pixels) of a 9:16 picture: 360 x 360 points of it, in a 360 x 640 frame: it already fits, no scaling.
        let region = V2Crop(x: 0, y: 0, width: 1, height: 9.0 / 16, rotation: nil, flipped: nil)
        let plan = try XCTUnwrap(CropLayout.plan(frame: CGSize(width: 360, height: 640), pictureAspect: 9.0 / 16, cover: false, crop: region))
        XCTAssertEqual(plan.visible.width, plan.visible.height, accuracy: 0.001)
        XCTAssertEqual(plan.visible.midY, 320, accuracy: 0.001)
        XCTAssertEqual(plan.scale, 1, accuracy: 0.001)
        // Its centre is 180 points above the frame's, so the picture slides down by that much to bring it to the middle.
        XCTAssertEqual(plan.offset.height, 320 - 180, accuracy: 0.001)
    }

    func testAStraightenZoomCoversTheTurnedCorners() throws {
        let turned = V2Crop(x: 0, y: 0, width: 1, height: 1, rotation: 10, flipped: nil)
        let plan = try XCTUnwrap(CropLayout.plan(frame: CGSize(width: 360, height: 640), pictureAspect: 9.0 / 16, cover: false, crop: turned))
        XCTAssertGreaterThan(plan.zoom, 1)
        XCTAssertEqual(plan.zoom, cos(10 * .pi / 180) + sin(10 * .pi / 180) * (16.0 / 9), accuracy: 0.0001)
    }

    func testNothingIsPlannedForAnEmptyFrameOrRegion() {
        XCTAssertNil(CropLayout.plan(frame: .zero, pictureAspect: 1, cover: false, crop: half))
        XCTAssertNil(CropLayout.plan(frame: CGSize(width: 10, height: 10), pictureAspect: 1, cover: false,
                                     crop: V2Crop(x: 0, y: 0, width: 0, height: 0.5, rotation: nil, flipped: nil)))
    }
}
