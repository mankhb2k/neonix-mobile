import SwiftUI

/// Design lab for the editor's Transform tool, in the layout chosen so far: round buttons for X, Y, Scale, Rotate and
/// Opacity; tapping one opens a Curves-style sheet with the ruler and the same buttons inside. Laid out in a mock of
/// the editor (stage, timeline, tool area, toolbar) so the space it costs is real.
struct TransformLabView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var transform = LabTransform()
    @State private var param: LabParam = .rotation
    @State private var popupOpen = false
    @State private var stageGestures = true
    @State private var haptics = true
    @State private var sheetHeight: LabSheetHeight = .standard

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Text("Tap a button: a sheet opens with the ruler and the buttons inside")
                .font(.caption).foregroundColor(.secondary)

            LabStage(transform: $transform, gesturesEnabled: stageGestures)
                .padding(.horizontal, 40).padding(.vertical, 8)
                .frame(maxHeight: .infinity)

            timeRow
            mockTimeline
            controls
            mockToolbar
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .sheet(isPresented: $popupOpen) { transformSheet }
    }

    // MARK: Top

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.title3).frame(width: 44, height: 44) }
                .accessibilityIdentifier("labClose")
            Spacer()
            Text("Transform lab").font(.headline)
            Spacer()
            Menu {
                Toggle("Gestures on stage", isOn: $stageGestures)
                Toggle("Haptics on ruler", isOn: $haptics)
                Picker("Sheet height", selection: $sheetHeight) { ForEach(LabSheetHeight.allCases) { Text($0.rawValue).tag($0) } }
                Button("Reset transform", role: .destructive) { transform = LabTransform() }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("labMenu")
        }
        .padding(.horizontal, 8)
    }

    // MARK: Mock editor chrome

    private var timeRow: some View {
        HStack {
            Text("00:03").font(.body.monospacedDigit().weight(.semibold))
                + Text("  ·  00:12").font(.body.monospacedDigit()).foregroundColor(.secondary)
            Spacer()
            Image(systemName: "play.fill").font(.title3)
            Spacer()
            Image(systemName: "arrow.uturn.backward").foregroundColor(.secondary)
            Image(systemName: "arrow.uturn.forward").foregroundColor(.secondary).padding(.leading, 12)
        }
        .padding(.horizontal, 20).padding(.vertical, 6)
    }

    private var mockTimeline: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 6).fill(Color.green.opacity(0.8)).overlay(Text("Image").font(.caption2).foregroundColor(.white))
            RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.85)).overlay(Text("Text").font(.caption2).foregroundColor(.white))
        }
        .frame(height: 70)
        .padding(.horizontal, 16)
    }

    private var mockToolbar: some View {
        HStack {
            ForEach([("scissors", "Edit"), ("music.note", "Audio"), ("textformat", "Text"), ("wand.and.stars", "Effects"),
                     ("camera.filters", "Filter"), ("arrow.up.left.and.arrow.down.right", "Transform")], id: \.1) { symbol, title in
                VStack(spacing: 3) {
                    Image(systemName: symbol).font(.title3)
                    Text(title).font(.caption2)
                }
                .foregroundColor(title == "Transform" ? .accentColor : .primary)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: Controls (what is being compared)

    private var controls: some View {
        chipsRow(idPrefix: "chip") { item in
            param = item
            popupOpen = true
        }
        .padding(.vertical, 10)
    }

    /// Like the Curves popup: a system sheet over the lower part of the screen (it covers the tools and the timeline),
    /// title + Done in its bar, the ruler on top and the round buttons that switch the parameter inside it. The stage
    /// above stays live, so the layer can still be dragged, pinched and twisted while the sheet is open.
    private var transformSheet: some View {
        NavigationStack {
            VStack(spacing: 14) {
                RulerDial(value: binding(param), mapping: param.mapping, detents: param.detents, neutral: param.neutral, haptics: haptics, format: param.format)
                    .id(param)
                    .padding(.bottom, 18)   // 14 (stack spacing) + 18 = 32 pt between the ruler and the round buttons
                chipsRow(idPrefix: "sheetChip") { param = $0 }
            }
            .padding(.top, 8)
            .navigationTitle(param.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { popupOpen = false }.accessibilityIdentifier("popupDone")
                }
            }
        }
        .presentationDetents(sheetHeight.detents())
        .presentationDragIndicator(sheetHeight.showsGrabber ? .visible : .hidden)
        .presentationBackgroundInteraction(.enabled)
    }

    /// The round buttons that pick the parameter. The closed screen and the sheet use the same row; `idPrefix` keeps their
    /// accessibility ids apart when both are on screen.
    private func chipsRow(idPrefix: String, onTap: @escaping (LabParam) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(LabParam.allCases) { item in chip(item, idPrefix: idPrefix, onTap: onTap) }
                resetChip(idPrefix: idPrefix)
            }
            .padding(.horizontal, 16)
        }
    }

    private var chips: some View {
        chipsRow(idPrefix: "chip") { param = $0 }
    }

    private func chip(_ item: LabParam, idPrefix: String, onTap: @escaping (LabParam) -> Void) -> some View {
        let selected = param == item
        let changed = item.get(transform) != item.neutral
        return Button {
            onTap(item)
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(selected ? Color.accentColor : Color(.secondarySystemBackground))
                    .frame(width: 48, height: 48)
                    .overlay(Image(systemName: item.symbol).font(.system(size: 18, weight: .medium)).foregroundColor(selected ? .white : .primary))
                Text(item.format(item.get(transform)))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(changed ? .accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
        // Double tap puts just this parameter back to neutral.
        .simultaneousGesture(TapGesture(count: 2).onEnded { var t = transform; item.set(&t, item.neutral); transform = t })
        .accessibilityIdentifier("\(idPrefix)-\(item.rawValue)")
        .accessibilityLabel(item.title)
        .accessibilityValue(item.format(item.get(transform)))
    }

    private func resetChip(idPrefix: String) -> some View {
        Button { transform = LabTransform() } label: {
            VStack(spacing: 4) {
                Circle().fill(Color(.secondarySystemBackground)).frame(width: 48, height: 48)
                    .overlay(Image(systemName: "arrow.counterclockwise").font(.system(size: 18, weight: .medium)))
                Text("Reset").font(.caption2).foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(idPrefix)-reset")
    }

    private func binding(_ p: LabParam) -> Binding<Double> {
        Binding(get: { p.get(transform) }, set: { value in var t = transform; p.set(&t, value); transform = t })
    }
}
