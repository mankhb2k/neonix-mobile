import AVFoundation
import SwiftUI

/// The Crop tool's working frame, shared by the editor and the Crop lab (the lab's layout B was chosen 2026-10-18). `CropDraft` is the frame being
/// edited; `CropStage` draws the picture with it and handles the gestures.


enum CropAspect: String, CaseIterable, Identifiable {
    case custom, r916, r169, r11, r43, r34, r21
    var id: String { rawValue }

    /// Width over height of the crop in the picture's own pixels; nil = free.
    var ratio: Double? {
        switch self {
        case .custom: return nil
        case .r916: return 9.0 / 16
        case .r169: return 16.0 / 9
        case .r11: return 1
        case .r43: return 4.0 / 3
        case .r34: return 3.0 / 4
        case .r21: return 2
        }
    }

    var title: String {
        switch self {
        case .custom: return "Custom"
        case .r916: return "9:16"
        case .r169: return "16:9"
        case .r11: return "1:1"
        case .r43: return "4:3"
        case .r34: return "3:4"
        case .r21: return "2:1"
        }
    }
}

struct CropDraft: Equatable {
    init() {}

    /// From a clip's stored crop (nothing stored = the whole picture). The ratio lock is not stored: it starts free.
    init(crop: V2Crop?) {
        guard let crop else { return }
        rect = CGRect(x: crop.x, y: crop.y, width: crop.width, height: crop.height)
        rotation = crop.rotation ?? 0
        flipped = crop.flipped ?? false
    }

    /// What goes to the clip (`SetClipCropCommand` stores nothing when it changes nothing).
    var v2: V2Crop {
        V2Crop(x: Double(rect.minX), y: Double(rect.minY), width: Double(rect.width), height: Double(rect.height),
               rotation: rotation == 0 ? nil : rotation, flipped: flipped ? true : nil)
    }

    /// The frame in the picture's own space (each 0...1).
    var rect = CGRect(x: 0, y: 0, width: 1, height: 1)
    /// Degrees; the picture turns behind the frame.
    var rotation = 0.0
    var aspect: CropAspect = .custom
    var flipped = false

    var isChanged: Bool { self != CropDraft() }
}

/// A rounded outline with the ratio's shape (the tiles' icons); Custom is the corner-brackets symbol.
struct AspectGlyph: View {
    let ratio: Double
    var custom = false

    var body: some View {
        if custom {
            Image(systemName: "crop").font(.system(size: 17, weight: .medium)).foregroundColor(.primary)
        } else {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let width = ratio >= 1 ? side : side * ratio
                let height = ratio >= 1 ? side / ratio : side
                RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(Color.primary, lineWidth: 1.8)
                    .frame(width: width, height: height)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
    }
}

// MARK: The working crop frame

/// The picture with the crop frame on it. Drag a corner to resize (the opposite corner stays), drag inside to move; with an aspect picked the ratio
/// is kept. The frame is stored in the picture's space, so it survives a resize of the stage.
struct CropStage: View {
    let image: UIImage?
    /// A video clip: the running player is drawn over the still (which shows until its first frame).
    var player: AVPlayer?
    /// The picture's width / height when there is no still yet (a video's size).
    var pictureAspect: Double?
    @Binding var crop: CropDraft

    private enum Drag { case move(CGRect), corner(anchor: CGPoint) }
    @State private var drag: Drag?
    private let handle: CGFloat = 40
    private let minSide: CGFloat = 48

    var body: some View {
        GeometryReader { geo in
            let aspect = image.map { $0.size.width / $0.size.height } ?? pictureAspect ?? 0.75
            let display = fit(aspect, in: CGRect(origin: .zero, size: geo.size))
            let frame = self.frame(in: display)
            ZStack {
                if image != nil || player != nil {
                    ZStack {
                        if let image { Image(uiImage: image).resizable() }
                        if let player { CropPlayerLayerView(player: player) }
                    }
                    .frame(width: display.width, height: display.height)
                    .scaleEffect(x: (crop.flipped ? -1 : 1) * zoom(aspect), y: zoom(aspect))
                    .rotationEffect(.degrees(crop.rotation))
                    .position(x: display.midX, y: display.midY)
                    .clipShape(Path(display))
                } else {
                    ProgressView()
                }
                Canvas { context, _ in
                    context.fill(Path { $0.addRect(display); $0.addRect(frame) }, with: .color(.black.opacity(0.5)), style: FillStyle(eoFill: true))
                    context.stroke(Path(frame), with: .color(.white), lineWidth: 1.5)
                    for i in 1...2 {
                        let t = CGFloat(i) / 3
                        context.stroke(Path { p in
                            p.move(to: CGPoint(x: frame.minX + frame.width * t, y: frame.minY)); p.addLine(to: CGPoint(x: frame.minX + frame.width * t, y: frame.maxY))
                            p.move(to: CGPoint(x: frame.minX, y: frame.minY + frame.height * t)); p.addLine(to: CGPoint(x: frame.maxX, y: frame.minY + frame.height * t))
                        }, with: .color(.white.opacity(0.55)), lineWidth: 0.8)
                    }
                    let arm: CGFloat = 22
                    for corner in Corner.allCases {
                        let dx = corner.isLeft ? 1.0 : -1.0, dy = corner.isTop ? 1.0 : -1.0
                        let edge = corner.point(of: frame)
                        let p = CGPoint(x: edge.x + dx * 2, y: edge.y + dy * 2)   // inside the frame, over the picture
                        let bracket = Path { path in
                            path.move(to: CGPoint(x: p.x + dx * arm, y: p.y)); path.addLine(to: p); path.addLine(to: CGPoint(x: p.x, y: p.y + dy * arm))
                        }
                        context.stroke(bracket, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                        context.stroke(bracket, with: .color(.white), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    }
                }
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in change(value, display: display) }
                    .onEnded { _ in drag = nil }
            )
            .onChange(of: crop.aspect) { _, new in applyAspect(new, display: display) }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("cropStage")
            .accessibilityValue(String(format: "%.0f,%.0f,%.0f,%.0f", frame.minX, frame.minY, frame.width, frame.height))
        }
    }

    // MARK: Geometry

    /// Largest rect of `aspect` inside `box`, with a little room around it.
    private func fit(_ aspect: CGFloat, in box: CGRect) -> CGRect {
        let inner = box.insetBy(dx: 14, dy: 14)
        let width = min(inner.width, inner.height * aspect)
        let height = width / aspect
        return CGRect(x: inner.midX - width / 2, y: inner.midY - height / 2, width: width, height: height)
    }

    private func frame(in display: CGRect) -> CGRect {
        CGRect(x: display.minX + crop.rect.minX * display.width, y: display.minY + crop.rect.minY * display.height,
               width: crop.rect.width * display.width, height: crop.rect.height * display.height)
    }

    private func store(_ frame: CGRect, display: CGRect) {
        crop.rect = CGRect(x: (frame.minX - display.minX) / display.width, y: (frame.minY - display.minY) / display.height,
                           width: frame.width / display.width, height: frame.height / display.height)
    }

    /// The picture is zoomed just enough that its turned corners never show inside the frame's bounds.
    private func zoom(_ aspect: CGFloat) -> CGFloat {
        let t = abs(crop.rotation) * .pi / 180
        return CGFloat(cos(t) + sin(t) * max(aspect, 1 / aspect))
    }

    enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
        var isLeft: Bool { self == .topLeft || self == .bottomLeft }
        var isTop: Bool { self == .topLeft || self == .topRight }
        func point(of r: CGRect) -> CGPoint { CGPoint(x: isLeft ? r.minX : r.maxX, y: isTop ? r.minY : r.maxY) }
        var opposite: Corner {
            switch self {
            case .topLeft: return .bottomRight
            case .topRight: return .bottomLeft
            case .bottomLeft: return .topRight
            case .bottomRight: return .topLeft
            }
        }
    }

    // MARK: Gestures

    private func change(_ value: DragGesture.Value, display: CGRect) {
        let frame = self.frame(in: display)
        if drag == nil {
            if let corner = Corner.allCases.min(by: { distance($0.point(of: frame), value.startLocation) < distance($1.point(of: frame), value.startLocation) }),
               distance(corner.point(of: frame), value.startLocation) < handle {
                drag = .corner(anchor: corner.opposite.point(of: frame))
            } else if frame.insetBy(dx: -6, dy: -6).contains(value.startLocation) {
                drag = .move(frame)
            }
        }
        switch drag {
        case .move(let start):
            var next = start.offsetBy(dx: value.translation.width, dy: value.translation.height)
            next.origin.x = min(max(next.minX, display.minX), display.maxX - next.width)
            next.origin.y = min(max(next.minY, display.minY), display.maxY - next.height)
            store(next, display: display)
        case .corner(let anchor):
            let p = CGPoint(x: min(max(value.location.x, display.minX), display.maxX), y: min(max(value.location.y, display.minY), display.maxY))
            store(resized(anchor: anchor, to: p, display: display), display: display)
        case nil:
            break
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    private func resized(anchor: CGPoint, to p: CGPoint, display: CGRect) -> CGRect {
        let right = p.x >= anchor.x, down = p.y >= anchor.y
        var width = max(abs(p.x - anchor.x), minSide), height = max(abs(p.y - anchor.y), minSide)
        if let ratio = crop.aspect.ratio {
            // The picture's pixels are scaled evenly, so the on-screen ratio is the pixel ratio.
            width = max(width, height * ratio)
            height = width / ratio
            let room = CGSize(width: right ? display.maxX - anchor.x : anchor.x - display.minX, height: down ? display.maxY - anchor.y : anchor.y - display.minY)
            let shrink = min(1, room.width / width, room.height / height)
            width *= shrink; height *= shrink
        }
        return CGRect(x: right ? anchor.x : anchor.x - width, y: down ? anchor.y : anchor.y - height, width: width, height: height)
    }

    /// Picking a ratio: the largest frame of that shape that fits the picture, around the frame's centre.
    private func applyAspect(_ aspect: CropAspect, display: CGRect) {
        guard let ratio = aspect.ratio else { return }
        let current = frame(in: display)
        var width = display.width, height = width / ratio
        if height > display.height { height = display.height; width = height * ratio }
        var next = CGRect(x: current.midX - width / 2, y: current.midY - height / 2, width: width, height: height)
        next.origin.x = min(max(next.minX, display.minX), display.maxX - width)
        next.origin.y = min(max(next.minY, display.minY), display.maxY - height)
        withAnimation(.easeOut(duration: 0.2)) { store(next, display: display) }
    }
}

/// The video's own frames, drawn by Core Animation (no SwiftUI redraw per frame): a plain `AVPlayerLayer`.
struct CropPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}
