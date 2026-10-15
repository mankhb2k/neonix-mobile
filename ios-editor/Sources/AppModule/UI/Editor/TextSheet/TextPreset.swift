import Foundation

/// A ready-made look in the Style tab's first row (CapCut's "Aa" tiles): a named bundle of the values the renderer can draw today,
/// i.e. the text colour and the story-style label. Outline / shadow looks come with the Stroke and Shadow badges. Picking one
/// sets only these two fields - font, size and alignment stay.
struct TextPreset: Identifiable, Equatable {
    let id: String
    let color: String
    let background: String?

    /// First tile: white words, no label - what a new clip starts as.
    static let plain = TextPreset(id: "plain", color: "#FFFFFFff", background: nil)

    static let all: [TextPreset] = [
        plain,
        TextPreset(id: "black", color: "#000000ff", background: nil),
        TextPreset(id: "yellow", color: "#FFD60Aff", background: nil),
        TextPreset(id: "orange", color: "#FF9500ff", background: nil),
        TextPreset(id: "red", color: "#FF3B30ff", background: nil),
        TextPreset(id: "blue", color: "#007AFFff", background: nil),
        TextPreset(id: "black-on-white", color: "#000000ff", background: "#FFFFFFff"),
        TextPreset(id: "white-on-black", color: "#FFFFFFff", background: "#000000ff"),
        TextPreset(id: "black-on-yellow", color: "#000000ff", background: "#FFD60Aff"),
        TextPreset(id: "white-on-red", color: "#FFFFFFff", background: "#FF3B30ff"),
        TextPreset(id: "white-on-purple", color: "#FFFFFFff", background: "#AF52DEff"),
    ]

    /// Whether the words are light (so the tile behind them must be dark). `#RRGGBBAA`.
    var textIsLight: Bool {
        let hex = color.dropFirst()
        guard hex.count >= 6, let rgb = UInt32(hex.prefix(6), radix: 16) else { return true }
        let r = Double(rgb >> 16 & 255), g = Double(rgb >> 8 & 255), b = Double(rgb & 255)
        return 0.299 * r + 0.587 * g + 0.114 * b > 140
    }

    func matches(_ values: TextStyleValues) -> Bool {
        values.color.lowercased() == color.lowercased() && values.backgroundColor?.lowercased() == background?.lowercased()
    }

    func apply(to values: inout TextStyleValues) {
        values.color = color
        values.backgroundColor = background
    }
}
