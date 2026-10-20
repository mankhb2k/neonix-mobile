import SwiftUI
import UIKit

/// Gives the timeline the `UIScrollView` behind the lanes' `ScrollView`, so a clip dragged near the top or bottom of the lanes can scroll them by itself.
/// Put it as the background of the scrolling content; it walks up its superviews to the scroll view.
final class LaneScrollBox {
    weak var scrollView: UIScrollView?
}

struct LaneScrollFinder: UIViewRepresentable {
    let box: LaneScrollBox

    func makeUIView(context: Context) -> FinderView {
        let view = FinderView()
        view.isUserInteractionEnabled = false
        view.box = box
        return view
    }

    func updateUIView(_ uiView: FinderView, context: Context) { uiView.box = box }

    final class FinderView: UIView {
        var box: LaneScrollBox?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            var view: UIView? = superview
            while let current = view, !(current is UIScrollView) { view = current.superview }
            box?.scrollView = view as? UIScrollView
        }
    }
}

/// Speeds of the lanes' vertical auto-scroll while a clip is dragged (on screen, pt/s): slow within 40 pt of the viewport's top or bottom edge, fast within 16 pt.
enum LaneAutoScrollTuning {
    static let slowZone: CGFloat = 40
    static let fastZone: CGFloat = 16
    static let slowSpeed = 140.0
    static let fastSpeed = 420.0
    /// Seconds to ease between levels.
    static let ramp = 0.15

    /// Signed target speed for a finger at `y` over a viewport `top...bottom`: positive scrolls down (shows what is below), negative up, 0 away from the edges.
    static func targetSpeed(fingerY y: CGFloat, top: CGFloat, bottom: CGFloat) -> Double {
        guard bottom > top else { return 0 }
        let fromTop = y - top, fromBottom = bottom - y
        let (depth, sign): (CGFloat, Double) = fromBottom < fromTop ? (fromBottom, 1) : (fromTop, -1)
        if depth <= fastZone { return sign * fastSpeed }
        if depth <= slowZone { return sign * slowSpeed }
        return 0
    }
}

/// While a clip is held near the top or bottom of the lanes the whole lane area (picture lanes and audio tracks are one scroll) keeps scrolling, easing in and
/// out, until the finger leaves the zone, lifts, or the content ends. `onScrolled` is called after every step so the timeline re-reads the lanes' positions.
@MainActor
final class LaneAutoScroll {
    var box = LaneScrollBox()
    /// The lanes' visible area in the timeline panel's space.
    var viewport: ClosedRange<CGFloat> = 0...0
    private var onScrolled: () -> Void = {}
    private let clock = DisplayLinkClock()
    private var speed = 0.0
    private var target = 0.0

    func begin(onScrolled: @escaping () -> Void) {
        self.onScrolled = onScrolled
        speed = 0
        target = 0
    }

    /// Call on every move of the finger (`fingerY` in the panel's space).
    func update(fingerY: CGFloat) {
        target = LaneAutoScrollTuning.targetSpeed(fingerY: fingerY, top: viewport.lowerBound, bottom: viewport.upperBound)
        if target != 0, !clock.isRunning { clock.start { [weak self] dt in self?.tick(dt) } }
    }

    func stop() {
        clock.stop()
        speed = 0
        target = 0
    }

    private func tick(_ dt: Double) {
        speed += (target - speed) * min(dt / LaneAutoScrollTuning.ramp, 1)
        if target == 0, abs(speed) < 1 {
            stop()
            return
        }
        guard let scrollView = box.scrollView else { return }
        let inset = scrollView.adjustedContentInset
        let minY = -inset.top
        let maxY = max(scrollView.contentSize.height + inset.bottom - scrollView.bounds.height, minY)
        let next = min(max(scrollView.contentOffset.y + speed * dt, minY), maxY)
        if next == scrollView.contentOffset.y {
            speed = 0   // at the end of the content
            return
        }
        scrollView.contentOffset.y = next
        onScrolled()
    }
}
