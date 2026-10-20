import SwiftUI

/// Draws a Protocol V2 mask as a matte (alpha = what shows) the size of the layer's box, to be used as `.mask { }` on the layer. The children are read in the
/// layer's own pixels (`maskContentUnits: userSpaceOnUse`, the default); only rect / circle / ellipse / polygon / group are drawn so far, with their
/// `transform` and `fillOpacity`. `feather` blurs the finished matte (it is drawn on a canvas padded by three times that, so the blur does not fade the
/// box's own edge), `invert` flips it.
struct MaskMatteView: View {
    let mask: V2Mask
    let size: CGSize

    var body: some View {
        let feather = max(mask.feather ?? 0, 0)
        let pad = feather * 3
        Canvas { context, _ in
            context.translateBy(x: pad, y: pad)
            if mask.invert == true {
                context.fill(Path(CGRect(x: -pad, y: -pad, width: size.width + 2 * pad, height: size.height + 2 * pad)), with: .color(.white))
                context.blendMode = .destinationOut
            }
            for node in mask.children ?? [] { Self.draw(node, in: &context) }
        }
        .frame(width: size.width + 2 * pad, height: size.height + 2 * pad)
        .blur(radius: feather)
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    // MARK: Drawing

    private static func draw(_ node: V2SvgDefinitionNode, in context: inout GraphicsContext) {
        var inner = context
        switch node {
        case .rect(let x, let y, let width, let height, let rx, let ry, let common):
            apply(common.transform, to: &inner)
            let rect = CGRect(x: x, y: y, width: width, height: height)
            let path = (rx ?? 0) > 0 || (ry ?? 0) > 0
                ? Path(roundedRect: rect, cornerSize: CGSize(width: rx ?? ry ?? 0, height: ry ?? rx ?? 0), style: .continuous)
                : Path(rect)
            fill(path, common, in: &inner)
        case .circle(let cx, let cy, let r, let common):
            apply(common.transform, to: &inner)
            fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)), common, in: &inner)
        case .ellipse(let cx, let cy, let rx, let ry, let common):
            apply(common.transform, to: &inner)
            fill(Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry)), common, in: &inner)
        case .polygon(let points, let common):
            apply(common.transform, to: &inner)
            guard let first = points.first else { return }
            var path = Path()
            path.move(to: CGPoint(x: first.x, y: first.y))
            for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
            path.closeSubpath()
            fill(path, common, in: &inner)
        case .group(let children, let opacity, let common):
            apply(common.transform, to: &inner)
            inner.opacity = opacity ?? 1
            for child in children { draw(child, in: &inner) }
        case .path, .line, .polyline:
            break   // not drawn yet
        }
    }

    private static func fill(_ path: Path, _ common: V2SvgDefinitionNodeCommon, in context: inout GraphicsContext) {
        if case .some(.none) = common.fill { return }
        context.fill(path, with: .color(.white.opacity(common.fillOpacity ?? 1)))
    }

    /// SVG's transform list, first operation outermost, as the context's current transform.
    private static func apply(_ operations: [V2SvgTransformOperation]?, to context: inout GraphicsContext) {
        for operation in operations ?? [] {
            switch operation {
            case .translate(let x, let y): context.translateBy(x: x, y: y)
            case .scale(let x, let y): context.scaleBy(x: x, y: y)
            case .rotate(let angle, let center):
                let c = center ?? V2Vec2(x: 0, y: 0)
                context.translateBy(x: c.x, y: c.y)
                context.rotate(by: .degrees(angle))
                context.translateBy(x: -c.x, y: -c.y)
            case .skewX(let angle): context.concatenate(CGAffineTransform(a: 1, b: 0, c: tan(angle * .pi / 180), d: 1, tx: 0, ty: 0))
            case .skewY(let angle): context.concatenate(CGAffineTransform(a: 1, b: tan(angle * .pi / 180), c: 0, d: 1, tx: 0, ty: 0))
            case .matrix(let m): context.concatenate(CGAffineTransform(a: m.0, b: m.1, c: m.2, d: m.3, tx: m.4, ty: m.5))
            }
        }
    }
}
