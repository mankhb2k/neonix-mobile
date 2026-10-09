import AVFoundation
import CoreImage

/// Creates a preview-only, video-only proxy with short GOPs.
///
/// The original asset remains the source of truth for export. The proxy is
/// deliberately kept in Caches and is used only by the editor preview: lower
/// resolution reduces GPU/memory pressure, while a dense keyframe interval
/// makes backward seeks cheap instead of forcing a long-GOP walk on every
/// reverse drag.
enum VideoProxyService {
    private static let version = "v1-gop10-720"
    private static let targetLongEdge: CGFloat = 720
    private static let maxKeyFrameInterval = 10

    static func proxyURLIfPresent(assetId: String, sourceURL: URL) -> URL? {
        let url = outputURL(assetId: assetId, sourceURL: sourceURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let byteCount = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard byteCount > 0 else { return nil }
        return url
    }

    static func makeProxy(assetId: String, sourceURL: URL) async -> URL? {
        if let existing = proxyURLIfPresent(assetId: assetId, sourceURL: sourceURL) {
            return existing
        }

        let destination = outputURL(assetId: assetId, sourceURL: sourceURL)
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: destination)
            try await encode(sourceURL: sourceURL, to: destination)
            return proxyURLIfPresent(assetId: assetId, sourceURL: sourceURL)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            return nil
        }
    }

    private static func outputURL(assetId: String, sourceURL: URL) -> URL {
        let safeAsset = assetId.replacingOccurrences(of: "/", with: "_")
        let safeSource = sourceURL.lastPathComponent.replacingOccurrences(of: "/", with: "_")
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VideoProxies", isDirectory: true)
            .appendingPathComponent("\(safeAsset)-\(safeSource)-\(version).mp4")
    }

    private static func encode(sourceURL: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: sourceURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ProxyError.noVideoTrack
        }
        let duration = try await asset.load(.duration)
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let nominalFrameRate = try await track.load(.nominalFrameRate)

        let transformedBounds = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let sourceWidth = max(abs(transformedBounds.width), 2)
        let sourceHeight = max(abs(transformedBounds.height), 2)
        let scale = min(1, targetLongEdge / max(sourceWidth, sourceHeight))
        let renderSize = CGSize(
            width: max(2, (sourceWidth * scale / 2).rounded(.down) * 2),
            height: max(2, (sourceHeight * scale / 2).rounded(.down) * 2)
        )
        let frameRate = nominalFrameRate > 0 ? nominalFrameRate : 30

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        let transform = preferredTransform
            .concatenating(CGAffineTransform(translationX: -transformedBounds.minX, y: -transformedBounds.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
        layerInstruction.setTransform(transform, at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layerInstruction]

        let composition = AVMutableVideoComposition()
        composition.renderSize = renderSize
        composition.frameDuration = CMTime(seconds: 1 / Double(frameRate), preferredTimescale: 6000)
        composition.instructions = [instruction]
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [track],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        readerOutput.videoComposition = composition
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else { throw ProxyError.readerSetup }
        reader.add(readerOutput)

        let width = Int(renderSize.width)
        let height = Int(renderSize.height)
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 2_000_000,
                    AVVideoExpectedSourceFrameRateKey: Int(frameRate.rounded()),
                    AVVideoMaxKeyFrameIntervalKey: Self.maxKeyFrameInterval,
                    AVVideoAllowFrameReorderingKey: false,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
        )
        writerInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
        )
        guard writer.canAdd(writerInput) else { throw ProxyError.writerSetup }
        writer.add(writerInput)
        guard reader.startReading(), writer.startWriting() else {
            throw reader.error ?? writer.error ?? ProxyError.startFailed
        }
        writer.startSession(atSourceTime: .zero)

        while let sample = readerOutput.copyNextSampleBuffer() {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sample)
            guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                throw writer.error ?? ProxyError.appendFailed
            }
        }

        if reader.status == .failed {
            throw reader.error ?? ProxyError.readFailed
        }
        writerInput.markAsFinished()
        try await finish(writer)
    }

    private static func finish(_ writer: AVAssetWriter) async throws {
        try await withCheckedThrowingContinuation { continuation in
            writer.finishWriting {
                if writer.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: writer.error ?? ProxyError.finishFailed)
                }
            }
        }
    }

    private enum ProxyError: Error {
        case noVideoTrack
        case readerSetup
        case writerSetup
        case startFailed
        case appendFailed
        case readFailed
        case finishFailed
    }
}
