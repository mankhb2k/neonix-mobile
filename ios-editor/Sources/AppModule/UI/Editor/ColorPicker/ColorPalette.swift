import SwiftUI
import UIKit

/// The colours every styling badge offers (text, stroke, glow, shadow, background): 40 ready-made swatches in a two-row grid plus
/// a custom picker (`ColorPickerPanel`). The eyedropper CapCut has is not built (user 2026-10-14: later).
/// Colours are `#RRGGBBff` strings, the form `EditorTextLayer.color` and Protocol V2 use.
enum ColorPalette {
    /// Column-major for a two-row grid: first two columns are neutrals (white over black, light over dark grey), then 18 hues in 20°
    /// steps - the top row vivid, the bottom row the soft tint of the same hue (readable on video, and a label colour).
    static let colors: [String] = {
        var list = ["#FFFFFFff", "#000000ff", "#D9D9D9ff", "#4D4D4Dff"]
        for step in 0..<18 {
            let hue = Double(step) / 18
            list.append(hex(hue: hue, saturation: 0.92, brightness: 1))
            list.append(hex(hue: hue, saturation: 0.4, brightness: 1))
        }
        return list
    }()

    static func hex(hue: Double, saturation: Double, brightness: Double) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02Xff", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    /// Hue, saturation and brightness (0...1) of a `#RRGGBB[AA]` colour; a grey keeps `hue` as given.
    static func hsb(of hex: String, keepingHue hue: Double = 0) -> (hue: Double, saturation: Double, brightness: Double) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(Color(hex: hex)).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (s < 0.001 || b < 0.001 ? hue : Double(h), Double(s), Double(b))
    }
}

/// The swatch area of a styling badge: a left column (an optional "none" dot and the rainbow button that opens the custom picker),
/// a divider, then the colours in a two-row grid that scrolls sideways. `recent` are the user's own colours, shown first.
struct ColorSwatchGrid: View {
    let selected: String?
    var recent: [String] = []
    var includesNone = false
    let idPrefix: String
    let pick: (String?) -> Void
    let openCustom: () -> Void

    private let dot: CGFloat = 34

    /// The grid fills column by column, two to a column: an odd number of user colours gets a gap so the palette keeps its pairs.
    private var cells: [String] {
        recent + (recent.count % 2 == 1 ? ["gap"] : []) + ColorPalette.colors.filter { !recent.contains($0) }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(spacing: 12) {
                if includesNone {
                    Button { pick(nil) } label: {
                        Image(systemName: "nosign").font(.system(size: 22)).foregroundColor(.secondary)
                            .frame(width: dot, height: dot)
                            .overlay(Circle().strokeBorder(selected == nil ? Color.accentColor : .clear, lineWidth: 3).padding(-4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(idPrefix)-none")
                }
                Button(action: openCustom) {
                    Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                        .frame(width: dot, height: dot)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Custom colour")
                .accessibilityIdentifier("\(idPrefix)-custom")
            }
            Divider().frame(height: includesNone ? 80 : 34)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: [GridItem(.fixed(dot), spacing: 12), GridItem(.fixed(dot), spacing: 12)], spacing: 12) {
                    ForEach(cells, id: \.self) { hex in
                        let on = selected?.lowercased() == hex.lowercased()
                        if hex.hasPrefix("gap") { Color.clear.frame(width: dot, height: dot) } else {
                        Button { pick(hex) } label: {
                            Circle().fill(Color(hex: hex)).frame(width: dot, height: dot)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                                .overlay(Circle().strokeBorder(on ? Color.accentColor : .clear, lineWidth: 3).padding(-4))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("\(idPrefix)-\(hex)")
                        }
                    }
                }
                .padding(.horizontal, 6).padding(.vertical, 6)
            }
        }
    }
}
