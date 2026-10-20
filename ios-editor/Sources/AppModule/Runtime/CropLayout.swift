import CoreGraphics
import Foundation

/// Where a cropped picture goes inside its layer's frame (the maths behind `V2Crop`, pure so it can be tested).
///
/// The layer draws its whole picture in the frame as before (`contain` or `cover`). The Crop tool's frame is a region of that picture; the region is
/// shown as large as it fits the frame (`contain`), centred. So: turn the picture about the frame's centre (flip, straighten, and a zoom that keeps its
/// turned corners out of the frame), then scale it up about the centre by `scale` and slide it by `offset` so the region's centre lands on the frame's, and
/// show only `visible`.
enum CropLayout {
    struct Plan: Equatable {
        /// Zoom applied with the straighten, so the turned picture still covers the region's bounds.
        var zoom: CGFloat
        /// Scale about the frame's centre that blows the region up to `visible`.
        var scale: CGFloat
        /// Slide, in the frame's points after `scale`, that brings the region's centre to the frame's centre.
        var offset: CGSize
        /// What shows, in the frame's own coordinates (always centred in it).
        var visible: CGRect
    }

    /// `pictureAspect` = picture width / height; `cover` = the layer fills its frame (`fit: cover`) instead of fitting it.
    static func plan(frame: CGSize, pictureAspect: Double, cover: Bool, crop: V2Crop) -> Plan? {
        guard frame.width > 0, frame.height > 0, pictureAspect > 0, crop.width > 0, crop.height > 0 else { return nil }
        let a = CGFloat(pictureAspect)
        // The picture as drawn in the frame.
        let fitWidth = min(frame.width, frame.height * a), fitHeight = fitWidth / a
        let fillWidth = max(frame.width, frame.height * a), fillHeight = fillWidth / a
        let picture = cover
            ? CGSize(width: fillWidth, height: fillHeight)
            : CGSize(width: fitWidth, height: fitHeight)
        let origin = CGPoint(x: (frame.width - picture.width) / 2, y: (frame.height - picture.height) / 2)
        let region = CGRect(x: origin.x + CGFloat(crop.x) * picture.width, y: origin.y + CGFloat(crop.y) * picture.height,
                            width: CGFloat(crop.width) * picture.width, height: CGFloat(crop.height) * picture.height)

        let regionAspect = region.width / region.height
        let width = min(frame.width, frame.height * regionAspect), height = width / regionAspect
        let visible = CGRect(x: (frame.width - width) / 2, y: (frame.height - height) / 2, width: width, height: height)
        let scale = visible.width / region.width
        let center = CGPoint(x: frame.width / 2, y: frame.height / 2)
        let offset = CGSize(width: -(region.midX - center.x) * scale, height: -(region.midY - center.y) * scale)

        let t = abs(CGFloat(crop.rotation ?? 0)) * .pi / 180
        let zoom = cos(t) + sin(t) * max(a, 1 / a)
        return Plan(zoom: zoom, scale: scale, offset: offset, visible: visible)
    }
}
