import CoreGraphics
import Foundation

/// The four shapes of the Mask tool (user 2026-10-18: Horizontal, Mirror, Circle, Rectangle; more later).
enum MaskShape: String, CaseIterable, Identifiable {
    case none, horizontal, mirror, circle, rectangle
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .horizontal: return "Horizontal"
        case .mirror: return "Mirror"
        case .circle: return "Circle"
        case .rectangle: return "Rectangle"
        }
    }

    var symbol: String {
        switch self {
        case .none: return "nosign"
        case .horizontal: return "rectangle.tophalf.filled"
        case .mirror: return "rectangle.center.inset.filled"
        case .circle: return "circle"
        case .rectangle: return "rectangle"
        }
    }

    /// Whether the shape has a width / height of its own (a half-plane has none, a band only a thickness).
    var hasWidth: Bool { self == .circle || self == .rectangle }
    var hasHeight: Bool { self == .circle || self == .rectangle || self == .mirror }
}

/// The mask being edited, in the units people work in: the centre as fractions of the layer box (0...1), sizes as fractions of the box's shorter side,
/// the angle in degrees clockwise, `feather` 0...1 (1 = a blur of a tenth of the shorter side), `roundness` 0...1 of the rectangle's half-short-side.
/// `v2Mask` turns it into the Protocol V2 mask the renderer draws; the mask is never stored in this form.
struct MaskDraft: Equatable {
    var shape: MaskShape = .none
    var centerX = 0.5
    var centerY = 0.5
    var width = 0.5
    var height = 0.5
    var rotation = 0.0
    var feather = 0.0
    var invert = false
    var roundness = 0.0

    init() {}

    /// A fresh mask of `shape` with sensible starting sizes (a picked shape keeps nothing of the last one except the invert switch).
    init(shape: MaskShape, keeping previous: MaskDraft = MaskDraft()) {
        self.shape = shape
        invert = previous.invert
        switch shape {
        case .none: break
        case .horizontal: break
        case .mirror: height = 0.35
        case .circle: width = 0.5; height = 0.5
        case .rectangle: width = 0.5; height = 0.7
        }
    }

    var isChanged: Bool { self != MaskDraft() }

    /// Largest blur, as a fraction of the shorter side, at `feather == 1`.
    static let maxFeather = 0.1

    /// The Protocol V2 mask for a layer box of `frame` px (children in the layer's own pixels - the default `maskContentUnits`, so a rotation stays a
    /// rotation on a box that is not square); nil for `.none`.
    func v2Mask(id: String, frame: CGSize) -> V2Mask? {
        guard shape != .none, frame.width > 0, frame.height > 0 else { return nil }
        let short = Double(min(frame.width, frame.height)), reach = 4 * Double(max(frame.width, frame.height))
        let cx = centerX * Double(frame.width), cy = centerY * Double(frame.height)
        let spin: [V2SvgTransformOperation]? = rotation == 0 ? nil : [.rotate(angle: rotation, center: V2Vec2(x: cx, y: cy))]
        let common = V2SvgDefinitionNodeCommon(transform: spin, fill: .color("#FFFFFF"))
        let node: V2SvgDefinitionNode
        switch shape {
        case .none:
            return nil
        case .horizontal:
            // What is above the line through the centre.
            node = .rect(x: cx - reach, y: cy - reach, width: 2 * reach, height: reach, rx: nil, ry: nil, common: common)
        case .mirror:
            let band = height * short
            node = .rect(x: cx - reach, y: cy - band / 2, width: 2 * reach, height: band, rx: nil, ry: nil, common: common)
        case .circle:
            node = .ellipse(cx: cx, cy: cy, rx: width * short / 2, ry: height * short / 2, common: common)
        case .rectangle:
            let w = width * short, h = height * short, radius = roundness * min(w, h) / 2
            node = .rect(x: cx - w / 2, y: cy - h / 2, width: w, height: h, rx: radius == 0 ? nil : radius, ry: radius == 0 ? nil : radius, common: common)
        }
        return V2Mask(id: id, maskType: "alpha", children: [node], feather: feather == 0 ? nil : feather * Self.maxFeather * short, invert: invert ? true : nil)
    }
}

// MARK: Reading a stored mask back

extension MaskDraft {
    /// The editor's draft for a V2 mask this tool wrote (`v2Mask`'s inverse): the shape is told by the mask's id (`SetLayerMaskCommand.maskId`), the numbers
    /// come back out of the children. nil for a mask of any other make.
    init?(mask: V2Mask, shape: MaskShape, frame: CGSize) {
        guard shape != .none, frame.width > 0, frame.height > 0, let node = mask.children?.first else { return nil }
        let w = Double(frame.width), h = Double(frame.height), short = Double(min(frame.width, frame.height))
        func angle(_ common: V2SvgDefinitionNodeCommon) -> Double {
            for case .rotate(let degrees, _) in common.transform ?? [] { return degrees }
            return 0
        }
        var draft = MaskDraft()
        draft.shape = shape
        switch (shape, node) {
        case (.circle, .ellipse(let cx, let cy, let rx, let ry, let common)):
            draft.centerX = cx / w; draft.centerY = cy / h
            draft.width = 2 * rx / short; draft.height = 2 * ry / short
            draft.rotation = angle(common)
        case (.rectangle, .rect(let x, let y, let rw, let rh, let rx, _, let common)):
            draft.centerX = (x + rw / 2) / w; draft.centerY = (y + rh / 2) / h
            draft.width = rw / short; draft.height = rh / short
            draft.roundness = min(max((rx ?? 0) / max(min(rw, rh) / 2, 0.0001), 0), 1)
            draft.rotation = angle(common)
        case (.mirror, .rect(let x, let y, let rw, let rh, _, _, let common)):
            draft.centerX = (x + rw / 2) / w; draft.centerY = (y + rh / 2) / h
            draft.height = rh / short
            draft.rotation = angle(common)
        case (.horizontal, .rect(let x, let y, let rw, let rh, _, _, let common)):
            draft.centerX = (x + rw / 2) / w; draft.centerY = (y + rh) / h
            draft.rotation = angle(common)
        default:
            return nil
        }
        draft.feather = (mask.feather ?? 0) / (Self.maxFeather * short)
        draft.invert = mask.invert ?? false
        self = draft
    }

    /// The draft of `layer`'s own mask (none when it has no mask of this tool's making). `frame` is the layer's own box.
    init(layer: V2Layer, masks: [V2Mask]) {
        let frame = CGSize(width: layer.frame.width, height: layer.frame.height)
        if let id = layer.mask, let shape = SetLayerMaskCommand.shape(ofMaskId: id), let mask = masks.first(where: { $0.id == id }),
           let draft = MaskDraft(mask: mask, shape: shape, frame: frame) {
            self = draft
        } else {
            self = MaskDraft()
        }
    }
}

// MARK: Parameters of the controls (shared by the lab and the editor's popup)

/// What the Mask tool's controls edit. Which ones a shape has: everything has Position, Rotate and Feather; Size needs a height (band, circle, rectangle);
/// Round is a rectangle's.
enum MaskParameter: String, CaseIterable, Identifiable {
    case position, rotate, size, feather, roundness
    var id: String { rawValue }

    var title: String {
        switch self {
        case .position: return "Position"
        case .rotate: return "Rotate"
        case .size: return "Size"
        case .feather: return "Feather"
        case .roundness: return "Round"
        }
    }

    var symbol: String {
        switch self {
        case .position: return "arrow.up.and.down.and.arrow.left.and.right"
        case .rotate: return "rotate.right"
        case .size: return "arrow.up.left.and.arrow.down.right"
        case .feather: return "aqi.medium"
        case .roundness: return "square.on.square.squareshape.controlhandles"
        }
    }

    func applies(to shape: MaskShape) -> Bool {
        switch self {
        case .position, .rotate, .feather: return shape != .none
        case .size: return shape.hasHeight
        case .roundness: return shape == .rectangle
        }
    }

    /// Two ways from a middle mark (0): Transform's ruler. The others run one way from 0: a plain slider.
    var isTwoWay: Bool { self == .position || self == .rotate }
}

/// One number a control edits, in the units it is shown in.
struct MaskAxis: Identifiable {
    let id: String
    let title: String
    let range: ClosedRange<Double>
    let step: Double
    let majorEvery: Int
    let neutral: Double?
    let get: (MaskDraft) -> Double
    let set: (inout MaskDraft, Double) -> Void

    static func axes(for parameter: MaskParameter, shape: MaskShape) -> [MaskAxis] {
        switch parameter {
        case .position:
            return [MaskAxis(id: "x", title: "X axis", range: -50...50, step: 1, majorEvery: 10, neutral: 0, get: { ($0.centerX - 0.5) * 100 }, set: { $0.centerX = 0.5 + $1 / 100 }),
                    MaskAxis(id: "y", title: "Y axis", range: -50...50, step: 1, majorEvery: 10, neutral: 0, get: { ($0.centerY - 0.5) * 100 }, set: { $0.centerY = 0.5 + $1 / 100 })]
        case .rotate:
            return [MaskAxis(id: "rotate", title: "Rotate", range: -180...180, step: 1, majorEvery: 45, neutral: 0, get: { $0.rotation }, set: { $0.rotation = $1 })]
        case .size:
            var list: [MaskAxis] = []
            if shape.hasWidth { list.append(MaskAxis(id: "width", title: "Width", range: 5...200, step: 1, majorEvery: 25, neutral: nil, get: { $0.width * 100 }, set: { $0.width = $1 / 100 })) }
            if shape.hasHeight { list.append(MaskAxis(id: "height", title: shape == .mirror ? "Thickness" : "Height", range: 5...200, step: 1, majorEvery: 25, neutral: nil, get: { $0.height * 100 }, set: { $0.height = $1 / 100 })) }
            return list
        case .feather:
            return [MaskAxis(id: "feather", title: "Feather", range: 0...100, step: 1, majorEvery: 10, neutral: 0, get: { $0.feather * 100 }, set: { $0.feather = $1 / 100 })]
        case .roundness:
            return [MaskAxis(id: "round", title: "Round", range: 0...100, step: 1, majorEvery: 10, neutral: 0, get: { $0.roundness * 100 }, set: { $0.roundness = $1 / 100 })]
        }
    }
}
