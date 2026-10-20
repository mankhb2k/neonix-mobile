import SwiftUI
import UIKit

/// Notices a press-and-hold on a free clip (text, sticker, overlay) and then follows the finger, **without any SwiftUI gesture on the
/// clips**: a SwiftUI `LongPressGesture` on a view inside the lanes' `ScrollView` made it refuse every swipe that began on that clip
/// (measured on the simulator: 6 of 20 swipes did nothing, 0 of 30 without it; the timeline's own logs showed the touch reaching the
/// app and no clip ever lifting). A UIKit long-press recognizer is allowed to run *alongside* the scroll view's pan, and it fails by
/// itself as soon as the finger moves, so scrolling is never held up.
///
/// The recognizer lives on the screen's root view (it sees every touch, so nothing has to sit over the clips); `hit` says whether
/// the touch began on a free clip, and the recognizer only begins when it did. Points are in this view's own space, which is the
/// timeline panel's (`timelinePanelSpace`).
/// What a press began on: a free clip of the picture lanes, or a standalone audio clip (with its track).
enum PressedClip {
    case layer(V2Layer)
    case audio(clip: V2AudioClip, trackId: String)
}

struct ClipPressDetector: UIViewRepresentable {
    /// The free clip (picture lane or audio) under a point (panel space), if any.
    let hit: (CGPoint) -> PressedClip?
    /// The press has been held long enough: lift this clip; the point is where the finger went down (panel space).
    let onLift: (PressedClip, CGPoint) -> Void
    /// The finger's travel since it went down.
    let onDrag: (CGSize) -> Void
    /// The finger lifted (or the touch was cancelled).
    let onEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> DetectorView {
        let view = DetectorView()
        view.isUserInteractionEnabled = false
        view.attach = { [weak coordinator = context.coordinator] root in coordinator?.attach(to: root, from: view) }
        return view
    }

    func updateUIView(_ uiView: DetectorView, context: Context) {
        context.coordinator.parent = self
    }

    final class DetectorView: UIView {
        var attach: ((UIView?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { attach?(nil); return }
            // The root-most view under the window: it contains every touch of this screen.
            var root: UIView = self
            while let parent = root.superview, !(parent is UIWindow) { root = parent }
            attach?(root)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: ClipPressDetector
        private let recognizer = UILongPressGestureRecognizer()
        private weak var host: UIView?
        private weak var detector: UIView?
        private var start = CGPoint.zero
        private var pending: PressedClip?

        init(_ parent: ClipPressDetector) {
            self.parent = parent
            super.init()
            recognizer.minimumPressDuration = 0.3
            recognizer.allowableMovement = 10
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delegate = self
            recognizer.addTarget(self, action: #selector(handle(_:)))
        }

        func attach(to root: UIView?, from detector: UIView) {
            self.detector = detector
            if host === root { return }
            host?.removeGestureRecognizer(recognizer)
            host = root
            root?.addGestureRecognizer(recognizer)
        }

        @objc private func handle(_ recognizer: UILongPressGestureRecognizer) {
            guard let detector else { return }
            let point = recognizer.location(in: detector)
            switch recognizer.state {
            case .began:
                start = point
                if let clip = pending { parent.onLift(clip, point) }
            case .changed:
                parent.onDrag(CGSize(width: point.x - start.x, height: point.y - start.y))
            case .ended, .cancelled, .failed:
                pending = nil
                parent.onEnd()
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let detector else { return false }
            let point = gestureRecognizer.location(in: detector)
            guard detector.bounds.contains(point) else { return false }
            pending = parent.hit(point)
            return pending != nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
