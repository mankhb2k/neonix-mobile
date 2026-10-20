import AVFoundation
import ImageIO
import SwiftUI
import UIKit

/// The Crop tool's popup (user 2026-10-18: first the lab's layout B as a 300 pt sheet over the stage, then "a popup as tall as the screen, like Stickers"): it
/// opens full length, the picture with its crop frame (`CropStage`) fills the top, and under it the controls of layout B - three round buttons, **Aspect**
/// (a row of ratio tiles), **Rotate** (the ruler, -20...20 degrees) and **Flip**. Reset (the back-arrow icon) and Done stay pinned in the title bar. The
/// frame is a draft; the shell stores it with one `SetClipCropCommand` when the popup closes, so the whole session is one undo step.
struct CropSheet: View {
    @Binding var draft: CropDraft
    /// The picture to crop: the photo, or the video's frame under the playhead (nil while it loads).
    let image: UIImage?
    /// A video clip: its running player (the picture is its frames, the time bar and the play button drive it). nil for a photo - no bar, no player.
    @State private var playback: CropPlayback?
    private let video: CropVideo?

    init(draft: Binding<CropDraft>, image: UIImage?, video: CropVideo?) {
        _draft = draft
        self.image = image
        self.video = video
    }

    enum Param: String, CaseIterable, Identifiable {
        case aspect, rotate
        var id: String { rawValue }
        var title: String { self == .aspect ? "Aspect ratio" : "Rotate" }
        var symbol: String { self == .aspect ? "crop" : "rotate.right" }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var param: Param = .aspect
    private let rotation = RulerMapping.linear(-20...20, step: 1, majorEvery: 10)

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                CropStage(image: image, player: playback?.player, pictureAspect: video?.pictureAspect, crop: $draft)
                    .padding(.horizontal, 16)
                    .frame(maxHeight: .infinity)
                if let playback, let video { CropTimeBar(playback: playback, durationMs: video.durationMs) }
                Group {
                    switch param {
                    case .aspect: aspectTiles
                    case .rotate: rotateDial
                    }
                }
                .frame(height: 96, alignment: .center)
                HStack(spacing: 26) {
                    paramButton(.aspect, value: draft.aspect.title)
                    paramButton(.rotate, value: draft.rotation == 0 ? "0°" : String(format: "%+.0f°", draft.rotation))
                    flipButton
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
            }
            .padding(.top, 4)
            .navigationTitle(param.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { draft = CropDraft() } label: { Image(systemName: "arrow.counterclockwise") }
                        .disabled(!draft.isChanged).accessibilityLabel("Reset").accessibilityIdentifier("cropReset")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("cropDone") }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            // Made when the popup shows (not in `init`, which SwiftUI runs again and again): the player starts at the playhead.
            if playback == nil, let video { playback = CropPlayback(video: video) }
        }
        .onDisappear { playback?.stop() }
    }

    // MARK: Controls

    private var rotateDial: some View {
        RulerDial(value: $draft.rotation, mapping: rotation, detents: [0], neutral: 0, format: { String(format: "%.0f°", $0 == 0 ? 0 : $0) })
    }

    private var aspectTiles: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(CropAspect.allCases) { item in
                    let on = draft.aspect == item
                    Button { draft.aspect = item } label: {
                        VStack(spacing: 5) {
                            AspectGlyph(ratio: item.ratio ?? 1, custom: item == .custom)
                                .frame(width: 22, height: 22)
                                .frame(width: 64, height: 52)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.accentColor, lineWidth: on ? 2 : 0))
                            Text(item.title).font(.caption2).foregroundColor(on ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("cropAspect-\(item.title)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func paramButton(_ item: Param, value: String) -> some View {
        let selected = param == item
        return Button { param = item } label: {
            VStack(spacing: 4) {
                Circle().fill(selected ? Color.accentColor : Color(.secondarySystemBackground)).frame(width: 48, height: 48)
                    .overlay(Image(systemName: item.symbol).font(.system(size: 18, weight: .medium)).foregroundColor(selected ? .white : .primary))
                Text(value).font(.caption2.monospacedDigit()).foregroundColor(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cropParam-\(item.rawValue)")
    }

    private var flipButton: some View {
        Button { draft.flipped.toggle() } label: {
            VStack(spacing: 4) {
                Circle().fill(draft.flipped ? Color.accentColor : Color(.secondarySystemBackground)).frame(width: 48, height: 48)
                    .overlay(Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right").font(.system(size: 18, weight: .medium))
                        .foregroundColor(draft.flipped ? .white : .primary))
                Text(draft.flipped ? "On" : "Flip").font(.caption2).foregroundColor(draft.flipped ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cropFlip")
    }
}

/// The picture the crop frame is drawn on: a photo as it is, a video's frame under the playhead.
enum CropStill {
    @MainActor
    static func image(for layer: V2Layer, project: V2Project, atMs timelineMs: Double) async -> UIImage? {
        switch layer.payload {
        case .video(let payload):
            guard case .video(let asset)? = project.assets.first(where: { $0.id == payload.assetId }), let url = bundledURL(filename: asset.uri) else { return nil }
            let sourceMs = VideoTimeMapping(layer: layer)?.sourceMs(atTimelineMs: timelineMs) ?? payload.trimStart ?? 0
            return await VideoFrameCache.shared.frame(assetId: payload.assetId, url: url, atSeconds: max(sourceMs, 0) / 1000)
        case .image(let payload):
            guard case .image(let asset)? = project.assets.first(where: { $0.id == payload.assetId }), let url = bundledURL(filename: asset.uri) else { return nil }
            return await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                               kCGImageSourceThumbnailMaxPixelSize: 1400] as CFDictionary
                return CGImageSourceCreateThumbnailAtIndex(source, 0, options).map { UIImage(cgImage: $0) }
            }.value
        default:
            return nil
        }
    }
}

// MARK: Playing the clip

/// One opening of the popup (`.sheet(item:)`, like the Volume popup: what it needs is handed over when it opens, not read back from the shell's state).
struct CropSession: Identifiable {
    let id = UUID()
    let video: CropVideo?
}

/// What the popup needs to play a video clip: the file, where in it the clip starts and ends, and how long it is on the timeline.
struct CropVideo {
    let url: URL
    let startSourceMs: Double
    let endSourceMs: Double
    let durationMs: Double
    /// Width / height of the footage, for the picture's size before its first frame is there.
    let pictureAspect: Double
    /// Where the time bar opens (0...1 of the clip): the playhead.
    let initialFraction: Double
}

/// A real `AVPlayer` on the clip's file for the Crop popup (user 2026-10-18; measured on an iPhone 13 with 1080x1920 60 fps footage: the player delivers ~57
/// frames/s where one still every 150 ms gave 6.7 - `PLAYBACK_PIPELINE.md` section 9). Muted: cropping is visual. The time bar is a fraction of the clip, mapped
/// linearly onto the source stretch the clip plays. While the finger is on the bar only one seek is in flight and the newest request wins; on release the seek is exact.
@MainActor
@Observable
final class CropPlayback {
    @ObservationIgnored let player: AVPlayer
    private(set) var fraction: Double
    private(set) var isPlaying = false

    @ObservationIgnored private let startMs: Double
    @ObservationIgnored private let endMs: Double
    @ObservationIgnored private var observer: Any?
    @ObservationIgnored private var scrubbing = false
    @ObservationIgnored private var seeking = false
    @ObservationIgnored private var pending: Double?

    init(video: CropVideo) {
        player = AVPlayer(url: video.url)
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = false
        startMs = video.startSourceMs
        endMs = max(video.endSourceMs, video.startSourceMs + 1)
        fraction = video.initialFraction
        player.seek(to: time(for: fraction), toleranceBefore: .zero, toleranceAfter: .zero)
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] now in
            Task { @MainActor in self?.tick(now) }
        }
    }

    func toggle() { isPlaying ? pause() : play() }

    func play() {
        if fraction >= 0.999 { fraction = 0; player.seek(to: time(for: 0), toleranceBefore: .zero, toleranceAfter: .zero) }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    /// The finger moved the bar: stop and show that frame.
    func scrub(to value: Double) {
        pause()
        fraction = min(max(value, 0), 1)
        pending = fraction
        drain()
    }

    func setScrubbing(_ editing: Bool) {
        scrubbing = editing
        if editing { pause() } else { player.seek(to: time(for: fraction), toleranceBefore: .zero, toleranceAfter: .zero) }   // the exact frame on release
    }

    /// The popup is gone: stop and let go of the player.
    func stop() {
        pause()
        if let observer { player.removeTimeObserver(observer); self.observer = nil }
    }

    private func time(for value: Double) -> CMTime {
        CMTime(seconds: (startMs + value * (endMs - startMs)) / 1000, preferredTimescale: 600)
    }

    private func tick(_ now: CMTime) {
        guard isPlaying, !scrubbing else { return }
        let value = (now.seconds * 1000 - startMs) / (endMs - startMs)
        if value >= 1 { fraction = 1; pause() } else { fraction = max(value, 0) }
    }

    private func drain() {
        guard !seeking, let value = pending else { return }
        pending = nil
        seeking = true
        let tolerance = CMTime(seconds: 0.05, preferredTimescale: 600)
        player.seek(to: time(for: value), toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            Task { @MainActor in
                self?.seeking = false
                self?.drain()
            }
        }
    }
}

/// Play button, clock and time bar. Its own view, so the frames' 30 updates a second redraw only this row, not the whole popup.
private struct CropTimeBar: View {
    let playback: CropPlayback
    let durationMs: Double

    var body: some View {
        HStack(spacing: 10) {
            Button { playback.toggle() } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 16))
                    .frame(width: 34, height: 34)
                    .background(Color(.secondarySystemBackground), in: Circle())
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("cropPlay")
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
            Text("00:00").font(.caption.monospacedDigit()).foregroundColor(.secondary)
            Slider(value: Binding(get: { playback.fraction }, set: { playback.scrub(to: $0) }), onEditingChanged: { playback.setScrubbing($0) })
                .accessibilityIdentifier("cropScrub")
            Text(Self.clock(durationMs)).font(.caption.monospacedDigit()).foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
    }

    static func clock(_ ms: Double) -> String {
        let seconds = Int((ms / 1000).rounded())
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
