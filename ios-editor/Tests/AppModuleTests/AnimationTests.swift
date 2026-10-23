import AVFoundation
import CoreImage
import SwiftUI
import XCTest
@testable import NeonixEditor

/// The Animation tool's model: presets -> atomic V2 tracks, nested wrappers per slot, and what every edit does to them.
final class AnimationTests: XCTestCase {
    func testEditorTransitionIntentRoundTripsAndCompilesToV2Groups() throws {
        let json = ##"{"id":"edit","composition":{"width":96,"height":170,"fps":30,"background":"#000000"},"assets":[],"layers":[{"id":"a","kind":"video","assetId":"file","frame":{"width":96,"height":170},"timing":{"start":0,"duration":500}},{"id":"b","kind":"video","assetId":"file","frame":{"width":96,"height":170},"timing":{"start":500,"duration":500}}],"transitions":[{"outgoingId":"a","incomingId":"b","kind":"push","durationMs":200}]}"##
        let document = try JSONDecoder().decode(EditorDocument.self, from: Data(json.utf8))
        let restored = try JSONDecoder().decode(EditorDocument.self, from: JSONEncoder().encode(document))
        XCTAssertEqual(restored.transitions, [EditorTransitionIntent(outgoingId: "a", incomingId: "b", kind: .push, durationMs: 200)])
        let project = compile(restored)
        XCTAssertEqual(project.layers.first { $0.id == "b" }?.timing.start, 500, "the editor document keeps its split timing")
        XCTAssertEqual(TransitionWrappers.applied(for: "b", in: project.layers)?.kind, .push)
        XCTAssertEqual(project.layers.filter { $0.type == "video" }.count, 2, "transition must not create a media clip")
        XCTAssertTrue(project.layers.contains { $0.type == "group" && $0.tracks?.contains { $0.path == "transform.translate.x" } == true })
        let rendered = TransitionRenderPlan.compile(project)
        XCTAssertEqual(rendered.layers.map(\.id), project.layers.map(\.id), "render planning must retain V2 layer identity and order")
        let renderTransition = try XCTUnwrap(rendered.layers.first { TransitionWrappers.parse($0.id)?.incomingId == "b" })
        XCTAssertEqual(renderTransition.timing.start, 400, "only the render projection spans across the split")
        XCTAssertEqual(renderTransition.timing.duration, 600)
    }

    func testTransitionIntentStaysOutsideAuthoringV2AndUndoSnapshot() throws {
        let source = transitionProject()
        let authored = EditorTransitionIntent(outgoingId: "a", incomingId: "b", kind: .push, durationMs: 200)
        let renderProject = TransitionWrappers.compiling([authored], into: source)
        let extracted = TransitionWrappers.extracting(from: renderProject)

        XCTAssertEqual(extracted.transitions, [authored])
        XCTAssertFalse(extracted.project.layers.contains { TransitionWrappers.parse($0.id) != nil })
        XCTAssertFalse(extracted.project.layers.contains { TransitionWrappers.parseOutgoing($0.id) != nil })
        XCTAssertEqual(extracted.project.layers.filter { $0.type == "video" }.map(\.id), ["a", "b", "c"])

        var history = EditorHistory()
        history.record(current: extracted.project, transitions: [])
        let restored = try XCTUnwrap(history.undo(current: renderProject, transitions: [authored]))
        XCTAssertTrue(restored.transitions.isEmpty)
        XCTAssertFalse(restored.project.layers.contains { TransitionWrappers.parse($0.id) != nil })

        let recompiled = TransitionWrappers.compiling(extracted.transitions, into: extracted.project)
        XCTAssertEqual(TransitionWrappers.applied(in: recompiled.layers)["b"], authored)
    }

    @MainActor
    func testOfflineExportRendersTransitionWithAnimationAndKeyframes() async throws {
        let name = "13792197_1080_1920_30fps.mp4"
        let asset = V2Asset.video(V2VideoAsset(id: "footage", uri: name, mimeType: "video/mp4",
                                               width: 1080, height: 1920, duration: 31_200, fps: 30,
                                               integrity: nil, audio: nil))
        let soundtrack = V2Asset.audio(V2AudioAsset(id: "music", uri: "audio-demo.mp3", mimeType: "audio/mpeg",
                                                 duration: 262_530, sampleRate: nil, channels: nil, integrity: nil))
        let ownTrack = V2Track(id: "own-move", path: "transform.translate.x", keyframes: [
            V2Keyframe(time: .absolute(0), value: 0), V2Keyframe(time: .absolute(300), value: 10)
        ], animation: nil)
        let first = V2Layer(id: "a", order: 0, frame: V2Frame(width: 96, height: 170), transform: .identity,
                            timing: V2Timing(start: 0, duration: 300), payload: .video(V2VideoPayload(assetId: "footage")))
        let second = V2Layer(id: "b", order: 0, frame: V2Frame(width: 96, height: 170), transform: .identity,
                             timing: V2Timing(start: 300, duration: 300), tracks: [ownTrack],
                             payload: .video(V2VideoPayload(assetId: "footage", trimStart: 1000)))
        var project = V2Project(composition: V2Composition(width: 96, height: 170, fps: 30, background: "#000000"),
                                assets: [asset, soundtrack], layers: [first, second])
        project.audio = V2AudioDomain(sampleRate: 48_000, tracks: [V2AudioTrack(
            id: "music-track", gainDb: nil, pan: 0, muted: false,
            clips: [V2AudioClip(id: "music-clip", assetId: "music", timing: V2AudioClipTiming(start: 0, duration: 450),
                                trim: V2AudioClipTrim(start: 0, end: nil), playbackRate: 1, enabled: true,
                                gainDb: nil, pan: nil, fadeIn: nil, fadeOut: nil)]
        )])
        project = SetAnimationCommand(layerId: "b", slot: .in, presetId: "fade", durationMs: 150).apply(to: project)
        func averagePixel(_ image: CGImage) throws -> [UInt8] {
            let input = CIImage(cgImage: image)
            let average = try XCTUnwrap(CIFilter(name: "CIAreaAverage"))
            average.setValue(input, forKey: kCIInputImageKey)
            average.setValue(CIVector(cgRect: input.extent), forKey: kCIInputExtentKey)
            var pixel = [UInt8](repeating: 0, count: 4)
            CIContext().render(try XCTUnwrap(average.outputImage), toBitmap: &pixel, rowBytes: 4,
                               bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8,
                               colorSpace: CGColorSpaceCreateDeviceRGB())
            return pixel
        }
        var transitionFrameColors: [TransitionKind: [UInt8]] = [:]
        for kind in TransitionKind.allCases {
            let transitioned = SetTransitionCommand(outgoingId: "a", incomingId: "b", kind: kind, durationMs: 150).apply(to: project)
            XCTAssertEqual(TransitionWrappers.applied(for: "b", in: transitioned.layers)?.kind, kind)
            XCTAssertEqual(transitioned.layers.first { $0.id == "b" }?.tracks?.first?.id, "own-move")
            let output = try await OfflineProjectExporter().export(
                transitioned, settings: ExportSettings(resolution: .p480, frameRate: 30, bitrateMbps: 5))
            defer { try? FileManager.default.removeItem(at: output) }
            XCTAssertGreaterThan(try Data(contentsOf: output).count, 1000, kind.rawValue)
            let exported = AVURLAsset(url: output)
            let videoTracks = try await exported.loadTracks(withMediaType: .video)
            XCTAssertEqual(videoTracks.count, 1, kind.rawValue)
            let audioTracks = try await exported.loadTracks(withMediaType: .audio)
            XCTAssertEqual(audioTracks.count, 1, kind.rawValue)
            let duration = try await exported.load(.duration)
            XCTAssertEqual(CMTimeGetSeconds(duration), 0.6, accuracy: 0.12,
                           "\(kind.rawValue): a transition does not compress the editor timeline")
            let frameReport = try inspectExportedFrames(exported, expectedFPS: 30)
            NSLog("[TransitionFrameTest] kind=%@ frames=%d measuredFPS=%.3f maxBlackCoverage=%.4f fullBlackFrames=%d",
                  kind.rawValue, frameReport.frameCount, frameReport.measuredFPS, frameReport.maxBlackCoverage,
                  frameReport.fullBlackFrameCount)
            XCTAssertGreaterThanOrEqual(frameReport.frameCount, 16, "\(kind.rawValue): export lost decoded frames")
            XCTAssertLessThanOrEqual(frameReport.frameCount, 20, "\(kind.rawValue): unexpected duplicate frames")
            XCTAssertEqual(frameReport.measuredFPS, 30, accuracy: 1.5, "\(kind.rawValue): output frame cadence")
            if kind == .fadeBlack {
                XCTAssertLessThanOrEqual(frameReport.maxBlackCoverage, 1,
                                         "Fade intentionally reaches full black at its midpoint")
                XCTAssertLessThanOrEqual(frameReport.fullBlackFrameCount, 1,
                                         "Fade should have at most one fully black frame at 30 fps")
            } else {
                XCTAssertLessThan(frameReport.maxBlackCoverage, 0.98,
                                  "\(kind.rawValue): an unintended full-screen black frame was exported")
                XCTAssertEqual(frameReport.fullBlackFrameCount, 0,
                               "\(kind.rawValue): no output frame may be fully black")
            }
            let frameGenerator = AVAssetImageGenerator(asset: exported)
            frameGenerator.appliesPreferredTrackTransform = true
            frameGenerator.requestedTimeToleranceBefore = .zero
            frameGenerator.requestedTimeToleranceAfter = .zero
            // Fade intentionally reaches black at the midpoint. Push is sampled early enough that both moving clips are in frame.
            let sampleSeconds = kind == .push ? 0.25 : 0.3
            let renderedFrame = try frameGenerator.copyCGImage(at: CMTime(seconds: sampleSeconds, preferredTimescale: 60000), actualTime: nil)
            let pixel = try averagePixel(renderedFrame)
            let brightness = Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2])
            if kind == .fadeBlack {
                XCTAssertLessThan(brightness, 30, "fade-black reaches a black frame at the transition midpoint")
            } else {
                XCTAssertGreaterThan(brightness, 30, "\(kind.rawValue) exported frame must contain video")
            }
            transitionFrameColors[kind] = pixel

            let afterTransition = try frameGenerator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 60000), actualTime: nil)
            let afterPixel = try averagePixel(afterTransition)
            XCTAssertGreaterThan(Int(afterPixel[0]) + Int(afterPixel[1]) + Int(afterPixel[2]), 30,
                                 "\(kind.rawValue): incoming footage remains visible after the transition window")
        }
        XCTAssertNotEqual(transitionFrameColors[.fadeBlack], transitionFrameColors[.mix],
                          "fade and mix must encode visibly different overlap frames")
    }

    func testAllNineTransitionsResolveFiniteTracksAtEveryFrame() throws {
        let base = transitionProject()
        let fps = base.composition.fps
        let frameCount = Int((TransitionWrappers.defaultDurationMs * fps / 1000).rounded())
        XCTAssertEqual(TransitionKind.allCases.count, 9)
        for kind in TransitionKind.allCases {
            let project = SetTransitionCommand(outgoingId: "a", incomingId: "b", kind: kind,
                                               durationMs: TransitionWrappers.defaultDurationMs).apply(to: base)
            let intent = try XCTUnwrap(TransitionWrappers.applied(for: "b", in: project.layers), kind.rawValue)
            XCTAssertEqual(intent.kind, kind)
            let plan = TransitionFramePlan(project: project)
            let incoming = try XCTUnwrap(project.layers.first { TransitionWrappers.parse($0.id)?.incomingId == "b" }, kind.rawValue)
            for frame in 0...frameCount {
                let timeMs = plan.windows[0].startMs + Double(frame) * 1000 / fps
                let resolved = plan.renderLayer(incoming, at: timeMs, layers: project.layers)
                let sample = sampleLayer(resolved, atMs: timeMs)
                XCTAssertTrue(sample.opacity.isFinite, "\(kind.rawValue) frame \(frame): non-finite opacity")
                XCTAssertTrue(sample.translateX.isFinite && sample.translateY.isFinite,
                              "\(kind.rawValue) frame \(frame): non-finite position")
                XCTAssertTrue(sample.scaleX.isFinite && sample.scaleY.isFinite,
                              "\(kind.rawValue) frame \(frame): non-finite scale")
            }
        }
    }

    @MainActor
    func testPreviewCanvasHasNoUnexpectedBlackFrameAcrossEveryTransitionFrame() throws {
        func solidImage(_ color: UIColor) throws -> CGImage {
            let context = try XCTUnwrap(CGContext(data: nil, width: 96, height: 170,
                                                  bitsPerComponent: 8, bytesPerRow: 0,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 96, height: 170))
            return try XCTUnwrap(context.makeImage())
        }
        func blackCoverage(_ image: CGImage) -> Double {
            let width = image.width
            let height = image.height
            let rowBytes = width * 4
            var pixels = [UInt8](repeating: 0, count: rowBytes * height)
            return pixels.withUnsafeMutableBytes { storage in
                guard let context = CGContext(data: storage.baseAddress, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: rowBytes,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 1 }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                var black = 0
                for index in Swift.stride(from: 0, to: storage.count, by: 4) {
                    if storage[index] < 8 && storage[index + 1] < 8 && storage[index + 2] < 8 { black += 1 }
                }
                return Double(black) / Double(max(width * height, 1))
            }
        }

        let red = try solidImage(.red)
        let blue = try solidImage(.blue)
        let base = V2Project(composition: V2Composition(width: 96, height: 170, fps: 30, background: "#000000"),
                             assets: [], layers: [
                                V2Layer(id: "a", order: 0, frame: V2Frame(width: 96, height: 170), transform: .identity,
                                        timing: V2Timing(start: 0, duration: 2000), payload: .video(V2VideoPayload(assetId: "a"))),
                                V2Layer(id: "b", order: 0, frame: V2Frame(width: 96, height: 170), transform: .identity,
                                        timing: V2Timing(start: 2000, duration: 2000), payload: .video(V2VideoPayload(assetId: "b")))
                             ])
        let expectedFadeBlackFrames = 1
        for kind in TransitionKind.allCases {
            let project = SetTransitionCommand(outgoingId: "a", incomingId: "b", kind: kind, durationMs: 400).apply(to: base)
            let plan = TransitionFramePlan(project: project)
            let window = try XCTUnwrap(plan.windows.first)
            var fullBlackFrames = 0
            let frameCount = Int((window.durationMs * project.composition.fps / 1000).rounded())
            for frame in 0..<frameCount {
                let timeMs = window.startMs + Double(frame) * 1000 / project.composition.fps
                let canvas = PreviewCanvas(composition: project.composition, assets: [], layers: project.layers,
                                           atMs: timeMs, transitionFramePlan: plan,
                                           playerEngine: EditorPlaybackEngine(project: project),
                                           exportFrames: ["a": red, "b": blue])
                    .frame(width: 96, height: 170)
                let renderer = ImageRenderer(content: canvas)
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.uiImage?.cgImage, "\(kind.rawValue) frame \(frame)")
                let coverage = blackCoverage(image)
                if coverage >= 0.98 { fullBlackFrames += 1 }
            }
            NSLog("[TransitionPreviewFrameTest] kind=%@ frames=%d fullBlackFrames=%d",
                  kind.rawValue, frameCount, fullBlackFrames)
            if kind == .fadeBlack {
                XCTAssertLessThanOrEqual(fullBlackFrames, expectedFadeBlackFrames, "Fade has at most one planned black midpoint frame")
            } else {
                XCTAssertEqual(fullBlackFrames, 0, "\(kind.rawValue): SwiftUI preview must not expose a black canvas frame")
            }
        }
    }

    private func inspectExportedFrames(_ asset: AVAsset, expectedFPS: Double) throws ->
        (frameCount: Int, measuredFPS: Double, maxBlackCoverage: Double, fullBlackFrameCount: Int) {
        let tracks = try XCTUnwrap(asset.tracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: tracks, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        output.alwaysCopiesSampleData = false
        XCTAssertTrue(reader.canAdd(output))
        reader.add(output)
        XCTAssertTrue(reader.startReading())

        var timestamps: [Double] = []
        var maximumBlackCoverage = 0.0
        var fullBlackFrameCount = 0
        while let sample = output.copyNextSampleBuffer() {
            timestamps.append(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)))
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(buffer) else { continue }
            let width = CVPixelBufferGetWidth(buffer)
            let height = CVPixelBufferGetHeight(buffer)
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            var black = 0
            let total = width * height
            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * stride + x * 4
                    if bytes[offset] < 8 && bytes[offset + 1] < 8 && bytes[offset + 2] < 8 { black += 1 }
                }
            }
            let coverage = Double(black) / Double(max(total, 1))
            maximumBlackCoverage = max(maximumBlackCoverage, coverage)
            if coverage >= 0.98 { fullBlackFrameCount += 1 }
        }
        XCTAssertEqual(reader.status, .completed, "frame reader failed: \(String(describing: reader.error))")
        let durations = zip(timestamps, timestamps.dropFirst()).map { $1 - $0 }.filter { $0 > 0 }
        let meanDuration = durations.isEmpty ? 0 : durations.reduce(0, +) / Double(durations.count)
        let measuredFPS = meanDuration > 0 ? 1 / meanDuration : 0
        XCTAssertEqual(measuredFPS, expectedFPS, accuracy: 1.5)
        return (timestamps.count, measuredFPS, maximumBlackCoverage, fullBlackFrameCount)
    }
    private func project() -> V2Project {
        let base = V2Project(composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"), assets: [], layers: [])
        return AddTextLayerCommand(layerId: "clip", text: "Hello", atMs: 1000).apply(to: base)   // 1000 ... 4000 ms
    }

    private func set(_ p: V2Project, _ slot: AnimationSlot, _ preset: String?, _ ms: Double = 500) -> V2Project {
        SetAnimationCommand(layerId: "clip", slot: slot, presetId: preset, durationMs: ms).apply(to: p)
    }

    private func wrappers(_ p: V2Project) -> [V2Layer] { p.layers.filter { $0.type == "group" } }
    private func clip(_ p: V2Project, _ id: String = "clip") -> V2Layer { p.layers.first { $0.id == id }! }
    private func opacity(_ layer: V2Layer, at ms: Double) -> Double { sampleLayer(layer, atMs: ms).opacity }

    private func video(_ id: String, start: Double, duration: Double, tracks: [V2Track]? = nil) -> V2Layer {
        V2Layer(id: id, order: 0, frame: V2Frame(width: 360, height: 640), transform: .identity,
                timing: V2Timing(start: start, duration: duration), tracks: tracks,
                payload: .video(V2VideoPayload(assetId: id)))
    }

    private func transitionProject() -> V2Project {
        V2Project(
            composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"), assets: [],
            layers: [video("a", start: 0, duration: 2000), video("b", start: 2000, duration: 2000), video("c", start: 4000, duration: 1000)]
        )
    }

    func testEveryPresetBuildsOrderedTracks() {
        XCTAssertEqual(Set(AnimationCatalog.all.map(\.id)).count, AnimationCatalog.all.count)
        for preset in AnimationCatalog.all {
            for slot in preset.slots {
                let tracks = AnimationCatalog.tracks(for: preset, slot: slot, durationMs: 600, canvas: (360, 640), idPrefix: "x")
                XCTAssertFalse(tracks.isEmpty, preset.id)
                for track in tracks {
                    var last = -Double.infinity
                    for key in track.keyframes {
                        let t: Double
                        switch key.time {
                        case .absolute(let ms): t = ms
                        case .anchored(_, let offset): t = 10_000 - offset   // as if the clip were 10 s long
                        default: t = last + 1
                        }
                        XCTAssertGreaterThan(t, last, "\(preset.id) \(slot) \(track.path): keyframe times must increase")
                        last = t
                    }
                    XCTAssertEqual(track.animation != nil, slot == .combo, "only a combo loops")
                }
            }
        }
        XCTAssertTrue(AnimationCatalog.presets(for: .combo).allSatisfy { $0.cycleMs > 0 })
    }

    func testAnInFadeWrapsTheClipAndFadesItIn() throws {
        let p = set(project(), .in, "fade", 500)
        let w = try XCTUnwrap(wrappers(p).first)
        XCTAssertEqual(wrappers(p).count, 1)
        XCTAssertEqual(w.id, "clip~anim~in~fade~500")
        XCTAssertEqual(clip(p).parentLayerId, w.id)
        XCTAssertEqual(w.timing.start, 1000); XCTAssertEqual(w.timing.duration, 3000)
        XCTAssertEqual(p.layers.firstIndex { $0.id == w.id }!, p.layers.firstIndex { $0.id == "clip" }! - 1, "the wrapper takes the clip's place in the z-order")
        XCTAssertEqual(opacity(w, at: 1000), 0, accuracy: 1e-6)
        XCTAssertEqual(opacity(w, at: 1500), 1, accuracy: 1e-6)
        XCTAssertEqual(opacity(w, at: 3000), 1, accuracy: 1e-6)
    }

    func testAnOutFadeIsTheSameMotionBackwardsEndingAtTheClipsEnd() throws {
        let p = set(project(), .out, "slide-left", 500)
        let w = try XCTUnwrap(wrappers(p).first)
        let x: (Double) -> Double = { sampleLayer(w, atMs: $0).translateX }
        XCTAssertEqual(x(1000), 0, accuracy: 1e-6, "at rest until the exit starts")
        XCTAssertEqual(x(3400), 0, accuracy: 1e-6)
        XCTAssertEqual(x(4000), -0.4 * 360, accuracy: 1e-6, "slide-left out ends off to the left at the end")
        XCTAssertLessThan(x(3800), 0)
        XCTAssertGreaterThan(x(3800), x(4000))
    }

    func testAComboLoopsForTheWholeClip() throws {
        let p = set(project(), .combo, "pulse")
        let w = try XCTUnwrap(wrappers(p).first)
        let scale: (Double) -> Double = { sampleLayer(w, atMs: $0).scaleX }
        XCTAssertEqual(scale(1000), 1, accuracy: 1e-6)
        XCTAssertEqual(scale(1400), 1.08, accuracy: 0.01, "the middle of the first cycle")
        XCTAssertEqual(scale(1800), 1, accuracy: 0.01)
        XCTAssertEqual(scale(2200), 1.08, accuracy: 0.01, "and again, a cycle later")
    }

    func testTheSlotsNestInOrderAndAreReadBack() {
        var p = set(project(), .combo, "sway")
        p = set(p, .out, "fade", 400)
        p = set(p, .in, "zoom-in", 600)
        let ws = wrappers(p)
        XCTAssertEqual(ws.count, 3)
        func parent(_ id: String) -> String? { p.layers.first { $0.id == id }!.parentLayerId }
        XCTAssertEqual(clip(p).parentLayerId, "clip~anim~in~zoom-in~600")
        XCTAssertEqual(parent("clip~anim~in~zoom-in~600"), "clip~anim~out~fade~400")
        XCTAssertEqual(parent("clip~anim~out~fade~400"), "clip~anim~combo~sway~0")
        XCTAssertNil(parent("clip~anim~combo~sway~0"))
        let applied = AnimationWrappers.applied(for: "clip", in: p.layers)
        XCTAssertEqual(applied[.in]?.presetId, "zoom-in"); XCTAssertEqual(applied[.in]?.durationMs, 600)
        XCTAssertEqual(applied[.out]?.presetId, "fade"); XCTAssertEqual(applied[.combo]?.presetId, "sway")
    }

    func testReplacingAndRemovingASlot() {
        var p = set(project(), .in, "fade", 500)
        p = set(p, .in, "pop", 300)
        XCTAssertEqual(wrappers(p).map(\.id), ["clip~anim~in~pop~300"], "replaced, not stacked")
        p = set(p, .out, "fade", 500)
        p = set(p, .in, nil)
        XCTAssertEqual(wrappers(p).map(\.id), ["clip~anim~out~fade~500"])
        XCTAssertEqual(clip(p).parentLayerId, "clip~anim~out~fade~500")
        p = set(p, .out, nil)
        XCTAssertTrue(wrappers(p).isEmpty)
        XCTAssertNil(clip(p).parentLayerId, "back to a plain clip")
    }

    func testFailsClosed() {
        let p = project()
        XCTAssertEqual(set(p, .combo, "fade").layers.count, p.layers.count, "a fade is not a combo")
        XCTAssertEqual(set(p, .in, "nope").layers.count, p.layers.count)
        XCTAssertEqual(SetAnimationCommand(layerId: "missing", slot: .in, presetId: "fade").apply(to: p).layers.count, p.layers.count)
        let clamped = set(p, .in, "fade", 99_999)
        XCTAssertLessThanOrEqual(AnimationWrappers.applied(for: "clip", in: clamped.layers)[.in]!.durationMs, 2900, "never longer than the clip")
    }

    func testDissolveUsesItsOwnWrapperAndMixesWithAnimationAndClipKeyframes() throws {
        let move = V2Track(id: "b-move", path: "transform.translate.x", keyframes: [
            V2Keyframe(time: .absolute(0), value: 0), V2Keyframe(time: .absolute(2000), value: 100)
        ], animation: nil)
        var p = transitionProject()
        var layers = p.layers
        layers[layers.firstIndex { $0.id == "b" }!].tracks = [move]
        p = p.withLayers(layers)
        p = SetAnimationCommand(layerId: "b", slot: .in, presetId: "fade", durationMs: 500).apply(to: p)
        p = SetTransitionCommand(outgoingId: "a", incomingId: "b", durationMs: 400).apply(to: p)

        let rendered = TransitionRenderPlan.compile(p)
        let transition = try XCTUnwrap(rendered.layers.first { TransitionWrappers.parse($0.id)?.incomingId == "b" })
        let animation = try XCTUnwrap(p.layers.first { AnimationWrappers.parse($0.id)?.clipId == "b" })
        let clip = try XCTUnwrap(p.layers.first { $0.id == "b" })
        XCTAssertEqual(clip.timing.start, 2000)
        XCTAssertEqual(TransitionWrappers.parse(transition.id)?.outgoingId, "a")
        let plan = TransitionFramePlan(project: p)
        XCTAssertEqual(sampleLayer(plan.renderLayer(transition, at: 1800, layers: p.layers), atMs: 1800).opacity, 0, accuracy: 1e-6)
        XCTAssertEqual(sampleLayer(plan.renderLayer(transition, at: 2000, layers: p.layers), atMs: 2000).opacity, 0.5, accuracy: 1e-5)
        XCTAssertEqual(sampleLayer(plan.renderLayer(transition, at: 2200, layers: p.layers), atMs: 2200).opacity, 1, accuracy: 1e-6)
        XCTAssertEqual(sampleLayer(animation, atMs: 2200).opacity, 0.5708792066370367, accuracy: 1e-6)
        XCTAssertEqual(sampleLayer(clip, atMs: 2200).translateX, 10, accuracy: 1e-6)
        XCTAssertEqual(sampleLayer(plan.renderLayer(transition, at: 2000, layers: p.layers), atMs: 2000).opacity * sampleLayer(animation, atMs: 2000).opacity, 0, accuracy: 1e-6,
                       "the transition and the clip's own fade compose as separate nested opacity factors")
        XCTAssertEqual(clip.tracks?.map(\.id), ["b-move"], "transition generation must not rewrite authored clip keyframes")
        XCTAssertEqual(AnimationWrappers.applied(for: "b", in: p.layers)[.in]?.presetId, "fade")
    }

    func testEditorAndRenderPlanKeepClipTimingsWhileTransitionSpansTheCut() {
        var p = SetTransitionCommand(outgoingId: "a", incomingId: "b", durationMs: 500).apply(to: transitionProject())
        XCTAssertEqual(p.layers.first { $0.id == "b" }?.timing.start, 2000)
        XCTAssertEqual(p.layers.first { $0.id == "c" }?.timing.start, 4000)

        p = PackMainLaneCommand().apply(to: p)
        XCTAssertEqual(p.layers.first { $0.id == "b" }?.timing.start, 2000, "packing keeps the split visible in the editor")
        XCTAssertEqual(p.layers.first { $0.id == "c" }?.timing.start, 4000)

        let render = TransitionRenderPlan.compile(p)
        XCTAssertEqual(render.layers.first { TransitionWrappers.parse($0.id)?.incomingId == "b" }?.timing.start, 1750)
        XCTAssertEqual(render.layers.first { $0.id == "c" }?.timing.start, 4000)
        XCTAssertEqual(render.layers.map(\.id), p.layers.map(\.id))
        XCTAssertEqual(render.layers.first { TransitionWrappers.parse($0.id)?.incomingId == "b" }?.timing.duration, 2250)
        XCTAssertEqual(p.layers.first { $0.id == "b" }?.timing.start, 2000, "authoring clip timing stays unchanged")

        p = SetTransitionCommand(outgoingId: "a", incomingId: "b", durationMs: nil).apply(to: p)
        XCTAssertNil(TransitionWrappers.applied(for: "b", in: p.layers))
        XCTAssertEqual(p.layers.first { $0.id == "b" }?.timing.start, 2000)
        XCTAssertEqual(p.layers.first { $0.id == "c" }?.timing.start, 4000)
    }

    func testTransitionFramePlanUsesEditorTimeAndHoldsSourceEdges() throws {
        let project = SetTransitionCommand(outgoingId: "a", incomingId: "b", durationMs: 500).apply(to: transitionProject())
        let plan = TransitionFramePlan(project: project)
        let incoming = try XCTUnwrap(project.layers.first { $0.id == "b" })
        let outgoing = try XCTUnwrap(project.layers.first { $0.id == "a" })
        let window = try XCTUnwrap(plan.activeWindow(at: 2000))
        XCTAssertNil(plan.activeWindow(at: 1749))
        XCTAssertEqual(plan.activeWindow(at: 1750)?.progress(at: 1750), 0)
        XCTAssertEqual(window.progress(at: 2000), 0.5, accuracy: 1e-6)
        XCTAssertEqual(window.progress(at: 2249), 0.998, accuracy: 0.005)
        XCTAssertEqual(plan.sourceTimelineTime(for: incoming, at: 1800), 2000,
                       "incoming media holds its first frame before its edit point")
        XCTAssertEqual(plan.sourceTimelineTime(for: outgoing, at: 2200), 2000,
                       "outgoing media holds its last frame after its edit point")
        XCTAssertNil(plan.activeWindow(at: 2250))
    }

    func testAnimationCanBeAddedAfterTransitionWithoutReplacingIt() throws {
        var p = SetTransitionCommand(outgoingId: "a", incomingId: "b", durationMs: 400).apply(to: transitionProject())
        p = SetAnimationCommand(layerId: "b", slot: .in, presetId: "fade", durationMs: 500).apply(to: p)
        let render = TransitionRenderPlan.compile(p)

        let transition = try XCTUnwrap(render.layers.first { TransitionWrappers.parse($0.id)?.incomingId == "b" })
        let animation = try XCTUnwrap(render.layers.first { AnimationWrappers.parse($0.id)?.clipId == "b" })
        XCTAssertEqual(transition.timing.start, 1800, "render transition starts before the cut")
        XCTAssertEqual(transition.timing.duration, 2200, "render transition remains alive through the incoming clip")
        XCTAssertEqual(animation.timing.duration, 2000, "authored animation timing remains aligned to the clip")
        XCTAssertEqual(TransitionWrappers.parse(transition.id)?.outgoingId, "a")
        XCTAssertEqual(AnimationWrappers.parse(animation.id)?.applied.presetId, "fade")
        let plan = TransitionFramePlan(project: p)
        let transientTransition = plan.renderLayer(transition, at: 2000, layers: p.layers)
        XCTAssertEqual(sampleLayer(transientTransition, atMs: 2000).opacity, 0.5, accuracy: 1e-5)
        XCTAssertEqual(sampleLayer(animation, atMs: 2000).opacity, 0, accuracy: 1e-6)
        XCTAssertEqual(sampleLayer(transientTransition, atMs: 2000).opacity * sampleLayer(animation, atMs: 2000).opacity, 0, accuracy: 1e-6)
    }

    func testFadeBlackUsesItsOwnOverlayAndComposesWithIncomingAnimationAndKeyframes() throws {
        let authoredTrack = V2Track(id: "b-authored-opacity", path: "opacity", keyframes: [
            V2Keyframe(time: .absolute(0), value: 0.8), V2Keyframe(time: .absolute(2000), value: 0.6)
        ], animation: nil)
        var p = transitionProject()
        p = p.withLayers(p.layers.map { layer in
            guard layer.id == "b" else { return layer }
            var updated = layer; updated.tracks = [authoredTrack]; return updated
        })
        p = SetAnimationCommand(layerId: "b", slot: .in, presetId: "fade", durationMs: 500).apply(to: p)
        p = SetTransitionCommand(outgoingId: "a", incomingId: "b", kind: .fadeBlack, durationMs: 400).apply(to: p)
        let render = TransitionRenderPlan.compile(p)

        let transition = try XCTUnwrap(render.layers.first { TransitionWrappers.parse($0.id)?.incomingId == "b" })
        let contentFade = try XCTUnwrap(render.layers.first { $0.type == "group" && $0.parentLayerId == transition.id })
        let black = try XCTUnwrap(render.layers.first { $0.type == "shape" && $0.parentLayerId == transition.id })
        let animation = try XCTUnwrap(render.layers.first { AnimationWrappers.parse($0.id)?.clipId == "b" })
        let clip = try XCTUnwrap(render.layers.first { $0.id == "b" })

        XCTAssertNil(transition.tracks, "Fade keeps the dip overlay independent from the incoming clip opacity")
        XCTAssertEqual(transition.timing.start, 1800)
        XCTAssertEqual(contentFade.timing.duration, 2200, "the incoming source remains alive after the transition window")
        XCTAssertEqual(black.timing.duration, 400, "the black dip exists only during the transition window")
        let plan = TransitionFramePlan(project: p)
        XCTAssertEqual(sampleLayer(plan.renderLayer(contentFade, at: 1800, layers: p.layers), atMs: 1800).opacity, 0, accuracy: 1e-6)
        XCTAssertEqual(sampleLayer(plan.renderLayer(contentFade, at: 2000, layers: p.layers), atMs: 2000).opacity, 0.5, accuracy: 1e-5)
        XCTAssertEqual(sampleLayer(plan.renderLayer(black, at: 1800, layers: p.layers), atMs: 1800).opacity, 0, accuracy: 1e-6)
        XCTAssertEqual(sampleLayer(plan.renderLayer(black, at: 2000, layers: p.layers), atMs: 2000).opacity, 1, accuracy: 1e-6)
        XCTAssertEqual(sampleLayer(plan.renderLayer(black, at: 2200, layers: p.layers), atMs: 2200).opacity, 0, accuracy: 1e-6)
        XCTAssertEqual(clip.tracks?.map(\.id), [authoredTrack.id])
        XCTAssertEqual(AnimationWrappers.applied(for: "b", in: p.layers)[.in]?.presetId, "fade")
        XCTAssertEqual(sampleLayer(animation, atMs: 2000).opacity, 0, accuracy: 1e-6)
    }

    func testPushSlidesIncomingOverStationaryOutgoingAndKeepsAuthoredAnimationTracksSeparate() throws {
        var p = transitionProject()
        p = SetAnimationCommand(layerId: "b", slot: .in, presetId: "fade", durationMs: 500).apply(to: p)
        p = SetTransitionCommand(outgoingId: "a", incomingId: "b", kind: .push, durationMs: 400).apply(to: p)
        let render = TransitionRenderPlan.compile(p)

        let incoming = try XCTUnwrap(render.layers.first { TransitionWrappers.parse($0.id)?.incomingId == "b" })
        let clip = try XCTUnwrap(render.layers.first { $0.id == "b" })
        XCTAssertEqual(TransitionWrappers.parse(incoming.id)?.kind, .push)
        XCTAssertEqual(incoming.timing.start, 1800)
        XCTAssertEqual(incoming.timing.duration, 2200)
        XCTAssertFalse(render.layers.contains { $0.id.contains("~transition-out~") },
                       "the previous clip remains fixed below the entering clip to prevent uncovered canvas")
        let plan = TransitionFramePlan(project: p)
        XCTAssertEqual(sampleLayer(plan.renderLayer(incoming, at: 1800, layers: p.layers), atMs: 1800).translateX, 360, accuracy: 1e-6)
        XCTAssertEqual(sampleLayer(plan.renderLayer(incoming, at: 2000, layers: p.layers), atMs: 2000).translateX, 180, accuracy: 1e-3)
        XCTAssertEqual(sampleLayer(plan.renderLayer(incoming, at: 2200, layers: p.layers), atMs: 2200).translateX, 0, accuracy: 1e-6)
        XCTAssertNil(clip.tracks)
        XCTAssertEqual(AnimationWrappers.applied(for: "b", in: p.layers)[.in]?.presetId, "fade")
    }

    func testChainedPushKeepsOutgoingSubtreeVisiblePastCut() throws {
        for firstKind in TransitionKind.allCases {
            var project = transitionProject()
            project = SetTransitionCommand(outgoingId: "a", incomingId: "b", kind: firstKind, durationMs: 400).apply(to: project)
            project = SetTransitionCommand(outgoingId: "b", incomingId: "c", kind: .push, durationMs: 400).apply(to: project)
            let plan = TransitionFramePlan(project: project)
            let sampleTime = 4100.0 // 75% through b -> c; b must still cover the left quarter.
            let byId = Dictionary(uniqueKeysWithValues: project.layers.map { ($0.id, $0) })
            var parentId = try XCTUnwrap(byId["b"]?.parentLayerId)
            while let parent = byId[parentId] {
                XCTAssertTrue(plan.isVisible(parent.id, at: sampleTime, layers: project.layers),
                              "\(firstKind): resolver must keep ancestor \(parent.id) mounted during chained Push")
                guard let nextId = parent.parentLayerId else { break }
                parentId = nextId
            }
        }
    }

    @MainActor
    func testChainedPushPreviewDrawsBothSidesAfterCut() throws {
        func solidFrame(_ color: UIColor) throws -> CGImage {
            let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2,
                                                  bitsPerComponent: 8, bytesPerRow: 0,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            return try XCTUnwrap(context.makeImage())
        }
        func pixel(_ image: CGImage, x: Int) -> [UInt8] {
            var rgba = [UInt8](repeating: 0, count: 4)
            CIContext().render(CIImage(cgImage: image), toBitmap: &rgba, rowBytes: 4,
                               bounds: CGRect(x: x, y: 320, width: 1, height: 1),
                               format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            return rgba
        }

        var project = transitionProject()
        project = SetTransitionCommand(outgoingId: "a", incomingId: "b", kind: .mix, durationMs: 400).apply(to: project)
        project = SetTransitionCommand(outgoingId: "b", incomingId: "c", kind: .push, durationMs: 400).apply(to: project)
        let framePlan = TransitionFramePlan(project: project)
        let render = framePlan.renderProject(from: project)
        let canvas = PreviewCanvas(composition: render.composition, assets: [], layers: render.layers,
                                   atMs: 4100, transitionFramePlan: framePlan,
                                   playerEngine: EditorPlaybackEngine(project: project),
                                   exportFrames: ["b": try solidFrame(.red), "c": try solidFrame(.blue)])
            .frame(width: 360, height: 640)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage?.cgImage)
        let left = pixel(image, x: 45)
        let right = pixel(image, x: 180)
        XCTAssertGreaterThan(Int(left[0]), Int(left[2]) + 100, "outgoing clip must fill the left side")
        XCTAssertGreaterThan(Int(right[2]), Int(right[0]) + 100, "incoming clip must fill the right side")
    }

    func testChangingTransitionKindReplacesGeneratedLayersWithoutChangingEditorTiming() throws {
        var p = SetTransitionCommand(outgoingId: "a", incomingId: "b", durationMs: 400).apply(to: transitionProject())
        p = SetTransitionCommand(outgoingId: "a", incomingId: "b", kind: .push, durationMs: 400).apply(to: p)

        XCTAssertEqual(TransitionWrappers.applied(for: "b", in: p.layers)?.kind, .push)
        XCTAssertEqual(p.layers.filter { $0.id.contains("~transition~") }.count, 1)
        XCTAssertEqual(p.layers.filter { $0.id.contains("~transition-out~") }.count, 0,
                       "push keeps the outgoing clip stationary under the incoming clip")
        XCTAssertNil(p.layers.first { $0.id.contains("~transition~") && $0.id.contains("mix") })
        XCTAssertEqual(p.layers.first { $0.id == "b" }?.timing.start, 2000)
        XCTAssertEqual(TransitionRenderPlan.compile(p).layers.first { TransitionWrappers.parse($0.id)?.incomingId == "b" }?.timing.start, 1800)
    }

    func testTransitionRequiresAdjacentVideosOnThePrimaryLane() {
        var p = transitionProject()
        let photo = V2Layer(id: "photo", order: 0, frame: V2Frame(width: 360, height: 640), transform: .identity,
                            timing: V2Timing(start: 2000, duration: 1000), payload: .image(V2ImagePayload(assetId: "still")))
        var layers = p.layers
        layers.insert(photo, at: 1)
        p = p.withLayers(layers)
        let unchanged = SetTransitionCommand(outgoingId: "a", incomingId: "b", durationMs: 400).apply(to: p)
        XCTAssertFalse(unchanged.layers.contains { TransitionWrappers.parse($0.id) != nil })
        XCTAssertEqual(unchanged.layers.first { $0.id == "b" }?.timing.start, 2000)
    }

    func testWrappersFollowTheirClipAndGoWhenItDoes() {
        var p = set(project(), .in, "fade", 500)
        // Trim: the clip now starts later and is shorter; the wrapper mirrors it once normalised.
        p = TrimClipCommand(layerId: "clip", start: 1500, duration: 2000, trimStart: nil, trimEnd: nil).apply(to: p)
        p = AnimationWrappers.normalized(p)
        XCTAssertEqual(wrappers(p)[0].timing.start, 1500); XCTAssertEqual(wrappers(p)[0].timing.duration, 2000)
        XCTAssertEqual(opacity(wrappers(p)[0], at: 1500), 0, accuracy: 1e-6, "the entrance starts at the new start")
        let same = AnimationWrappers.normalized(p)
        XCTAssertEqual(same.layers.count, p.layers.count)
        p = DeleteClipCommand(layerId: "clip").apply(to: p)
        XCTAssertEqual(AnimationWrappers.normalized(p).layers.count, 0, "no orphan wrapper is left behind")
    }

    func testSplitMovesTheExitToTheSecondHalfAndLoopsOnBoth() throws {
        var p = set(project(), .in, "fade", 400)
        p = set(p, .out, "zoom-out", 400)
        p = set(p, .combo, "float")
        p = SplitClipCommand(layerId: "clip", atMs: 2500).apply(to: p)
        p = AnimationWrappers.normalized(p)
        let secondId = try XCTUnwrap(p.layers.first { $0.id.hasPrefix("clip-split-") && $0.type != "group" }?.id)
        let first = AnimationWrappers.applied(for: "clip", in: p.layers)
        let second = AnimationWrappers.applied(for: secondId, in: p.layers)
        XCTAssertEqual(Set(first.keys), [.in, .combo], "the entrance stays at the start")
        XCTAssertEqual(Set(second.keys), [.out, .combo], "the exit moves to the end")
        XCTAssertEqual(clip(p, secondId).parentLayerId?.hasPrefix("\(secondId)~anim~"), true, "the second half is not nested in the first half's wrappers")
        XCTAssertEqual(clip(p).timing.duration, 1500)
        for w in wrappers(p) {
            let owner = AnimationWrappers.parse(w.id)!.clipId
            XCTAssertEqual(w.timing.start, clip(p, owner).timing.start); XCTAssertEqual(w.timing.duration, clip(p, owner).timing.duration)
        }
        // A split without any animation is unchanged.
        let plain = SplitClipCommand(layerId: "clip", atMs: 2500).apply(to: project())
        XCTAssertTrue(plain.layers.allSatisfy { $0.type != "group" })
    }

    func testParseRejectsOtherIds() {
        XCTAssertNil(AnimationWrappers.parse("text-1234"))
        XCTAssertNil(AnimationWrappers.parse("clip-fx"))
        XCTAssertNil(AnimationWrappers.parse("clip~anim~sideways~fade~500"))
        XCTAssertEqual(AnimationWrappers.parse("a-b~anim~out~slide-left~250")?.clipId, "a-b")
    }

    func testADuplicatedStickerKeepsItsAnimationsInWrappersOfItsOwn() throws {
        let base = V2Project(composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"), assets: [], layers: [])
        let asset = V2ImageAsset(id: "sticker-a", uri: "x.png", width: 100, height: 100)
        var p = AddStickerCommand(layerId: "sticker-1", asset: asset, atMs: 0).apply(to: base)
        p = SetAnimationCommand(layerId: "sticker-1", slot: .in, presetId: "pop", durationMs: 400).apply(to: p)
        p = DuplicateOverlayCommand(layerId: "sticker-1", newLayerId: "sticker-2").apply(to: p)
        XCTAssertEqual(AnimationWrappers.applied(for: "sticker-2", in: p.layers)[.in]?.presetId, "pop")
        let copy = p.layers.first { $0.id == "sticker-2" }!
        XCTAssertEqual(copy.parentLayerId, "sticker-2~anim~in~pop~400")
        let wrapper = p.layers.first { $0.id == "sticker-2~anim~in~pop~400" }!
        XCTAssertNil(wrapper.parentLayerId)
        XCTAssertEqual(wrapper.timing.start, copy.timing.start, "the copy's wrapper follows the copy, which starts where the original ends")
        XCTAssertEqual(AnimationWrappers.applied(for: "sticker-1", in: p.layers).count, 1)
    }
}
