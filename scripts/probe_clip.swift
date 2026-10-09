// Describes a video the way a seek-cost analysis needs it: codec, size, fps,
// bitrate, keyframe spacing, B-frame reordering, HDR/transfer, rotation.
// Build + run:  swiftc -O scripts/probe_clip.swift -o /tmp/probe_clip && /tmp/probe_clip clip.mov
import AVFoundation

func fourcc(_ code: FourCharCode) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xFF) }
    return String(bytes: bytes, encoding: .macOSRoman) ?? "\(code)"
}

let args = CommandLine.arguments
guard args.count > 1 else { print("usage: probe_clip <file>"); exit(1) }
let url = URL(fileURLWithPath: args[1])
let asset = AVURLAsset(url: url)
let done = DispatchSemaphore(value: 0)

Task {
    defer { done.signal() }
    guard let track = try? await asset.loadTracks(withMediaType: .video).first else { print("no video track"); return }
    let duration = (try? await asset.load(.duration))?.seconds ?? 0
    let size = (try? await track.load(.naturalSize)) ?? .zero
    let transform = (try? await track.load(.preferredTransform)) ?? .identity
    let fps = (try? await track.load(.nominalFrameRate)) ?? 0
    let rate = (try? await track.load(.estimatedDataRate)) ?? 0
    let formats = (try? await track.load(.formatDescriptions)) ?? []
    let hasAudio = ((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty == false
    let fileBytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0

    var codec = "?", transfer = "-", primaries = "-", bits = "-"
    if let format = formats.first {
        codec = fourcc(CMFormatDescriptionGetMediaSubType(format))
        func ext(_ key: CFString) -> String? { CMFormatDescriptionGetExtension(format, extensionKey: key) as? String }
        transfer = ext(kCMFormatDescriptionExtension_TransferFunction) ?? "-"
        primaries = ext(kCMFormatDescriptionExtension_ColorPrimaries) ?? "-"
        if let b = CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_BitsPerComponent) { bits = "\(b)" }
    }
    let angle = Int((atan2(transform.b, transform.a) * 180 / .pi).rounded())
    let hdr = transfer.contains("2100") || transfer.contains("2084") || transfer.contains("HLG")

    // Walk the compressed samples in decode order.
    var frames = 0, keys: [Int] = [], reordered = false, lastPTS = -Double.infinity
    var firstPTS: Double?, lastSeen: Double = 0
    if let reader = try? AVAssetReader(asset: asset) {
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(out)
        if reader.startReading() {
            while let sample = out.copyNextSampleBuffer() {
                let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
                if (attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool) != true { keys.append(frames) }
                let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                if pts < lastPTS { reordered = true }
                lastPTS = max(lastPTS, pts)
                firstPTS = firstPTS ?? pts
                lastSeen = pts
                frames += 1
            }
        }
    }
    let gaps = zip(keys.dropFirst(), keys).map { $0 - $1 }
    let measuredFPS = frames > 1 ? Double(frames - 1) / max(lastSeen - (firstPTS ?? 0), 0.001) : 0

    print("file         \(url.lastPathComponent)  (\(String(format: "%.1f", Double(fileBytes) / 1_048_576)) MB)")
    print("codec        \(codec)   \(Int(size.width))x\(Int(size.height))   rotation \(angle)°   audio \(hasAudio ? "yes" : "no")")
    print("duration     \(String(format: "%.2f", duration)) s   frames \(frames)   nominal \(String(format: "%.2f", fps)) fps   measured \(String(format: "%.2f", measuredFPS)) fps")
    print("bitrate      \(String(format: "%.1f", rate / 1_000_000)) Mbps")
    print("color        primaries \(primaries)   transfer \(transfer)   bits \(bits)   HDR \(hdr ? "YES" : "no")")
    if gaps.isEmpty {
        print("keyframes    \(keys.count)")
    } else {
        let sorted = gaps.sorted()
        print("keyframes    \(keys.count)   interval frames: median \(sorted[sorted.count / 2])  max \(sorted.last!)  (≈ \(String(format: "%.2f", Double(sorted[sorted.count / 2]) / max(measuredFPS, 1))) s median)")
    }
    print("B-frames     \(reordered ? "YES (presentation order differs from decode order)" : "no")")
}
done.wait()
