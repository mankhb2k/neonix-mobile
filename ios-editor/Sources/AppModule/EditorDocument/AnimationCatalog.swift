import Foundation

/// Where an animation sits on a clip: the entrance, the exit, or a loop over its whole length (CapCut's In / Out / Combo).
enum AnimationSlot: String, CaseIterable, Identifiable {
    case `in`, out, combo
    var id: String { rawValue }
    var title: String { self == .in ? "In" : self == .out ? "Out" : "Combo" }
}

/// One ready-made animation. A preset is a handful of channels (a Protocol V2 track path and normalised keyframes); `AnimationCatalog`
/// lowers it into atomic V2 tracks. In and Out presets are written as the entrance (`t` 0 = the hidden/offset start, 1 = at rest); the exit is
/// the same motion played backwards, ending at the clip's end. Combo presets are one cycle that loops for the whole clip.
struct AnimationPreset: Identifiable, Equatable {
    /// How a channel value is scaled: as is, or as a fraction of the canvas width / height (slides).
    enum Unit { case plain, canvasWidth, canvasHeight }

    struct Channel: Equatable {
        var path: String
        var keyframes: [(t: Double, value: Double)]
        var unit: Unit = .plain

        static func == (lhs: Channel, rhs: Channel) -> Bool {
            lhs.path == rhs.path && lhs.unit == rhs.unit && lhs.keyframes.count == rhs.keyframes.count
                && zip(lhs.keyframes, rhs.keyframes).allSatisfy { $0.t == $1.t && $0.value == $1.value }
        }
    }

    let id: String
    let title: String
    let group: String
    /// SF Symbol drawn on the tile.
    let symbol: String
    let slots: Set<AnimationSlot>
    let channels: [Channel]
    /// For a combo: one cycle's length in ms. In / Out use the chosen duration instead.
    var cycleMs: Double = 0
    var defaultDurationMs: Double = 500
}

enum AnimationCatalog {
    static let groups = ["Basic", "Slide", "Motion", "Loop"]

    private static let appear: AnimationPreset.Channel = .init(path: "opacity", keyframes: [(0, 0), (1, 1)])
    private static func scale(_ keys: [(Double, Double)]) -> [AnimationPreset.Channel] {
        [.init(path: "transform.scale.x", keyframes: keys), .init(path: "transform.scale.y", keyframes: keys)]
    }

    static let all: [AnimationPreset] = [
        AnimationPreset(id: "fade", title: "Fade", group: "Basic", symbol: "circle.lefthalf.filled", slots: [.in, .out], channels: [appear]),
        AnimationPreset(id: "zoom-in", title: "Zoom In", group: "Basic", symbol: "arrow.up.left.and.arrow.down.right", slots: [.in, .out],
                        channels: scale([(0, 0.5), (1, 1)]) + [appear]),
        AnimationPreset(id: "zoom-out", title: "Zoom Out", group: "Basic", symbol: "arrow.down.right.and.arrow.up.left", slots: [.in, .out],
                        channels: scale([(0, 1.5), (1, 1)]) + [appear]),
        AnimationPreset(id: "slide-left", title: "Slide Left", group: "Slide", symbol: "arrow.right", slots: [.in, .out],
                        channels: [.init(path: "transform.translate.x", keyframes: [(0, -0.4), (1, 0)], unit: .canvasWidth), appear]),
        AnimationPreset(id: "slide-right", title: "Slide Right", group: "Slide", symbol: "arrow.left", slots: [.in, .out],
                        channels: [.init(path: "transform.translate.x", keyframes: [(0, 0.4), (1, 0)], unit: .canvasWidth), appear]),
        AnimationPreset(id: "slide-up", title: "Slide Up", group: "Slide", symbol: "arrow.up", slots: [.in, .out],
                        channels: [.init(path: "transform.translate.y", keyframes: [(0, 0.3), (1, 0)], unit: .canvasHeight), appear]),
        AnimationPreset(id: "slide-down", title: "Slide Down", group: "Slide", symbol: "arrow.down", slots: [.in, .out],
                        channels: [.init(path: "transform.translate.y", keyframes: [(0, -0.3), (1, 0)], unit: .canvasHeight), appear]),
        AnimationPreset(id: "rotate", title: "Rotate", group: "Motion", symbol: "arrow.clockwise", slots: [.in, .out],
                        channels: [.init(path: "transform.rotate.z", keyframes: [(0, -90), (1, 0)]), appear] + scale([(0, 0.4), (1, 1)])),
        AnimationPreset(id: "spin", title: "Spin", group: "Motion", symbol: "arrow.triangle.2.circlepath", slots: [.in, .out],
                        channels: [.init(path: "transform.rotate.z", keyframes: [(0, -360), (1, 0)]), appear], defaultDurationMs: 700),
        AnimationPreset(id: "bounce", title: "Bounce", group: "Motion", symbol: "arrow.up.and.down", slots: [.in, .out],
                        channels: scale([(0, 0.3), (0.5, 1.15), (0.75, 0.95), (1, 1)]) + [.init(path: "opacity", keyframes: [(0, 0), (0.3, 1), (1, 1)])], defaultDurationMs: 700),
        AnimationPreset(id: "pop", title: "Pop", group: "Motion", symbol: "sparkle", slots: [.in, .out],
                        channels: scale([(0, 0), (0.6, 1.2), (1, 1)])),
        AnimationPreset(id: "swing", title: "Swing", group: "Motion", symbol: "metronome", slots: [.in, .out],
                        channels: [.init(path: "transform.rotate.z", keyframes: [(0, 25), (0.35, -15), (0.65, 8), (1, 0)]), .init(path: "opacity", keyframes: [(0, 0), (0.2, 1), (1, 1)])], defaultDurationMs: 800),
        AnimationPreset(id: "drop", title: "Drop", group: "Motion", symbol: "arrow.down.to.line", slots: [.in, .out],
                        channels: [.init(path: "transform.translate.y", keyframes: [(0, -0.4), (0.6, 0.03), (0.8, -0.01), (1, 0)], unit: .canvasHeight), appear], defaultDurationMs: 700),
        // Combo: one cycle, looped for the whole clip.
        AnimationPreset(id: "pulse", title: "Pulse", group: "Loop", symbol: "circle.circle", slots: [.combo],
                        channels: scale([(0, 1), (0.5, 1.08), (1, 1)]), cycleMs: 800),
        AnimationPreset(id: "heartbeat", title: "Heartbeat", group: "Loop", symbol: "heart", slots: [.combo],
                        channels: scale([(0, 1), (0.15, 1.12), (0.3, 1), (0.45, 1.08), (1, 1)]), cycleMs: 1000),
        AnimationPreset(id: "shake", title: "Shake", group: "Loop", symbol: "waveform", slots: [.combo],
                        channels: [.init(path: "transform.translate.x", keyframes: [(0, 0), (0.25, -0.02), (0.5, 0), (0.75, 0.02), (1, 0)], unit: .canvasWidth)], cycleMs: 240),
        AnimationPreset(id: "sway", title: "Sway", group: "Loop", symbol: "wind", slots: [.combo],
                        channels: [.init(path: "transform.rotate.z", keyframes: [(0, -5), (0.5, 5), (1, -5)])], cycleMs: 1600),
        AnimationPreset(id: "float", title: "Float", group: "Loop", symbol: "cloud", slots: [.combo],
                        channels: [.init(path: "transform.translate.y", keyframes: [(0, 0), (0.5, -0.02), (1, 0)], unit: .canvasHeight)], cycleMs: 1800),
        AnimationPreset(id: "blink", title: "Blink", group: "Loop", symbol: "eye", slots: [.combo],
                        channels: [.init(path: "opacity", keyframes: [(0, 1), (0.5, 0.35), (1, 1)])], cycleMs: 1000),
    ]

    static func preset(id: String) -> AnimationPreset? { all.first { $0.id == id } }
    static func presets(for slot: AnimationSlot) -> [AnimationPreset] { all.filter { $0.slots.contains(slot) } }

    /// The atomic V2 tracks of `preset` in `slot`. `layerId` only names the tracks; `canvas` scales the slides. In: absolute keyframes from the
    /// clip's start. Out: the same keyframes mirrored and end-anchored (trim-safe: it always finishes exactly at the clip's end). Combo: one
    /// cycle with an infinite loop.
    static func tracks(for preset: AnimationPreset, slot: AnimationSlot, durationMs: Double, canvas: (width: Double, height: Double), idPrefix: String) -> [V2Track] {
        func scaled(_ channel: AnimationPreset.Channel, _ value: Double) -> Double {
            switch channel.unit {
            case .plain: return value
            case .canvasWidth: return value * canvas.width
            case .canvasHeight: return value * canvas.height
            }
        }
        return preset.channels.map { channel in
            let keys = channel.keyframes
            let keyframes: [V2Keyframe]
            let playback: V2AnimationPlayback?
            switch slot {
            case .in:
                let easing = resolveEasing("easeOut")
                keyframes = keys.enumerated().map { i, k in
                    V2Keyframe(time: .absolute(k.t * durationMs), value: scaled(channel, k.value), easing: i < keys.count - 1 ? easing : nil)
                }
                playback = nil
            case .out:
                let easing = resolveEasing("easeIn")
                // Time before the end is `t * duration`; ascending time = descending `t`.
                keyframes = keys.reversed().enumerated().map { i, k in
                    V2Keyframe(time: .anchored(anchor: .end, offsetMs: k.t * durationMs), value: scaled(channel, k.value), easing: i < keys.count - 1 ? easing : nil)
                }
                playback = nil
            case .combo:
                let easing = resolveEasing("easeInOut")
                keyframes = keys.enumerated().map { i, k in
                    V2Keyframe(time: .absolute(k.t * preset.cycleMs), value: scaled(channel, k.value), easing: i < keys.count - 1 ? easing : nil)
                }
                playback = V2AnimationPlayback(durationMs: preset.cycleMs, delayMs: 0, iterations: .infinite, direction: .normal, fillMode: "none", playState: .running)
            }
            return V2Track(id: "\(idPrefix)-\(channel.path)", path: channel.path, keyframes: keyframes, animation: playback)
        }
    }
}
