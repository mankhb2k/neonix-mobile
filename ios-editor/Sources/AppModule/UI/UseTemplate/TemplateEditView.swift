import SwiftUI

/// What the user sees after filling the slots (replaces the full editor in the template flow): the template playing
/// with their media, their slots, and three tabs - Media (replace/crop a clip), Audio (music on/off) and Text (the
/// template's texts) - plus Export.
struct TemplateEditView: View {
    let template: APITemplate
    let versionId: String?
    let onBack: () -> Void

    @State private var model: TemplateEditModel
    @State private var engine: EditorPlaybackEngine
    @State private var exportGate = ExportGate()
    @State private var library = PhotoLibrary()
    @State private var tab: Tab = .media
    @State private var selectedSlot: String?
    @State private var replacing: TemplateManifest.Slot?
    @State private var cropping: String?
    @State private var editingText: TemplateManifest.Slot?

    enum Tab: String, CaseIterable {
        case media = "Media", audio = "Audio", text = "Text"
        var symbol: String {
            switch self {
            case .media: return "film.stack"
            case .audio: return "music.note"
            case .text: return "textformat"
            }
        }
    }

    init(template: APITemplate, versionId: String?, model: TemplateEditModel, onBack: @escaping () -> Void) {
        self.template = template
        self.versionId = versionId
        self.onBack = onBack
        _model = State(initialValue: model)
        _engine = State(initialValue: EditorPlaybackEngine(project: model.project))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            stage
            timeRow
            panel
            tabBar
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .overlay {
            if exportGate.showsProgress {
                ExportProgressOverlay(progress: exportGate.progress, title: exportGate.progressTitle,
                                      isComplete: exportGate.completed)
            }
        }
        .task { engine.prepare() }
        .onChange(of: model.revision) { _, _ in engine.update(project: model.project) }
        .onDisappear { engine.pause() }
        .alert(item: $exportGate.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
        .alert("Couldn't update", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
        .fullScreenCover(item: $replacing) { slot in
            SingleSlotPickerView(slot: slot, onPick: { pick in
                replacing = nil
                Task { await model.replace(slot: slot.id, with: pick) }
            }, onCancel: { replacing = nil })
        }
        .fullScreenCover(item: Binding(get: { cropping.map(CropTarget.init) }, set: { cropping = $0?.id })) { target in
            if let entry = model.entries.first(where: { $0.id == target.id }), let pick = entry.pick {
                SlotCropView(library: library, media: pick, slotMs: entry.durationMs) { start in
                    model.setCrop(slot: target.id, startMs: start)
                    cropping = nil
                } onCancel: { cropping = nil }
            }
        }
        .sheet(item: $editingText) { slot in
            TextSlotSheet(label: slot.label, text: model.text(for: slot)) { model.setText(slot: slot.id, $0) }
                .presentationDetents([.height(220)])
        }
    }

    private struct CropTarget: Identifiable { let id: String }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("backButton")
            Spacer()
            Button { tab = .audio } label: {
                Label(model.musicOn ? model.musicTitle : "No music", systemImage: "music.note")
                    .font(.subheadline.weight(.medium)).lineLimit(1)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color(.secondarySystemBackground), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("musicChip")
            Spacer()
            Button(action: startExport) {
                Group {
                    if exportGate.isWorking { ProgressView().frame(minWidth: 44) } else { Text("Export") }
                }
                .fontWeight(.semibold)
                .padding(.horizontal, 12).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(exportGate.isWorking || model.isImporting)
            .accessibilityIdentifier("exportButton")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func startExport() {
        engine.pause()
        let context = TemplateExportContext(templateId: template.id, versionId: versionId, creditCost: template.creditCost)
        Task {
            await exportGate.export(project: model.project, context: context)
        }
    }

    // MARK: Stage + time

    private var stage: some View {
        let composition = model.project.composition
        return StagePreview(
            composition: composition, assets: model.project.assets, layers: model.project.layers,
            filters: model.project.filters ?? [], engine: engine
        )
        .aspectRatio(CGFloat(composition.width / composition.height), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 36)
        .padding(.vertical, 6)
        .frame(maxHeight: .infinity)
        .overlay { if model.isImporting { ProgressView().controlSize(.large) } }
    }

    private var timeRow: some View {
        ZStack {
            HStack {
                Text(clock(engine.currentTimeMs / 1000)).font(.body.monospacedDigit().weight(.semibold))
                + Text("  ·  \(clock(engine.maxDurationMs / 1000))").font(.body.monospacedDigit()).foregroundColor(.secondary)
                Spacer()
            }
            Button { engine.togglePlay() } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill").font(.title2).frame(width: 52, height: 40)
            }
            .accessibilityIdentifier("playButton")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    // MARK: Panels

    @ViewBuilder private var panel: some View {
        Group {
            switch tab {
            case .media: mediaPanel
            case .audio: audioPanel
            case .text: textPanel
            }
        }
        .frame(height: 170)
        .frame(maxWidth: .infinity)
    }

    private var mediaPanel: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(model.entries.enumerated()), id: \.element.id) { index, entry in
                        SlotThumb(library: library, index: index, entry: entry,
                                  isActive: selectedSlot == entry.id || (selectedSlot == nil && model.entry(at: engine.currentTimeMs)?.id == entry.id))
                            .onTapGesture {
                                selectedSlot = entry.id
                                engine.scrub(toMs: entry.startMs + 1)
                            }
                    }
                }
                .padding(.horizontal, 16)
            }
            if let id = selectedSlot, let entry = model.entries.first(where: { $0.id == id }) {
                HStack(spacing: 12) {
                    Button { replacing = entry.slot } label: { Label("Replace", systemImage: "arrow.triangle.2.circlepath") }
                        .accessibilityIdentifier("replaceSlot")
                    if let pick = entry.pick, SlotRules.needsCrop(pick.kind, durationMs: pick.durationMs, slotMs: entry.durationMs) {
                        Button { cropping = entry.id } label: { Label("Crop", systemImage: "crop") }
                            .accessibilityIdentifier("cropSlot")
                    }
                }
                .buttonStyle(.bordered)
            } else {
                Text("Tap a clip to replace or crop it").font(.footnote).foregroundColor(.secondary)
            }
        }
    }

    private var audioPanel: some View {
        VStack(spacing: 10) {
            musicRow(title: model.musicTitle, subtitle: "From the template", isOn: true)
            musicRow(title: "No music", subtitle: nil, isOn: false)
        }
        .padding(.horizontal, 16)
    }

    private func musicRow(title: String, subtitle: String?, isOn: Bool) -> some View {
        Button { model.musicOn = isOn } label: {
            HStack {
                Image(systemName: isOn ? "music.note" : "speaker.slash").frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium))
                    if let subtitle { Text(subtitle).font(.caption).foregroundColor(.secondary) }
                }
                Spacer()
                if model.musicOn == isOn { Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor) }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(isOn ? "musicOriginal" : "musicNone")
    }

    private var textPanel: some View {
        ScrollView {
            VStack(spacing: 10) {
                if model.textSlots.isEmpty {
                    Text("This template has no text to edit").font(.footnote).foregroundColor(.secondary).padding(.top, 20)
                }
                ForEach(model.textSlots, id: \.id) { slot in
                    Button { editingText = slot } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(slot.label).font(.caption).foregroundColor(.secondary)
                                Text(model.text(for: slot)).font(.body.weight(.medium)).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "pencil").foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("textSlot-\(slot.id)")
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var tabBar: some View {
        HStack {
            ForEach(Tab.allCases, id: \.self) { item in
                Button { tab = item } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol).font(.title3)
                        Text(item.rawValue).font(.caption2)
                        Capsule().fill(tab == item ? Color.accentColor : .clear).frame(width: 22, height: 3)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(tab == item ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tab-\(item.rawValue)")
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}

private struct SlotThumb: View {
    let library: PhotoLibrary
    let index: Int
    let entry: TemplateEditModel.SlotEntry
    let isActive: Bool

    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.tertiarySystemBackground))
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            Text("\(index + 1)").font(.caption2.weight(.bold)).foregroundColor(.white).padding(5).shadow(radius: 2)
            Text(String(format: "%.1fs", Double(entry.durationMs) / 1000))
                .font(.caption.weight(.semibold)).foregroundColor(.white).shadow(radius: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(.bottom, 6)
        }
        .frame(width: 80, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(isActive ? Color.primary : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Slot \(index + 1)")
        .accessibilityIdentifier("resultSlot-\(index)")
        .accessibilityAddTraits(.isButton)
        .task(id: entry.pick?.asset.localIdentifier) {
            if let asset = entry.pick?.asset { image = await library.thumbnail(for: asset, side: 200) } else { image = nil }
        }
    }
}

private struct TextSlotSheet: View {
    let label: String
    @State var text: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    init(label: String, text: String, onSave: @escaping (String) -> Void) {
        self.label = label
        self._text = State(initialValue: text)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Text(label).font(.headline)
                Spacer()
                Button("Done") { onSave(text); dismiss() }.fontWeight(.semibold).accessibilityIdentifier("textDone")
            }
            TextField("Text", text: $text)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("textField")
            Spacer()
        }
        .padding()
    }
}

extension TemplateManifest.Slot: Identifiable {}

