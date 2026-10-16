import UIKit

/// The picture a project shows in the Folder list (user 2026-10-16): the first frame of the project - the main lane's first clip at
/// the moment it starts (a video frame through `VideoFrameCache`, or a photo's square tile), the same picture the editor's cover cell
/// uses. Overlays and text are not part of it. Nil when the project has no picture yet (the row keeps its gradient).
enum ProjectCover {
    @MainActor
    static func firstFrame(of project: V2Project, side: CGFloat) async -> UIImage? {
        guard let mainOrder = primaryVideoLaneOrder(of: project.layers),
              let clip = project.layers.filter({ $0.order == mainOrder && isPushLane($0) }).min(by: { $0.timing.start < $1.timing.start }),
              let assetId = clip.assetId,
              let asset = project.assets.first(where: { $0.id == assetId })
        else { return nil }
        switch (clip.payload, asset) {
        case (.video, .video(let video)):
            guard let url = bundledURL(filename: video.uri) else { return nil }
            let sourceMs = VideoTimeMapping(layer: clip)?.sourceMs(atTimelineMs: clip.timing.start) ?? 0
            return await VideoFrameCache.shared.frame(assetId: assetId, url: url, atSeconds: sourceMs / 1000)
        case (.image, .image(let image)):
            guard let url = bundledURL(filename: image.uri) else { return nil }
            return await PhotoThumbnailCache.tile(for: url, side: side)
        default:
            return nil
        }
    }
}
