import SwiftUI

/// The Text tool's sheet, CapCut's way (user 2026-10-14): the text field heads the sheet, the Font and Style tabs under it, their
/// content below. While the field is being edited the content is hidden and the sheet shrinks to just the field and the tabs, so the
/// system - which lifts a sheet by the keyboard's height - puts that small strip right above the keyboard and the stage stays visible.
/// Tapping a tab (or the check mark) ends the editing and brings the content back. Every change goes live to the clip through `values`;
/// the stage stays tappable at the small size (`presentationBackgroundInteraction`).
struct TextSheet: View {
    @Binding var values: TextStyleValues
    let composition: V2Composition
    /// A new clip's default words are selected the first time the field is tapped, so typing replaces them.
    var selectAllOnFirstFocus = false
    /// The tab the sheet opens on (the Style tool of a text clip opens it on Style).
    var initialTab: Tab = .font

    @Environment(\.dismiss) private var dismiss
    @State private var pendingSelectAll = false
    @State private var tab: Tab = .font
    @State var section: StyleSection = .text
    @State private var detent: PresentationDetent = Self.fullHeight
    @State private var headHeight: CGFloat = 90
    /// The custom colour screen, when open: it takes over the whole sheet (CapCut).
    @State var picker: ColorTarget?
    @State var recentColors = UserDefaults.standard.stringArray(forKey: "textRecentColors") ?? []
    @FocusState private var fieldFocused: Bool

    /// The sheet's two sizes: with the content, and just the field + tabs while typing.
    private static let fullHeight = PresentationDetent.height(320)
    /// The Background badge has four sliders under its tiles and colours, so its sheet is taller (user 2026-10-14; Shadow the same).
    private static let backgroundHeight = PresentationDetent.height(520)
    /// Shadow too: colours and four sliders, no style tiles, so a little lower than Background.
    private static let shadowHeight = PresentationDetent.height(460)

    /// The sheet's size at rest for what it shows now.
    private var restingHeight: PresentationDetent {
        guard tab == .style else { return Self.fullHeight }
        switch section {
        case .background: return Self.backgroundHeight
        case .shadow: return Self.shadowHeight
        default: return Self.fullHeight
        }
    }
    /// While typing the sheet is exactly its head (field + tabs): measured, so a longer field grows it and no blank shows
    /// above the keyboard (iPhone 13: keyboard 335 pt, head ~90 pt; a fixed 130 left 62 pt of blank - `KeyboardBench`).
    private var typingHeight: PresentationDetent { .height(headHeight) }

    enum Tab: String, CaseIterable, Identifiable { case font = "Font", style = "Style"; var id: String { rawValue } }

    /// The badges of the Style tab, in the user's order. `symbol`s are checked by `TextSheetTests`.
    enum StyleSection: String, CaseIterable, Identifiable {
        case text = "Text", colors = "Colors", stroke = "Stroke", glow = "Glow", background = "Background", shadow = "Shadow"
        case curve = "Curve", spacing = "Spacing", letterCase = "Case"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .text: "textformat.size"
            case .colors: "paintpalette"
            case .stroke: "pencil.and.outline"
            case .glow: "sparkles"
            case .background: "rectangle.inset.filled"
            case .shadow: "shadow"
            case .curve: "point.topleft.down.to.point.bottomright.curvepath"
            case .spacing: "arrow.left.and.right"
            case .letterCase: "bold"
            }
        }
    }

    /// What the custom colour screen is editing, and the colour to go back to on ✕.
    enum ColorTarget: Equatable { case text(from: String), background(from: String?), stroke(from: String?), glow(from: String?), shadow(from: String?) }

    var body: some View {
        VStack(spacing: 0) {
          if let target = picker {
            colorScreen(target)
          } else {
            VStack(spacing: 0) {
                field.padding(.top, 14).padding(.bottom, 4)
                tabBar
                Divider().keyboardProbe(tabsBottom: true)
            }
            .background(HeadProbe())
            .background(GeometryReader { proxy in
                Color.clear.onChange(of: proxy.size.height, initial: true) { _, h in
                    headHeight = h.rounded(.up) + 3   // the system gives ~2.5 pt less than asked (measured)
                    if fieldFocused { detent = .height(headHeight) }
                }
            })
            if !fieldFocused {
                Group {
                    switch tab {
                    case .font: fontGrid
                    case .style: stylePanel
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
            } else {
                Spacer(minLength: 0)
            }
          }
        }
        .keyboardProbe(tabsBottom: false)
        #if DEBUG
        .onAppear { KeyboardBench.tag = "sheet"; KeyboardBench.start() }
        #endif
        .presentationDetents(fieldFocused ? [typingHeight] : [restingHeight, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled)   // the stage stays live at every size, also while typing
        .animation(.easeOut(duration: 0.2), value: fieldFocused)
        .onChange(of: section) { _, _ in if !fieldFocused { detent = restingHeight } }
        .onChange(of: tab) { _, _ in if !fieldFocused { detent = restingHeight } }
        .onChange(of: fieldFocused) { _, focused in
            detent = focused ? typingHeight : restingHeight
            #if DEBUG
            KeyboardBench.trace(focused ? "focus" : "blur")
            #endif
        }
        .onAppear { pendingSelectAll = selectAllOnFirstFocus; tab = initialTab }
        // A multi-line field is a UITextView underneath (a one-line one is a UITextField): listen to both.
        .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidBeginEditingNotification)) { selectAllOnce($0.object) }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { selectAllOnce($0.object) }
    }

    private func selectAllOnce(_ object: Any?) {
        guard pendingSelectAll, let responder = object as? UIResponder, responder is UITextField || responder is UITextView else { return }
        pendingSelectAll = false
        DispatchQueue.main.async {   // after UIKit has placed the caret
            (responder as? UITextField)?.selectAll(nil)
            (responder as? UITextView)?.selectAll(nil)
        }
    }

    private var field: some View {
        HStack(spacing: 10) {
            TextField(TextStyleValues.placeholder, text: $values.text, axis: .vertical)
                .lineLimit(1...3)   // Return starts a new line; the check mark closes
                .focused($fieldFocused)
                .padding(.horizontal, 14).padding(.vertical, 11).frame(minHeight: 44)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))   // a capsule on one line
                .accessibilityIdentifier("textField")
            // While typing the button folds the keyboard (CapCut); otherwise the check mark closes the sheet.
            Button { if fieldFocused { fieldFocused = false } else { dismiss() } } label: {
                Image(systemName: fieldFocused ? "keyboard.chevron.compact.down" : "checkmark").font(.title3.weight(.semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 40, height: 44)
            }
            .accessibilityIdentifier(fieldFocused ? "textHideKeyboard" : "textDone")
        }
        .padding(.horizontal, 16)
    }

    private var tabBar: some View {
        HStack(spacing: 28) {
            ForEach(Tab.allCases) { item in
                Button { fieldFocused = false; tab = item } label: {
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
                ForEach(EditorFont.available) { font in
                    let on = values.fontFamily == font.postScript
                    Button { values.fontFamily = font.postScript } label: {
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

    /// Style tab = a scrolling row of badges (one per kind of styling) and, under it, that badge's own controls. Text, Colors and
    /// Background work; the rest show a placeholder until their tools and sliders are built (user 2026-10-14).
    private var stylePanel: some View {
        VStack(spacing: 0) {
            badgeRow
            ScrollView { styleSectionContent.padding(.horizontal, 16).padding(.vertical, 12) }
        }
    }

    /// CapCut's row of "Aa" tiles, the content of the Text badge: one tap sets a whole look (`TextPreset`).
    var presetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TextPreset.all) { preset in
                    let on = preset.matches(values)
                    // The tile stands for the stage: a label's colour, else a dark or light card so the words always read.
                    let card = preset.background.map { Color(hex: $0) } ?? (preset.textIsLight ? Color(white: 0.2) : Color(white: 0.9))
                    Button { preset.apply(to: &values) } label: {
                        Text("Aa").font(.system(size: 20, weight: .heavy)).foregroundColor(Color(hex: preset.color))
                            .frame(width: 52, height: 40)
                            .background(card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("textPreset-\(preset.id)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 2)
        }
        .accessibilityIdentifier("textPresets")
    }

    private var badgeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StyleSection.allCases) { item in
                    let on = section == item
                    Button { section = item } label: {
                        VStack(spacing: 5) {
                            Image(systemName: item.symbol).font(.system(size: 20, weight: .regular)).frame(height: 24)
                            Text(item.rawValue).font(.caption2.weight(on ? .semibold : .regular)).lineLimit(1)
                        }
                        .frame(width: 72, height: 56)
                        .background(on ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 1.5))
                        .foregroundColor(on ? .accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("styleBadge-\(item.rawValue)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .accessibilityIdentifier("styleBadges")
    }

    /// The custom colour screen for whatever colour is being edited. ✕ puts back the colour it opened with, ✓ keeps the new one (and
    /// remembers it first in the grid unless it is a palette colour).
    private func colorScreen(_ target: ColorTarget) -> some View {
        let start: String, apply: (String) -> Void, restore: () -> Void
        switch target {
        case .text(let from): start = from; apply = { values.color = $0 }; restore = { values.color = from }
        case .background(let from): start = from ?? "#FFFFFFff"; apply = { values.backgroundColor = $0 }; restore = { values.backgroundColor = from }
        case .stroke(let from): start = from ?? "#000000ff"; apply = { values.strokeColor = $0 }; restore = { values.strokeColor = from }
        case .glow(let from): start = from ?? "#FFD60Aff"; apply = { values.glowColor = $0 }; restore = { values.glowColor = from }
        case .shadow(let from): start = from ?? "#000000ff"; apply = { values.shadowColor = $0 }; restore = { values.shadowColor = from }
        }
        return ColorPickerPanel(initial: start, onChange: apply, onCancel: { restore(); picker = nil }, onDone: { hex in
            apply(hex)
            if !ColorPalette.colors.contains(hex) && !recentColors.contains(hex) {
                recentColors = Array(([hex] + recentColors).prefix(4))
                UserDefaults.standard.set(recentColors, forKey: "textRecentColors")
            }
            picker = nil
        })
    }
}
