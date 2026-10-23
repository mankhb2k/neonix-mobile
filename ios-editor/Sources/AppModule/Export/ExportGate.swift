import AVFoundation
import CoreImage
import Foundation
import Observation
import Photos
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
    func export(_ project: V2Project, settings: ExportSettings) async throws -> URL
    func export(_ project: V2Project, settings: ExportSettings, progress: @escaping (Double) -> Void) async throws -> URL
}

extension ProjectExporter {
    func export(_ project: V2Project, settings: ExportSettings, progress: @escaping (Double) -> Void) async throws -> URL {
        progress(0)
        let url = try await export(project, settings: settings)
        progress(1)
        return url
    }
}

enum ExportResolution: String, CaseIterable, Identifiable {
    case p480, p720, p1080
    var id: Self { self }
    var title: String {
        switch self { case .p480: "480p"; case .p720: "720p"; case .p1080: "1080p" }
    }
    var buttonTitle: String {
        switch self { case .p480: "480"; case .p720: "720"; case .p1080: "1080" }
    }
    var longEdge: Int {
        switch self { case .p480: 854; case .p720: 1280; case .p1080: 1920 }
    }
}

struct ExportSettings: Equatable {
    var resolution: ExportResolution = .p1080
    var frameRate: Int = 30
    var bitrateMbps: Int = 5

    /// Preserves the composition aspect ratio and returns encoder-compatible even dimensions.
    func outputSize(for composition: V2Composition) -> (width: Int, height: Int) {
        let sourceWidth = max(2, Int(composition.width.rounded()))
        let sourceHeight = max(2, Int(composition.height.rounded()))
        let longEdge = resolution.longEdge
        let scale = Double(longEdge) / Double(max(sourceWidth, sourceHeight))
        let width = max(2, Int((Double(sourceWidth) * scale).rounded()) / 2 * 2)
        let height = max(2, Int((Double(sourceHeight) * scale).rounded()) / 2 * 2)
        return (width, height)
    }
}

enum ExportError: LocalizedError {
    case notAvailable
    var errorDescription: String? { "Video export isn't available in this build yet." }
}

/// Placeholder until the offline render pipeline exists.
struct UnavailableExporter: ProjectExporter {
    var isAvailable: Bool { false }
    func export(_ project: V2Project, settings: ExportSettings) async throws -> URL { throw ExportError.notAvailable }
}

struct ExportQualityPopover: View {
    let selection: ExportResolution
    let frameRate: Int
    let bitrateMbps: Int
    let onResolutionChange: (ExportResolution) -> Void
    let onFrameRateChange: (Int) -> Void
    let onBitrateChange: (Int) -> Void

    private let frameRates = [24, 25, 30, 50, 60]
    private let bitrates = [5, 10, 20, 50, 100]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Export quality").font(.title3.weight(.semibold))
                Text("Set resolution, frame rate and bitrate").font(.subheadline).foregroundStyle(.secondary)
            }
            qualitySlider(title: "Resolution", value: selection.title, choices: ExportResolution.allCases.map(\.title),
                          selectedIndex: ExportResolution.allCases.firstIndex(of: selection) ?? 1,
                          onChange: { onResolutionChange(ExportResolution.allCases[$0]) }, identifier: "resolution")
            qualitySlider(title: "Frame rate", value: "\(frameRate) fps", choices: frameRates.map(String.init),
                          selectedIndex: frameRates.firstIndex(of: frameRate) ?? 2,
                          onChange: { onFrameRateChange(frameRates[$0]) }, identifier: "frameRate")
            qualitySlider(title: "Bitrate", value: "\(bitrateMbps) Mbps", choices: bitrates.map(String.init),
                          selectedIndex: bitrates.firstIndex(of: bitrateMbps) ?? 0,
                          onChange: { onBitrateChange(bitrates[$0]) }, identifier: "bitrate")
            HStack(spacing: 6) {
                Image(systemName: "film").font(.footnote)
                Text("MP4 · H.264").font(.footnote)
                Text("·").font(.footnote)
                Text("\(frameRate) fps").font(.footnote)
            }.foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 340, maxWidth: 380, alignment: .leading)
        .background(Color(.systemBackground))
        .accessibilityIdentifier("exportQualityPopover")
    }

    private func qualitySlider(title: String, value: String, choices: [String], selectedIndex: Int,
                               onChange: @escaping (Int) -> Void, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.body.weight(.medium))
                Spacer()
                Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
            SteppedQualitySlider(choices: choices, selectedIndex: selectedIndex, onChange: onChange)
                .frame(height: 24)
                .accessibilityIdentifier("exportQualitySlider-\(identifier)")
            HStack(spacing: 0) {
                ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                    Text(choice)
                        .font(.caption)
                        .foregroundStyle(index == selectedIndex ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(alignment: index == 0 ? .leading : (index == choices.count - 1 ? .trailing : .center))
                }
            }
        }
    }
}

private struct SteppedQualitySlider: View {
    let choices: [String]
    let selectedIndex: Int
    let onChange: (Int) -> Void

    var body: some View {
        GeometryReader { geometry in
            let inset: CGFloat = 9
            let railWidth = max(0, geometry.size.width - inset * 2)
            let fraction = choices.count > 1 ? CGFloat(selectedIndex) / CGFloat(choices.count - 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemGray5)).frame(width: railWidth, height: 4).offset(x: inset)
                Capsule().fill(Color.cyan).frame(width: railWidth * fraction, height: 4).offset(x: inset)
                ForEach(choices.indices, id: \.self) { index in
                    Circle()
                        .fill(index <= selectedIndex ? Color.cyan : Color(.systemGray3))
                        .frame(width: 5, height: 5)
                        .position(x: inset + railWidth * CGFloat(index) / CGFloat(max(choices.count - 1, 1)), y: geometry.size.height / 2)
                }
                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(Color.cyan, lineWidth: 2))
                    .shadow(color: .black.opacity(0.16), radius: 3, y: 1)
                    .position(x: inset + railWidth * fraction, y: geometry.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                guard choices.count > 1, railWidth > 0 else { return }
                let position = min(max(gesture.location.x - inset, 0), railWidth) / railWidth
                onChange(Int((position * CGFloat(choices.count - 1)).rounded()))
            })
        }
        .accessibilityElement()
        .accessibilityValue(choices.indices.contains(selectedIndex) ? choices[selectedIndex] : "")
        .accessibilityAdjustableAction { direction in
            let next = selectedIndex + (direction == .increment ? 1 : -1)
            onChange(min(max(next, 0), choices.count - 1))
        }
    }
}

enum ExportPhotoLibrary {
    enum Failure: LocalizedError {
        case permissionDenied
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .permissionDenied: "Allow Neonix to add videos to Photos in Settings, then try exporting again."
            case .saveFailed(let message): message
            }
        }
    }

    static func saveVideo(at url: URL) async throws {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { continuation.resume(returning: $0) }
            }
        }
        guard status == .authorized || status == .limited else { throw Failure.permissionDenied }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                if success { continuation.resume() }
                else { continuation.resume(throwing: Failure.saveFailed(error?.localizedDescription ?? "Photos couldn't save this video.")) }
            }
        }
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

    func export(_ editorProject: V2Project, settings: ExportSettings = ExportSettings()) async throws -> URL {
        try await export(editorProject, settings: settings, progress: { _ in })
    }

    func export(_ editorProject: V2Project, settings: ExportSettings, progress: @escaping (Double) -> Void) async throws -> URL {
        let framePlan = TransitionFramePlan(project: editorProject)
        let project = framePlan.renderProject(from: editorProject)
        let endMs = max(project.layers.map { $0.timing.start + $0.timing.duration }.max() ?? 0,
                        project.audio.tracks.flatMap(\.clips).map { $0.timing.start + $0.timing.duration }.max() ?? 0)
        guard endMs > 0 else { throw Failure.emptyProject }
        let fps = Double(min(max(settings.frameRate, 1), 60))
        let outputSize = settings.outputSize(for: project.composition)
        let width = outputSize.width
        let height = outputSize.height
        let outputDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let stem = UUID().uuidString
        let silentURL = outputDir.appendingPathComponent(stem + "-video.mp4")
        let finalURL = outputDir.appendingPathComponent(stem + ".mp4")

        let writer = try AVAssetWriter(outputURL: silentURL, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: max(settings.bitrateMbps * 1_000_000, 1_000_000)]
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
                let sourceImage = CIImage(cgImage: image)
                let scaledImage = sourceImage.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / sourceImage.extent.width,
                                                                                y: CGFloat(height) / sourceImage.extent.height))
                ciContext.render(scaledImage, to: buffer,
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
                progress(Double(index + 1) / Double(max(count, 1)) * 0.92)
                await Task.yield()
            }
            input.markAsFinished()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                writer.finishWriting {
                    if writer.status == .completed { continuation.resume() }
                    else { continuation.resume(throwing: writer.error ?? Failure.cannotCreateWriter) }
                }
            }
            progress(0.95)
            try await muxAudio(project: project, videoURL: silentURL, outputURL: finalURL)
            progress(1)
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
    private(set) var showsProgress = false
    private(set) var progress = 0.0
    private(set) var progressTitle = "Preparing export"
    var alert: Alert?

    private let charge: Charge
    private let exporter: ProjectExporter
    private let chargesWithoutExporter: Bool
    private let saveToPhotos: @MainActor (URL) async throws -> Void

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
        chargesWithoutExporter: Bool = ExportGate.defaultChargesWithoutExporter,
        saveToPhotos: @escaping @MainActor (URL) async throws -> Void = { try await ExportPhotoLibrary.saveVideo(at: $0) }
    ) {
        self.charge = charge
        self.exporter = exporter ?? OfflineProjectExporter()
        self.chargesWithoutExporter = chargesWithoutExporter
        self.saveToPhotos = saveToPhotos
    }

    func export(project: V2Project, context: TemplateExportContext?, settings: ExportSettings = ExportSettings()) async {
        guard !isWorking else { return }
        isWorking = true
        completed = false
        showsProgress = true
        progress = 0.02
        progressTitle = "Preparing export"
        alert = nil
        defer {
            isWorking = false
            if !completed { showsProgress = false }
        }

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
            progressTitle = "Rendering video"
            let url = try await exporter.export(project, settings: settings, progress: { [weak self] value in
                self?.progress = min(max(value, 0), 1) * 0.9
            })
            progressTitle = "Saving to Photos"
            progress = 0.96
            try await saveToPhotos(url)
            progress = 1
            progressTitle = "Saved to Photos"
            completed = true
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1.2))
                self?.showsProgress = false
            }
        } catch {
            alert = Alert(title: "Export failed", message: error.localizedDescription)
        }
    }
}

struct ExportProgressOverlay: View {
    let progress: Double
    let title: String
    let isComplete: Bool

    private var percent: Int { Int((min(max(progress, 0), 1) * 100).rounded()) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.34).ignoresSafeArea()
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.10), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: min(max(progress, 0), 1))
                        .stroke(Color.cyan, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if isComplete {
                        Image(systemName: "checkmark")
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundStyle(Color.cyan)
                    } else {
                        Text("\(percent)%")
                            .font(.system(size: 21, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                }
                .frame(width: 82, height: 82)
                .accessibilityLabel("Export progress, \(percent) percent")

                VStack(spacing: 5) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(isComplete ? "Your video is in Photos." : "Keep Neonix open while this finishes.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
            .frame(width: 260)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
            .accessibilityIdentifier("exportProgressOverlay")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: progress)
        .zIndex(10_000)
    }
}
