import QuartzCore

/// Calls back once per screen refresh with the elapsed time since the
/// previous refresh. Used by `EditorPlaybackEngine` as the single tick
/// source for both playback and momentum — aligned to the display's vsync
/// (60 or 120 Hz), unlike a `Task.sleep` loop that drifts against it.
@MainActor
final class DisplayLinkClock {
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var onTick: ((Double) -> Void)?

    var isRunning: Bool { link != nil }

    /// `onTick` receives seconds elapsed since the previous frame. The very
    /// first frame after `start` only records a timestamp.
    func start(onTick: @escaping (Double) -> Void) {
        stop()
        self.onTick = onTick
        let link = CADisplayLink(target: DisplayLinkTarget(clock: self), selector: #selector(DisplayLinkTarget.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        lastTimestamp = nil
        onTick = nil
    }

    fileprivate func tick(timestamp: CFTimeInterval) {
        defer { lastTimestamp = timestamp }
        guard let lastTimestamp else { return }
        onTick?(timestamp - lastTimestamp)
    }
}

/// `CADisplayLink` retains its target strongly; this weak hop keeps the
/// clock (and the engine owning it) free to deallocate, and invalidates the
/// link itself once the clock is gone.
private final class DisplayLinkTarget: NSObject {
    weak var clock: DisplayLinkClock?

    init(clock: DisplayLinkClock) {
        self.clock = clock
    }

    @objc func tick(_ link: CADisplayLink) {
        MainActor.assumeIsolated {
            guard let clock else {
                link.invalidate()
                return
            }
            clock.tick(timestamp: link.timestamp)
        }
    }
}
