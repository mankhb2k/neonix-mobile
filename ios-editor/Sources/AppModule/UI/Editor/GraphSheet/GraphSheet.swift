import SwiftUI

/// Picks the graph (easing) of the segment between two keyframes: CapCut's one row of curve tiles + Edit tile (variant A
/// of the Keyframe lab; the style is not final). The graph types are the lab's `LabEasing` until the keyframe model exists.
struct GraphSheet: View {
    let easing: LabEasing
    let onChange: (LabEasing) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editing = false

    var body: some View {
        NavigationStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    tile(.original)
                    ForEach(LabEasing.catalogue) { tile($0) }
                    editTile
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
            .accessibilityIdentifier("graphRow")
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle("Graph")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { onChange(.original) }
                        .disabled(easing == .original).accessibilityIdentifier("graphReset")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("graphDone")
                }
            }
        }
        .presentationDetents([.height(250)])
        .presentationBackgroundInteraction(.enabled)
        .fullScreenCover(isPresented: $editing) {
            GraphEditorView(bezier: easing.bezier) { onChange(.custom($0)) }
        }
    }

    private func tile(_ item: LabEasing) -> some View {
        let on = easing.id == item.id
        return Button { onChange(item) } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.tertiarySystemBackground))
                    if item == .original {
                        Image(systemName: "nosign").font(.title2).foregroundColor(.secondary)
                    } else {
                        LabCurveShape(bezier: item.bezier).stroke(on ? Color.accentColor : Color.primary, lineWidth: 2).padding(10)
                    }
                }
                .frame(width: 64, height: 64)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2.5))
                Text(item.name).font(.caption2).foregroundColor(on ? .accentColor : .secondary).lineLimit(1)
            }
            .frame(width: 72)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("graphTile-\(item.id)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var editTile: some View {
        Button { editing = true } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor)
                    Image(systemName: "pencil").font(.title2).foregroundColor(.white)
                }
                .frame(width: 64, height: 64)
                Text("Edit").font(.caption2).foregroundColor(.accentColor)
            }
            .frame(width: 72)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("graphEdit")
    }
}

/// The sheet's curves are the lab's `LabEasing` until the picker style is final; the project stores `V2Easing`.
extension LabEasing {
    /// "Original" = no easing on the keyframe; anything but a cubic-bezier / linear is treated as Original.
    init(v2: V2Easing?) {
        switch v2 {
        case .some(.linear): self = .linear
        case .some(.cubicBezier(let x1, let y1, let x2, let y2)):
            let bezier = LabBezier(x1: x1, y1: y1, x2: x2, y2: y2)
            self = LabEasing.catalogue.first { $0.bezier == bezier && $0 != .linear } ?? .custom(bezier)
        default: self = .original
        }
    }

    var v2: V2Easing? {
        if self == .original { return nil }
        if self == .linear { return .linear }
        return .cubicBezier(x1: bezier.x1, y1: bezier.y1, x2: bezier.x2, y2: bezier.y2)
    }
}
