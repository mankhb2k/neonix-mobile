import SwiftUI

#if DEBUG
import UIKit

/// How tall is the software keyboard and where does the Text sheet's strip end above it? Records, on every keyboard show, the
/// keyboard frame, the screen and safe area, the sheet's frame and the bottom of its tabs (`TextSheet`), into
/// `Documents/keyboard_bench.txt` (pull with `devicectl ... copy from`). Always on in Debug, costs nothing at rest.
@MainActor
enum KeyboardBench {
    static var sheetFrame = CGRect.zero
    static var tabsBottom: CGFloat = 0
    /// Which layout is being measured ("sheet", "docked-260", ...), written into every trace line.
    static var tag = "sheet"
    /// A view at the top of the panel's head: `HeadProbe` fills it, the tracer reads its on-screen y every frame.
    static weak var headView: UIView?
    private static var observers: [NSObjectProtocol] = []
    private static var tracer: FrameTracer?

    static func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers += [UIResponder.keyboardDidShowNotification, UIResponder.keyboardDidHideNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { note in
                let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
                let kind = name == UIResponder.keyboardDidShowNotification ? "show" : "hide"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { MainActor.assumeIsolated { record(kind, keyboard: frame) } }
            }
        }
    }

    /// Samples `headView`'s presentation-layer y (every animation in flight included) for 1.2 s and appends one line.
    @MainActor private final class FrameTracer: NSObject {
        let label: String
        let start = CACurrentMediaTime()
        var samples: [String] = []
        var link: CADisplayLink?
        init(label: String) {
            self.label = label
            super.init()
            link = CADisplayLink(target: self, selector: #selector(tick))
            link?.add(to: .main, forMode: .common)
            tick()
        }
        @objc nonisolated func tick() { MainActor.assumeIsolated { sample() } }
        func sample() {
            let t = CACurrentMediaTime() - start
            if let y = KeyboardBench.screenY(of: KeyboardBench.headView) {
                samples.append(String(format: "%.0f:%.0f", t * 1000, y))
            }
            if t > 1.2 { finish() }
        }
        func finish() {
            link?.invalidate(); link = nil
            KeyboardBench.append("TRACE \(label) ms:headTopY " + samples.joined(separator: " ") + "\n")
        }
    }

    /// The view's top edge in window coordinates, from its presentation layer (so a sheet's slide and any animation in flight count).
    static func screenY(of view: UIView?) -> CGFloat? {
        guard let v = view, let window = v.window else { return nil }
        return v.layer.presentation()?.convert(CGPoint.zero, to: window.layer).y
    }

    /// Starts a trace now (call when the field's focus flips): keyboard notifications don't exist without a software keyboard.
    static func trace(_ kind: String) {
        tracer = FrameTracer(label: "\(tag) \(kind)")
    }

    static func append(_ line: String) {
        NSLog("KBBENCH %@", line)
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("keyboard_bench.txt")
        if let handle = try? FileHandle(forWritingTo: url) { handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close() }
        else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    }

    private static func record(_ kind: String, keyboard: CGRect) {
        var system = utsname(); uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        let screen = window?.bounds ?? .zero
        append(String(format: "%@ %@ screen %.0fx%.0f safeBottom %.0f | keyboard %@ h=%.1f | sheet y=%.1f h=%.1f maxY=%.1f | tabsBottom %.1f | blank(kbTop-tabsBottom) %.1f\n",
                      model, kind, screen.width, screen.height, window?.safeAreaInsets.bottom ?? 0,
                      NSCoder.string(for: keyboard), keyboard.height, sheetFrame.minY, sheetFrame.height, sheetFrame.maxY, tabsBottom,
                      keyboard.minY - tabsBottom))
    }
}

/// Place as a `.background` at the top of the head: tells `KeyboardBench` which view to trace.
struct HeadProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { let v = UIView(); v.isUserInteractionEnabled = false; return v }
    func updateUIView(_ view: UIView, context: Context) { KeyboardBench.headView = view }
}

extension View {
    /// Reports this view's global frame to `KeyboardBench` (`tabsBottom` = its maxY, else the sheet frame).
    func keyboardProbe(tabsBottom: Bool) -> some View {
        background(GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            Color.clear.onChange(of: frame, initial: true) { _, f in
                if tabsBottom { KeyboardBench.tabsBottom = f.maxY } else { KeyboardBench.sheetFrame = f }
            }
        })
    }
}
#else
struct HeadProbe: View { var body: some View { EmptyView() } }
extension View { func keyboardProbe(tabsBottom: Bool) -> some View { self } }
#endif
