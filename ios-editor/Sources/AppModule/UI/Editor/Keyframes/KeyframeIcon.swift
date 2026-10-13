import SwiftUI

/// The keyframe button's icon (CapCut's): a diamond with a small "+" when pressing it adds a keyframe at the playhead, a filled
/// diamond with a "-" when there already is one and pressing it removes it. SF Symbols has no such pair, so it is composed
/// from the `diamond` symbols and a bold `plus` / `minus` (tints, scales and follows Dynamic Type like any symbol).
struct KeyframeIcon: View {
    let hasKeyframeHere: Bool

    var body: some View {
        ZStack {
            Image(systemName: hasKeyframeHere ? "diamond.fill" : "diamond")
                .font(.headline.weight(.regular))
                .foregroundColor(hasKeyframeHere ? .accentColor : .primary)
            Image(systemName: hasKeyframeHere ? "minus" : "plus")
                .font(.system(size: 9, weight: .heavy))
                .foregroundColor(hasKeyframeHere ? .accentColor : .primary)
                .padding(1.5)
                .background(Color(.systemBackground), in: Circle())
                .offset(x: -11, y: -9)
        }
        .frame(width: 30, height: 26)
        .accessibilityLabel(hasKeyframeHere ? "Remove keyframe" : "Add keyframe")
    }
}
