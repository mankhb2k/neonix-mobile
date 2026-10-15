import SwiftUI
import CoreText

/// One run of a text layer as drawn on the stage: the words in their face (bold / italic resolved), letter spacing and underline; an
/// outline when the run has a stroke; shadows and glows as blurred copies behind. A run without stroke is plain SwiftUI `Text`
/// (cheap, what text always used); a stroked run is drawn from its glyph outlines (`GlyphOutline`), because `Text` cannot stroke.
struct TextRunView: View {
    let run: ResolvedTextRun

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(run.shadows.enumerated()), id: \.offset) { _, shadow in
                glyphs(fill: shadow.color, outline: run.strokeColor == nil ? nil : shadow.color)   // the shadow of the outlined shape
                    .offset(x: shadow.offsetX, y: shadow.offsetY)
                    .blur(radius: shadow.blur / 2)
            }
            glyphs(fill: run.color, outline: run.strokeColor)
        }
        .fixedSize()
        .opacity(run.opacity)
        .rotationEffect(.degrees(run.rotation))
        .offset(x: run.x, y: run.y)
    }

    @ViewBuilder private func glyphs(fill: V2Color, outline: V2Color?) -> some View {
        if let outline {
            let shape = GlyphOutline.outline(text: run.text, font: run.uiFont, letterSpacing: run.letterSpacing, underline: run.underline)
            ZStack(alignment: .topLeading) {
                Path(shape.path).stroke(Color(hex: outline), style: StrokeStyle(lineWidth: run.strokeWidth * 2, lineCap: .round, lineJoin: .round))
                Path(shape.path).fill(Color(hex: fill))
            }
            .frame(width: shape.size.width, height: shape.size.height, alignment: .topLeading)
        } else {
            Text(run.text)
                .font(Font(run.uiFont as CTFont))
                .tracking(run.letterSpacing)
                .underline(run.underline)
                .foregroundColor(Color(hex: fill))
        }
    }
}

/// The glyphs of a string as one path in the text's own box (origin at the top-left, the baseline `font.ascender` down), cached by
/// string and face: a stroked line is rebuilt only when its words or look change, not on every frame of playback.
final class GlyphOutline {
    let path: CGPath
    let size: CGSize
    init(path: CGPath, size: CGSize) { self.path = path; self.size = size }

    private static let cache: NSCache<NSString, GlyphOutline> = {
        let cache = NSCache<NSString, GlyphOutline>(); cache.countLimit = 256; return cache
    }()

    static func outline(text: String, font: UIFont, letterSpacing: Double, underline: Bool) -> GlyphOutline {
        let key = "\(text)|\(font.fontName)|\(font.pointSize)|\(letterSpacing)|\(underline)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if letterSpacing != 0 { attributes[.kern] = letterSpacing }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        let baseline = Double(font.ascender)
        let path = CGMutablePath()
        for case let run as CTRun in CTLineGetGlyphRuns(line) as NSArray {
            let runAttributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = (runAttributes[kCTFontAttributeName as String] as! CTFont?) ?? (font as CTFont)
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            for i in 0..<count {
                guard let glyph = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) else { continue }
                // Glyph outlines are y-up around the baseline; the box is y-down.
                path.addPath(glyph, transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: positions[i].x, ty: baseline - Double(positions[i].y)))
            }
        }
        if underline {
            let thickness = max(Double(CTFontGetUnderlineThickness(font as CTFont)), 1)
            path.addRect(CGRect(x: 0, y: baseline - Double(CTFontGetUnderlinePosition(font as CTFont)) - thickness / 2, width: width, height: thickness))
        }
        let result = GlyphOutline(path: path, size: CGSize(width: ceil(width), height: ceil(Double(font.lineHeight))))
        cache.setObject(result, forKey: key)
        return result
    }
}
