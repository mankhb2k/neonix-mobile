import SwiftUI

enum RecorderPhase { case ready, recording, review }

/// Gives its content the play progress (0...1) of a take played from `start`, redrawn every frame only while it plays.
struct PlaybackClock<Content: View>: View {
    let start: Date?
    let duration: TimeInterval
    @ViewBuilder let content: (Double) -> Content

    var body: some View {
        if let start {
            SwiftUI.TimelineView(.animation) { context in
                content(min(context.date.timeIntervalSince(start) / max(duration, 0.1), 1))
            }
        } else {
            content(0)
        }
    }
}

/// The recorder's waveform (the Recorder lab's design): dots while idle, red bars scrolling in from the right while recording, the whole take
/// (red up to the play head, grey after it) in review.
struct LiveWaveform: View {
    let levels: [Double]
    let phase: RecorderPhase
    /// nil while the take is not playing.
    let progress: Double?

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let step: CGFloat = 4
            func dots(upTo limit: CGFloat) {
                var x: CGFloat = 1
                while x < limit {
                    context.fill(Path(ellipseIn: CGRect(x: x - 1, y: midY - 1, width: 2, height: 2)), with: .color(Color(.systemGray3)))
                    x += step
                }
            }
            func bar(_ x: CGFloat, _ level: Double, _ color: Color) {
                let height = max(CGFloat(level) * size.height * 0.92, 2)
                context.fill(Path(roundedRect: CGRect(x: x - 1, y: midY - height / 2, width: 2, height: height), cornerRadius: 1), with: .color(color))
            }
            switch phase {
            case .ready:
                dots(upTo: size.width)
            case .recording:
                let capacity = Int(size.width / step)
                let visible = Array(levels.suffix(capacity))
                let first = size.width - CGFloat(visible.count) * step
                dots(upTo: first)
                for (index, level) in visible.enumerated() { bar(first + CGFloat(index) * step + step / 2, level, .red) }
            case .review:
                let count = max(Int(size.width / step), 1)
                guard !levels.isEmpty else { dots(upTo: size.width); return }
                for index in 0..<count {
                    let from = index * levels.count / count
                    let to = max((index + 1) * levels.count / count, from + 1)
                    let level = levels[from..<min(to, levels.count)].max() ?? 0
                    let played = progress.map { Double(index) / Double(count) < $0 } ?? true
                    bar(CGFloat(index) * step + step / 2, level, played ? .red : Color(.systemGray3))
                }
                if let progress, progress > 0 {
                    context.fill(Path(CGRect(x: size.width * progress - 0.75, y: 0, width: 1.5, height: size.height)), with: .color(.primary))
                }
            }
        }
    }
}
