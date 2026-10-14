import SwiftUI

/// Sandbox for trying UI before it goes into the editor: each experiment is a self-contained screen with fake
/// data, so layouts and navigation styles can be compared side by side without touching real code paths.
struct DesignLabView: View {
    @State private var showingTransform = false
    @State private var showingAdjust = false
    @State private var showingFilter = false
    @State private var showingKeyframe = false
    @State private var showingText = false

    var body: some View {
        List {
            Section {
                Button { showingTransform = true } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Transform controls").font(.body.weight(.semibold)).foregroundColor(.primary)
                        Text("Round buttons; tapping one opens a Curves-style sheet with the ruler and the buttons inside. Drag, pinch and twist the layer too.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
                .accessibilityIdentifier("lab-transform")

                Button { showingAdjust = true } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Adjust controls").font(.body.weight(.semibold)).foregroundColor(.primary)
                        Text("13 controls on a live photo: a scrolling row vs Light / Color / Detail groups, both in the sheet. Hold the photo to compare.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
                .accessibilityIdentifier("lab-adjust")

                Button { showingFilter = true } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Filter picker").font(.body.weight(.semibold)).foregroundColor(.primary)
                        Text("16 fake filters on a live photo with an Intensity ruler: a 4-column grid in a fixed sheet, the same with a pull-up detent, or one row of thumbnails.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
                .accessibilityIdentifier("lab-filter")

                Button { showingKeyframe = true } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Keyframes & graphs").font(.body.weight(.semibold)).foregroundColor(.primary)
                        Text("Three keyframes on a moving layer; pick each segment's graph from a row of curves, a grid sheet or a big live curve, or edit it with two handles.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
                .accessibilityIdentifier("lab-keyframe")

                Button { showingText = true } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Text picker").font(.body.weight(.semibold)).foregroundColor(.primary)
                        Text("Two tabs, Font and Style, on a live photo; the text field heads the sheet (CapCut) or sits at the bottom like Filter's Intensity bar.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
                .accessibilityIdentifier("lab-text")
            } header: {
                Text("Experiments")
            } footer: {
                Text("Fake data only. Nothing here touches projects or the server.")
            }
        }
        .navigationTitle("Design Lab")
        .fullScreenCover(isPresented: $showingTransform) { TransformLabView() }
        .fullScreenCover(isPresented: $showingAdjust) { AdjustLabView() }
        .fullScreenCover(isPresented: $showingFilter) { FilterLabView() }
        .fullScreenCover(isPresented: $showingKeyframe) { KeyframeLabView() }
        .fullScreenCover(isPresented: $showingText) { TextLabView() }
    }
}
