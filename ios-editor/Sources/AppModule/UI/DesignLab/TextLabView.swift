import SwiftUI

/// Design lab for the Text tool's picker. Two tabs only (user 2026-10-13): **Font** (a grid of fonts, each name drawn in its own
/// font) and **Style** (CapCut-like presets, a colour row, Size). The question the lab answers is where the text field goes: on top
/// of the sheet like CapCut (A), or at the bottom like the Filter sheet's Intensity bar (B). A live photo with the text on it, fake
/// styling, real iOS fonts. The text field only shows a keyboard on a device or a simulator with the software keyboard on.
struct TextLabView: View {
    @Environment(\.dismiss) private var dismiss

    enum Variant: String, CaseIterable, Identifiable {
        case top = "A Field on top", bottom = "B Field at bottom"
        var id: String { rawValue }
        var summary: String {
            switch self {
            case .top: return "CapCut: the text field heads the sheet, the tabs and their grid below it"
            case .bottom: return "Like Filter's Intensity bar: tabs and grid first, the text field pinned at the bottom"
            }
        }
    }

    enum Tab: String, CaseIterable, Identifiable { case font = "Font", style = "Style"; var id: String { rawValue } }

    @State private var variant: Variant = .top
    @State private var tab: Tab = .font
    @State private var text = ""   // empty: the field shows its placeholder, so typing starts from nothing
    @State private var fontName = "HelveticaNeue-Bold"
    @State private var preset: LabTextPreset = .plain
    @State private var size = 0.5
    @State private var sheetOpen = false
    @State private var photo: UIImage?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Picker("Layout", selection: $variant) { ForEach(Variant.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).padding(.horizontal)
                .accessibilityIdentifier("textVariantPicker")
            Text(variant.summary).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal).padding(.top, 4)
            stage.padding(.horizontal, 44).padding(.vertical, 8).frame(maxHeight: .infinity)
            mockSelectionRow
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .task { photo = await AdjustLabView.loadPhoto() }
        .onChange(of: variant) { _, _ in sheetOpen = false }
        .sheet(isPresented: $sheetOpen) { textSheet }
    }

    // MARK: Stage

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.title3).frame(width: 44, height: 44) }
                .accessibilityIdentifier("textLabClose")
            Spacer()
            Text("Text lab").font(.headline)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 8)
    }

    private var stage: some View {
        Color(.tertiarySystemBackground)
            .overlay {
                if let photo { Image(uiImage: photo).resizable().scaledToFill() } else { ProgressView() }
            }
            .overlay(GeometryReader { proxy in
                LabStyledText(text: text.isEmpty ? "Enter text" : text, fontName: fontName, points: 20 + size * 44, preset: preset)
                    .opacity(text.isEmpty ? 0.55 : 1)   // a preview until something is typed
                    .frame(maxWidth: proxy.size.width * 0.9)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.36)   // above the sheet, which covers the lower half
            })
            .clipped()
            .aspectRatio(9.0 / 16.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityIdentifier("textStage")
    }

    private var mockSelectionRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left.2").font(.body.weight(.semibold)).frame(width: 44, height: 44)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Divider().frame(height: 28)
            ForEach([("pencil", "Edit text"), ("scissors", "Split"), ("trash", "Delete")], id: \.1) { symbol, title in
                Button { if title == "Edit text" { sheetOpen = true } } label: {
                    VStack(spacing: 4) {
                        Image(systemName: symbol).font(.title3)
                        Text(title).font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(title == "Split" ? .secondary : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("textAction-\(title)")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: Sheet

    private var textSheet: some View {
        VStack(spacing: 0) {
            if variant == .top { field.padding(.top, 14); Divider().opacity(0).padding(.bottom, 4) }
            tabBar.padding(.top, variant == .top ? 0 : 14)
            Divider()
            Group {
                switch tab {
                case .font: fontGrid
                case .style: stylePanel
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            if variant == .bottom { Divider(); field.padding(.vertical, 8) }
        }
        .presentationDetents([.height(variant == .top ? 400 : 360), .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .height(400)))
    }

    private var field: some View {
        HStack(spacing: 10) {
            TextField("Enter text", text: $text)
                .focused($fieldFocused)
                .padding(.horizontal, 14).frame(height: 44)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("textField")
            Button { fieldFocused = false; sheetOpen = false } label: {
                Image(systemName: "checkmark").font(.title3.weight(.semibold)).frame(width: 40, height: 44)
            }
            .accessibilityIdentifier("textDone")
        }
        .padding(.horizontal, 16)
    }

    private var tabBar: some View {
        HStack(spacing: 28) {
            ForEach(Tab.allCases) { item in
                Button { tab = item } label: {
                    VStack(spacing: 6) {
                        Text(item.rawValue).font(.subheadline.weight(tab == item ? .semibold : .regular))
                            .foregroundColor(tab == item ? .primary : .secondary)
                        Capsule().fill(tab == item ? Color.accentColor : .clear).frame(width: 28, height: 3)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("textTab-\(item.rawValue)")
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var fontGrid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(LabFont.available) { font in
                    let on = fontName == font.postScript
                    Button { fontName = font.postScript } label: {
                        Text(font.title).font(.custom(font.postScript, size: 17)).lineLimit(1).minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2.5))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("fontCell-\(font.postScript)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .accessibilityIdentifier("fontGrid")
    }

    private var stylePanel: some View {
        VStack(spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LabTextPreset.all) { item in
                        let on = preset == item
                        Button { preset = item } label: {
                            Text("Aa").font(.system(size: 22, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                                .foregroundColor(item.fill)
                                .frame(width: 52, height: 44)
                                .background(item.background ?? Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("stylePreset-\(item.id)")
                    }
                }
                .padding(.horizontal, 16)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(LabTextPreset.swatches, id: \.self) { color in
                        Button { preset.fill = color } label: {
                            Circle().fill(color).frame(width: 34, height: 34)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                                .overlay(Circle().strokeBorder(preset.fill == color ? Color.accentColor : .clear, lineWidth: 3).padding(-4))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 4)
            }
            HStack(spacing: 12) {
                Text("Size").font(.subheadline).foregroundColor(.secondary)
                Slider(value: $size, in: 0...1).accessibilityIdentifier("textSize")
                Text("\(Int((20 + size * 44).rounded()))").font(.subheadline.monospacedDigit()).frame(width: 30, alignment: .trailing)
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 14)
    }
}

// MARK: - Fake model

/// A look: fill colour, optional stroke and optional background box (CapCut's "Aa" presets, trimmed).
struct LabTextPreset: Identifiable, Equatable {
    let id: String
    var fill: Color
    var stroke: Color?
    var background: Color?

    static let plain = LabTextPreset(id: "plain", fill: .white, stroke: nil, background: nil)
    static let all: [LabTextPreset] = [
        plain,
        LabTextPreset(id: "red-outline", fill: .red, stroke: .white, background: nil),
        LabTextPreset(id: "orange-outline", fill: .orange, stroke: .white, background: nil),
        LabTextPreset(id: "blue-outline", fill: .blue, stroke: .white, background: nil),
        LabTextPreset(id: "green-black", fill: .green, stroke: .black, background: nil),
        LabTextPreset(id: "black-on-white", fill: .black, stroke: nil, background: .white),
        LabTextPreset(id: "black-on-yellow", fill: .black, stroke: nil, background: .yellow),
        LabTextPreset(id: "white-on-purple", fill: .white, stroke: nil, background: .purple),
    ]
    static let swatches: [Color] = [.white, Color(white: 0.75), Color(white: 0.5), Color(white: 0.25), .black, .yellow, .orange, .red, .pink, .purple, .blue, .green]
}

/// The lab uses the production font list.
typealias LabFont = EditorFont

/// The styled text on the stage: stroke by stacking offset copies, a background box, the fill on top.
struct LabStyledText: View {
    let text: String
    let fontName: String
    let points: Double
    let preset: LabTextPreset

    var body: some View {
        let font = Font.custom(fontName, size: points)
        let offsets: [CGSize] = preset.stroke == nil ? [] : [(-1, -1), (1, -1), (-1, 1), (1, 1), (0, -1.5), (0, 1.5), (-1.5, 0), (1.5, 0)].map { CGSize(width: $0.0, height: $0.1) }
        ZStack {
            ForEach(offsets.indices, id: \.self) { i in
                Text(text).font(font).foregroundColor(preset.stroke).offset(offsets[i])
            }
            Text(text).font(font).foregroundColor(preset.fill)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, preset.background == nil ? 0 : 12).padding(.vertical, preset.background == nil ? 0 : 6)
        .background(preset.background.map { AnyShapeStyle($0) } ?? AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("textStageText")
    }
}
