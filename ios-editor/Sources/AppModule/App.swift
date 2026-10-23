import AVFoundation
import SwiftUI
import GoogleSignIn

@main
struct NeonixEditorApp: App {
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.system
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--split-preview-capture") {
                    SplitPreviewCaptureView()
                } else {
                    RootTabView()
                }
                #else
                RootTabView()
                #endif
            }
                .preferredColorScheme(appearance.colorScheme)
                .environment(\.locale, language.locale)
                .onOpenURL { url in
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
                #if DEBUG
                .task { await FilterThumbnailBench.runIfRequested() }   // env FILTER_BENCH=1; see FilterThumbnailBench
                .task { await CropFrameBench.runIfRequested() }   // env CROP_BENCH=1; see CropFrameBench
                .task { await RemoveBackgroundBench.runIfRequested() }   // env REMOVEBG_BENCH=1; see RemoveBackgroundBench
                .task { await SeekTimeBench.runIfRequested() }   // env SEEK_BENCH=1; see SeekTimeBench
                .task { await SpeedBench.runIfRequested() }   // env SPEED_BENCH=1; see SpeedBench
                #endif
        }
    }
}

#if DEBUG
/// Real PreviewCanvas capture harness, activated only by a simulator launch argument.
private struct SplitPreviewCaptureView: View {
    private struct Sample: Identifiable {
        let file: String
        let title: String
        let split: Bool
        let transition: Bool
        var id: String { "\(file)-\(title)" }
    }

    private let samples = [
        Sample(file: "demo-nguoi1.MOV", title: "SELFIE · UNSPLIT · 5s", split: false, transition: false),
        Sample(file: "demo-nguoi1.MOV", title: "SELFIE · SPLIT · 5s", split: true, transition: false),
        Sample(file: "demo-nguoi1.MOV", title: "SELFIE · TRANSITION · 5s", split: true, transition: true),
        Sample(file: "demo-nguoi2.MOV", title: "CROWD · UNSPLIT · 5s", split: false, transition: false),
        Sample(file: "demo-nguoi2.MOV", title: "CROWD · SPLIT · 5s", split: true, transition: false),
        Sample(file: "demo-nguoi2.MOV", title: "CROWD · TRANSITION · 5s", split: true, transition: true),
        Sample(file: "iphone-footage.MOV", title: "PHONE · UNSPLIT · 5s", split: false, transition: false),
        Sample(file: "iphone-footage.MOV", title: "PHONE · SPLIT · 5s", split: true, transition: false),
        Sample(file: "iphone-footage.MOV", title: "PHONE · TRANSITION · 5s", split: true, transition: true),
    ]
    @State private var project: V2Project?
    @State private var engine: EditorPlaybackEngine?
    @State private var title = "Preparing preview capture…"
    @State private var finished = false

    var body: some View {
        VStack(spacing: 10) {
            if let project, let engine {
                PreviewCanvas(composition: project.composition, assets: project.assets,
                              layers: engine.previewLayers, atMs: engine.currentTimeMs,
                              transitionFramePlan: engine.transitionFramePlan, playerEngine: engine)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black)
            } else {
                Color.black
            }
            Text(finished ? "Capture sequence complete" : title)
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Color(red: 0, green: 0.65, blue: 0.78))
        }
        .background(.black)
        .task { await runSequence() }
    }

    @MainActor
    private func runSequence() async {
        for (index, sample) in samples.enumerated() {
            do {
                let nextProject = try await makeProject(for: sample)
                let playback = EditorPlaybackEngine(project: nextProject)
                playback.prepare()
                project = nextProject
                engine = playback
                title = "\(index + 1)/\(samples.count)  \(sample.title)"
                playback.beginScrub()
                playback.scrub(toMs: 4_600)
                playback.endScrub(velocityMsPerSecond: 0)
                try await Task.sleep(nanoseconds: 350_000_000)
                playback.play()
                let deadline = CACurrentMediaTime() + 1.5
                while CACurrentMediaTime() < deadline && playback.currentTimeMs < 5_500 {
                    try await Task.sleep(nanoseconds: 16_000_000)
                }
                playback.pause()
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                title = "FAILED: \(sample.title) · \(error.localizedDescription)"
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        finished = true
        title = "9 samples complete"
    }

    private func makeProject(for sample: Sample) async throws -> V2Project {
        guard let url = bundledURL(filename: sample.file) else { throw CaptureFailure.missingVideo(sample.file) }
        let source = AVURLAsset(url: url)
        let duration = try await source.load(.duration).seconds * 1000
        let tracks = try await source.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw CaptureFailure.missingVideoTrack(sample.file) }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let upright = CGRect(origin: .zero, size: size).applying(transform).size
        let assetId = "capture-\(sample.file)"
        let layer = V2Layer(id: "capture-source-\(sample.file)", order: 0,
                            frame: V2Frame(width: 360, height: 640), transform: .identity,
                            timing: V2Timing(start: 0, duration: duration),
                            payload: .video(V2VideoPayload(assetId: assetId, fit: "cover", trimStart: 0,
                                                           trimEnd: duration, playbackRate: 1)))
        let videoAsset = V2Asset.video(V2VideoAsset(id: assetId, uri: sample.file,
                                                    width: abs(upright.width), height: abs(upright.height),
                                                    duration: duration))
        var result = V2Project(id: "capture-\(sample.id)",
                               composition: V2Composition(width: 360, height: 640, fps: 30, background: "#000000"),
                               assets: [videoAsset], layers: [layer])
        guard sample.split else { return result }
        let incomingId = "capture-second-\(sample.file)"
        result = SplitClipCommand(layerId: layer.id, atMs: 5_000, secondLayerId: incomingId).apply(to: result)
        if sample.transition {
            result = SetTransitionCommand(outgoingId: layer.id, incomingId: incomingId,
                                          kind: .mix, durationMs: 1_000).apply(to: result)
        }
        return result
    }

    private enum CaptureFailure: LocalizedError {
        case missingVideo(String), missingVideoTrack(String)
        var errorDescription: String? {
            switch self {
            case .missingVideo(let name): "Video not found: \(name)"
            case .missingVideoTrack(let name): "Video track not found: \(name)"
            }
        }
    }
}
#endif
