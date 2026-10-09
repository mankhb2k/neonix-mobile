import AVFoundation

/// Re-encodes a source video into a scrub-friendly proxy: downscaled to
/// `targetLongEdge` and forced to a short/all-intra keyframe interval
/// (`maxKeyFrameInterval` — 1 means every frame is a keyframe). Built by
/// hand with `AVAssetReader`/`AVAssetWriter`, not `AVAssetExportSession`:
/// export sessions only expose fixed quality presets, with no way to set
/// `AVVideoMaxKeyFrameIntervalKey` — the one setting this whole experiment
/// is actually testing.
///
/// Video-only output (no audio track) — this is a scrub-latency experiment,
/// not a drop-in replacement for the real asset.
enum ProxyTranscoder {
    struct Result {
        let outputURL: URL
        let transcodeSeconds: Double
        let originalBytes: Int64
        let proxyBytes: Int64
    }

    enum TranscodeError: Error {
        case noVideoTrack, readerSetupFailed, writerSetupFailed, writerFailed(Error?)
    }

    @MainActor
    static func makeProxy(
        sourceURL: URL,
        targetLongEdge: CGFloat,
        maxKeyFrameInterval: Int,
        onProgress: @escaping (Double) -> Void
    ) async throws -> Result {
        let start = Date()
        let asset = AVURLAsset(url: sourceURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw TranscodeError.noVideoTrack
        }
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let nominalFrameRate = try await track.load(.nominalFrameRate)
        let duration = try await asset.load(.duration)

        let bounds = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let longEdge = max(bounds.width, bounds.height)
        guard longEdge > 0 else { throw TranscodeError.noVideoTrack }
        let scale = min(1, targetLongEdge / longEdge)
        let renderSize = CGSize(
            width: max(2, (bounds.width * scale / 2).rounded(.down) * 2),
            height: max(2, (bounds.height * scale / 2).rounded(.down) * 2)
        )
        let frameRate = nominalFrameRate > 0 ? nominalFrameRate : 30

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layerInstruction.setTransform(
            preferredTransform
                .concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
                .concatenating(CGAffineTransform(scaleX: scale, y: scale)),
            at: .zero
        )
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layerInstruction]
        let composition = AVMutableVideoComposition()
        composition.renderSize = renderSize
        composition.frameDuration = CMTime(seconds: 1 / Double(frameRate), preferredTimescale: 6000)
        composition.instructions = [instruction]

        guard let reader = try? AVAssetReader(asset: asset) else { throw TranscodeError.readerSetupFailed }
        let readerOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [track],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        readerOutput.videoComposition = composition
        guard reader.canAdd(readerOutput) else { throw TranscodeError.readerSetupFailed }
        reader.add(readerOutput)

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("proxy-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)
        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            throw TranscodeError.writerSetupFailed
        }
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(renderSize.width),
            AVVideoHeightKey: Int(renderSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoMaxKeyFrameIntervalKey: maxKeyFrameInterval,
                AVVideoAverageBitRateKey: 4_000_000,
            ],
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        guard writer.canAdd(writerInput) else { throw TranscodeError.writerSetupFailed }
        writer.add(writerInput)

        guard reader.startReading() else { throw TranscodeError.readerSetupFailed }
        guard writer.startWriting() else { throw TranscodeError.writerSetupFailed }
        writer.startSession(atSourceTime: .zero)

        let durationSeconds = max(duration.seconds, 0.001)
        while reader.status == .reading, let sample = readerOutput.copyNextSampleBuffer() {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            adaptor.append(pixelBuffer, withPresentationTime: pts)
            onProgress(min(pts.seconds / durationSeconds, 1))
        }
        writerInput.markAsFinished()
        await writer.finishWriting()
        reader.cancelReading()

        guard writer.status == .completed else {
            throw TranscodeError.writerFailed(writer.error)
        }

        let originalBytes = fileSize(at: sourceURL)
        let proxyBytes = fileSize(at: outputURL)
        return Result(
            outputURL: outputURL,
            transcodeSeconds: Date().timeIntervalSince(start),
            originalBytes: originalBytes,
            proxyBytes: proxyBytes
        )
    }

    /// Zero-tolerance seek-to-exact-frame latency at each point in
    /// `seconds`, one at a time (not parallel — this measures real seek
    /// cost, not generator-internal batching).
    static func measureSeekLatency(url: URL, atSeconds seconds: [Double]) async -> [Double] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var results: [Double] = []
        for point in seconds {
            let start = Date()
            _ = try? await generator.image(at: CMTime(seconds: point, preferredTimescale: 600))
            results.append(Date().timeIntervalSince(start))
        }
        return results
    }

    private static func fileSize(at url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? 0
    }
}
