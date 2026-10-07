import SwiftUI

/// One horizontal track per non-`"group"` layer, positioned/sized by its
/// own `timing`, plus a draggable playhead. No thumbnail extraction yet
/// (flat color blocks) and no pinch-to-zoom — both real future work.
struct TimelineView: View {
    let layers: [V2Layer]
    @Binding var currentTimeMs: Double
    let maxDurationMs: Double
    let onScrub: () -> Void

    private let pxPerMs: Double = 0.2
    private let rowHeight: CGFloat = 40
    private let rowSpacing: CGFloat = 6

    private var tracks: [V2Layer] {
        layers.filter { $0.type != "group" }.sorted { $0.order < $1.order }
    }

    private var contentWidth: CGFloat {
        max(CGFloat(maxDurationMs) * pxPerMs, 1)
    }

    private var contentHeight: CGFloat {
        CGFloat(max(tracks.count, 1)) * rowHeight + CGFloat(max(tracks.count - 1, 0)) * rowSpacing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(Int(currentTimeMs)) / \(Int(maxDurationMs)) ms")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: rowSpacing) {
                        ForEach(tracks, id: \.id) { layer in
                            TimelineClipView(layer: layer, pxPerMs: pxPerMs, rowHeight: rowHeight)
                        }
                    }

                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2, height: contentHeight)
                        .offset(x: CGFloat(currentTimeMs) * pxPerMs)
                }
                .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
                .padding(.horizontal)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            onScrub()
                            let fraction = min(max(value.location.x / contentWidth, 0), 1)
                            currentTimeMs = fraction * maxDurationMs
                        }
                )
            }
            .frame(height: contentHeight)
        }
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }
}

/// One clip block — a flat, color-keyed rectangle positioned/sized by the
/// layer's own timing, not a real filmstrip (see `TimelineView`'s doc
/// comment).
private struct TimelineClipView: View {
    let layer: V2Layer
    let pxPerMs: Double
    let rowHeight: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(color.opacity(0.18))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(color, lineWidth: 1))
            .overlay(alignment: .leading) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.caption2)
                    Text(layer.type.capitalized)
                        .font(.caption2)
                        .lineLimit(1)
                }
                .foregroundColor(color)
                .padding(.horizontal, 6)
            }
            .frame(width: max(CGFloat(layer.timing.duration) * pxPerMs, 28), height: rowHeight)
            .offset(x: CGFloat(layer.timing.start) * pxPerMs)
    }

    private var color: Color {
        switch layer.type {
        case "video": return .blue
        case "image": return .green
        case "text": return .orange
        case "audio": return .purple
        case "shape", "path": return .pink
        default: return .gray
        }
    }

    private var icon: String {
        switch layer.type {
        case "video": return "video.fill"
        case "image": return "photo.fill"
        case "text": return "textformat"
        case "audio": return "waveform"
        case "shape", "path": return "square.on.circle"
        default: return "square"
        }
    }
}
