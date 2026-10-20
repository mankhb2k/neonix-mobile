import AVFoundation
import CoreImage
import Foundation
import Observation
import SwiftUI

/// Where an editor session came from, so Export knows which template to charge for.
struct TemplateExportContext {
    let templateId: String
    /// Version the project was started from.
    let versionId: String?
    /// What the first export costs (shown when the wallet is too low); an owned template costs nothing.
    let creditCost: Int
}

/// Turns a project into a video file on the device.
@MainActor
protocol ProjectExporter {
    var isAvailable: Bool { get }
    func export(_ project: V2Project) async throws -> URL
}

enum ExportError: LocalizedError {
    case notAvailable
    var errorDescription: String? { "Video export isn't available in this build yet." }
}

/// Placeholder until the offline render pipeline exists.
struct UnavailableExporter: ProjectExporter {
    var isAvailable: Bool { false }
    func export(_ project: V2Project) async throws -> URL { throw ExportError.notAvailable }
}

struct ExportedVideo: Identifiable {
    let id = UUID()
    let url: URL
}

struct ExportResultSheet: View {
    let url: URL
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(.tint)
            Text("Video ready")
                .font(.headline)
                .accessibilityIdentifier("exportReady")
            HStack(spacing: 14) {
                Button("Done", action: onDone)
                    .buttonStyle(.bordered)
                ShareLink(item: url) {
                    Label("Share video", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("shareExportedVideo")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.systemBackground))
        .presentationDetents([.height(230)])
    }
}

/// Renders the transition-compiled V2 tree, then muxes its audio sources into an MP4.
/// The supplied editor project retains contiguous clip timings; overlap exists only in this render copy.
@MainActor
struct OfflineProjectExporter: ProjectExporter {
    var isAvailable: Bool { true }

    enum Failure: LocalizedError {
        case emptyProject, missingMedia(String), cannotRenderFrame, cannotCreateWriter, cannotCreateAudioTrack
        var errorDescription: String? {
            switch self {
            case .emptyProject: "The project has no frames to export."
            case .missingMedia(let name): "The media file \(name) is missing."
            case .cannotRenderFrame: "The video frame could not be rendered."
            case .cannotCreateWriter: "The video encoder could not start."
            case .cannotCreateAudioTrack: "The audio track could not be assembled."
            }
        }
    }

    func export(_ editorProject: V2Project) async throws -> URL {
        let framePlan = TransitionFramePlan(project: editorProject)
        let project = framePlan.renderProject(from: editorProject)
        let endMs = max(project.layers.map { $0.timing.start + $0.timing.duration }.max() ?? 0,
                        project.audio.tracks.flatMap(\.clips).map { $0.timing.start + $0.timing.duration }.max() ?? 0)
        guard endMs > 0 else { throw Failure.emptyProject }
        let fps = min(max(project.composition.fps, 1), 60)
        let width = max(2, Int(project.composition.width.rounded()) / 2 * 2)
        let height = max(2, Int(project.composition.height.rounded()) / 2 * 2)
        let outputDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let stem = UUID().uuidString
        let silentURL = outputDir.appendingPathComponent(stem + "-video.mp4")
        let finalURL = outputDir.appendingPathComponent(stem + ".mp4")

        let writer = try AVAssetWriter(outputURL: silentURL, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: max(width * height * 5, 1_000_000)]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        guard writer.canAdd(input) else { throw Failure.cannotCreateWriter }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? Failure.cannotCreateWriter }
        writer.startSession(atSourceTime: .zero)

        struct Source {
            let generator: AVAssetImageGenerator
            let durationMs: Double
        }
        var sources: [String: Source] = [:]
        for layer in project.layers {
            guard case .video(let payload) = layer.payload,
                  let asset = project.assets.first(where: { $0.id == payload.assetId }),
                  case .video(let video) = asset else { continue }
            guard let url = bundledURL(filename: video.uri) else { throw Failure.missingMedia(video.uri) }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: width, height: height)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            sources[layer.id] = Source(generator: generator, durationMs: video.duration)
        }

        let engine = EditorPlaybackEngine(project: editorProject)
        let ciContext = CIContext()
        let count = Int(ceil(endMs * fps / 1000))
        do {
            for index in 0..<count {
                try Task.checkCancellation()
                let timeMs = Double(index) * 1000 / fps
                var frames: [String: CGImage] = [:]
                for layer in project.layers {
                    guard let source = sources[layer.id],
                          (timeMs >= layer.timing.start && timeMs < layer.timing.start + layer.timing.duration
                           || framePlan.isVisible(layer.id, at: timeMs)),
                          let mapping = VideoTimeMapping(layer: layer) else { continue }
                    let sampleTimelineMs = framePlan.sourceTimelineTime(for: layer, at: timeMs)
                    let sampleMs = min(mapping.sourceMs(atTimelineMs: sampleTimelineMs), max(0, source.durationMs - 1000 / fps))
                    let frame = try source.generator.copyCGImage(at: CMTime(seconds: sampleMs / 1000, preferredTimescale: 60000), actualTime: nil)
                    if let filterId = layer.filter, let filter = project.filters?.first(where: { $0.id == filterId }) {
                        frames[layer.id] = FilterRenderer.apply(filter, to: frame) ?? frame
                    } else {
                        frames[layer.id] = frame
                    }
                }
                let canvas = PreviewCanvas(composition: project.composition, assets: project.assets,
                                           layers: project.layers, filters: project.filters ?? [], masks: project.masks ?? [],
                                           atMs: timeMs, transitionFramePlan: framePlan,
                                           playerEngine: engine, exportFrames: frames)
                    .frame(width: project.composition.width, height: project.composition.height)
                let renderer = ImageRenderer(content: canvas)
                renderer.scale = 1
                guard let image = renderer.cgImage,
                      let pool = adaptor.pixelBufferPool else { throw Failure.cannotRenderFrame }
                var rawBuffer: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &rawBuffer) == kCVReturnSuccess,
                      let buffer = rawBuffer else { throw Failure.cannotRenderFrame }
                ciContext.render(CIImage(cgImage: image), to: buffer,
                                 bounds: CGRect(x: 0, y: 0, width: width, height: height),
                                 colorSpace: CGColorSpaceCreateDeviceRGB())
                while !input.isReadyForMoreMediaData {
                    guard writer.status == .writing else { throw writer.error ?? Failure.cannotCreateWriter }
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                let presentationTime = CMTime(seconds: timeMs / 1000, preferredTimescale: 60000)
                guard adaptor.append(buffer, withPresentationTime: presentationTime) else {
                    throw writer.error ?? Failure.cannotRenderFrame
                }
                await Task.yield()
            }
            input.markAsFinished()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                writer.finishWriting {
                    if writer.status == .completed { continuation.resume() }
                    else { continuation.resume(throwing: writer.error ?? Failure.cannotCreateWriter) }
                }
            }
            try await muxAudio(project: project, videoURL: silentURL, outputURL: finalURL)
            try? FileManager.default.removeItem(at: silentURL)
            return finalURL
        } catch {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: silentURL)
            try? FileManager.default.removeItem(at: finalURL)
            throw error
        }
    }

    private func muxAudio(project: V2Project, videoURL: URL, outputURL: URL) async throws {
        let mixEngine = AudioMixEngine()
        mixEngine.update(project: project)
        let sources = mixEngine.sources
        guard !sources.isEmpty else {
            try FileManager.default.moveItem(at: videoURL, to: outputURL)
            return
        }
        let composition = AVMutableComposition()
        let silent = AVURLAsset(url: videoURL)
        guard let videoTrack = try await silent.loadTracks(withMediaType: .video).first,
              let destinationVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw Failure.cannotCreateWriter }
        try destinationVideo.insertTimeRange(CMTimeRange(start: .zero, duration: try await silent.load(.duration)), of: videoTrack, at: .zero)
        var parameters: [AVAudioMixInputParameters] = []
        for source in sources {
            let asset = AVURLAsset(url: source.url)
            guard let track = try await asset.loadTracks(withMediaType: .audio).first else { continue }
            let assetDuration = try await asset.load(.duration)
            let available = CMTimeGetSeconds(assetDuration) - source.trimStartMs / 1000
            let seconds = min(source.durationMs / 1000, available)
            guard seconds > 0 else { continue }
            guard let destination = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw Failure.cannotCreateAudioTrack
            }
            let start = CMTime(seconds: max(0, source.startMs / 1000), preferredTimescale: 60000)
            let duration = CMTime(seconds: seconds, preferredTimescale: 60000)
            try destination.insertTimeRange(CMTimeRange(start: CMTime(seconds: source.trimStartMs / 1000, preferredTimescale: 60000), duration: duration), of: track, at: start)
            let parameter = AVMutableAudioMixInputParameters(track: destination)
            let gain = Float(pow(10, source.gainDb / 20))
            parameter.setVolume(gain, at: start)
            if let fade = source.fadeIn {
                parameter.setVolumeRamp(fromStartVolume: 0, toEndVolume: gain,
                                        timeRange: CMTimeRange(start: start, duration: CMTime(seconds: min(fade.duration / 1000, seconds), preferredTimescale: 60000)))
            }
            if let fade = source.fadeOut {
                let fadeSeconds = min(fade.duration / 1000, seconds)
                parameter.setVolumeRamp(fromStartVolume: gain, toEndVolume: 0,
                                        timeRange: CMTimeRange(start: start + CMTime(seconds: seconds - fadeSeconds, preferredTimescale: 60000),
                                                               duration: CMTime(seconds: fadeSeconds, preferredTimescale: 60000)))
            }
            parameters.append(parameter)
        }
        if parameters.isEmpty {
            try FileManager.default.moveItem(at: videoURL, to: outputURL)
            return
        }
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = parameters
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw Failure.cannotCreateWriter
        }
        session.audioMix = audioMix
        session.outputURL = outputURL
        session.outputFileType = .mp4
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                if session.status == .completed { continuation.resume() }
                else { continuation.resume(throwing: session.error ?? Failure.cannotCreateWriter) }
            }
        }
    }
}

/// Export button logic: for a template project the server is asked first (POST /v1/exports spends the credits,
/// or says the template is already owned, so it is free); only when it answers OK does the render start. Out of credits stops here
/// with a message, nothing is rendered.
@MainActor
@Observable
final class ExportGate {
    struct Alert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    typealias Charge = (TemplateExportContext) async throws -> APIExportResult

    private(set) var isWorking = false
    private(set) var completed = false
    var sharedFile: ExportedVideo?
    var alert: Alert?

    private let charge: Charge
    private let exporter: ProjectExporter
    private let chargesWithoutExporter: Bool

    /// Debug builds charge even though nothing can be rendered yet, so the credit flow can be tried;
    /// release builds do not take credits for a video they cannot produce.
    nonisolated static var defaultChargesWithoutExporter: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    init(
        charge: @escaping Charge = { context in
            try await NeonixAPIClient(config: .current).createExport(templateId: context.templateId, versionId: context.versionId)
        },
        exporter: ProjectExporter? = nil,
        chargesWithoutExporter: Bool = ExportGate.defaultChargesWithoutExporter
    ) {
        self.charge = charge
        self.exporter = exporter ?? OfflineProjectExporter()
        self.chargesWithoutExporter = chargesWithoutExporter
    }

    func export(project: V2Project, context: TemplateExportContext?) async {
        guard !isWorking else { return }
        isWorking = true
        completed = false
        sharedFile = nil
        defer { isWorking = false }

        if !exporter.isAvailable && !(context != nil && chargesWithoutExporter) {
            alert = Alert(title: "Export isn't available yet", message: "Video export is coming soon. No credits were used.")
            return
        }
        if let context {
            do {
                _ = try await charge(context)
            } catch let error as APIError where error.isInsufficientCredits {
                alert = Alert(title: "Not enough credits", message: "Unlocking this template costs \(context.creditCost) credits, once. Add credits to export this video.")
                return
            } catch let error as APIError where error.isUnauthenticated {
                alert = Alert(title: "Sign in to export", message: "Sign in with Google from the Account tab, then try exporting again.")
                return
            } catch {
                alert = Alert(title: "Couldn't check your credits", message: error.localizedDescription)
                return
            }
        }
        do {
            let url = try await exporter.export(project)
            completed = true
            sharedFile = ExportedVideo(url: url)
        } catch {
            alert = Alert(title: "Export failed", message: error.localizedDescription)
        }
    }
}
