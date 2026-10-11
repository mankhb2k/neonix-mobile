import SwiftUI

/// Sandbox for trying UI before it goes into the editor: each experiment is a self-contained screen with fake
/// data, so layouts and navigation styles can be compared side by side without touching real code paths.
struct DesignLabView: View {
    @State private var showingTransform = false
    @State private var showingAdjust = false

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
            } header: {
                Text("Experiments")
            } footer: {
                Text("Fake data only. Nothing here touches projects or the server.")
            }
        }
        .navigationTitle("Design Lab")
        .fullScreenCover(isPresented: $showingTransform) { TransformLabView() }
        .fullScreenCover(isPresented: $showingAdjust) { AdjustLabView() }
    }
}
