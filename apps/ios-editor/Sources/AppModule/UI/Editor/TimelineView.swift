import SwiftUI

/// The timeline below the stage/controls row — one horizontal track per
/// `project.layers[]` entry (excluding `"group"` wrapper layers, which have
/// no content of their own, only children — see CLAUDE.md's "Group layers
/// compose transform/opacity by real view nesting" note), positioned and
/// sized by each layer's own `timing.start`/`timing.duration`, plus a
/// draggable playhead synced to `currentTimeMs`.
///
/// **No thumbnail extraction yet** — each clip renders as a flat color
/// block (color/icon keyed by `layer.type`), not a real filmstrip. That's a
/// known, separate gap (see `VideoFrameCache`'s own doc comment for the
/// still-frame extraction this would reuse), not an oversight here.
///
/// `pxPerMs` is a fixed scale, not a pinch-to-zoom control — zooming the
/// timeline is real future work, not in scope for this first pass.
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
