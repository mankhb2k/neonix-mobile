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

    @Environment(\.dismiss) private var dismiss
    @State private var pendingSelectAll = false
    @State private var tab: Tab = .font
    @State private var detent: PresentationDetent = Self.fullHeight
    @FocusState private var fieldFocused: Bool

    /// The sheet's two sizes: with the content, and just the field + tabs while typing.
    private static let fullHeight = PresentationDetent.height(360)
    private static let typingHeight = PresentationDetent.height(130)

    enum Tab: String, CaseIterable, Identifiable { case font = "Font", style = "Style"; var id: String { rawValue } }

    static let swatches = ["#FFFFFFff", "#BFBFBFff", "#808080ff", "#404040ff", "#000000ff", "#FFD60Aff", "#FF9500ff", "#FF3B30ff", "#FF2D55ff", "#AF52DEff", "#007AFFff", "#34C759ff"]

    var body: some View {
        VStack(spacing: 0) {
            field.padding(.top, 14).padding(.bottom, 4)
            tabBar
            Divider()
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
        .presentationDetents(fieldFocused ? [Self.typingHeight] : [Self.fullHeight, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled)   // the stage stays live at every size, also while typing
        .animation(.easeOut(duration: 0.2), value: fieldFocused)
        .onChange(of: fieldFocused) { _, focused in detent = focused ? Self.typingHeight : Self.fullHeight }
        .onAppear { pendingSelectAll = selectAllOnFirstFocus }
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
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("textField")
            Button { fieldFocused = false; dismiss() } label: {
                Image(systemName: "checkmark").font(.title3.weight(.semibold)).frame(width: 40, height: 44)
            }
            .accessibilityIdentifier("textDone")
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

    private var stylePanel: some View {
        let range = TextStyleValues.sizeRange(for: composition)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Alignment of the lines (matters with more than one line).
                HStack(spacing: 8) {
                    ForEach([("left", "text.alignleft"), ("center", "text.aligncenter"), ("right", "text.alignright")], id: \.0) { align, symbol in
                        Button { values.align = align } label: {
                            Image(systemName: symbol).font(.body)
                                .frame(maxWidth: .infinity).frame(height: 40)
                                .background(values.align == align ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .foregroundColor(values.align == align ? .accentColor : .primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("textAlign-\(align)")
                    }
                }
                swatchRow(title: "Text", selected: values.color, includesNone: false, idPrefix: "textColor") { values.color = $0 ?? values.color }
                swatchRow(title: "Background", selected: values.backgroundColor, includesNone: true, idPrefix: "textBackground") { values.backgroundColor = $0 }
                HStack(spacing: 12) {
                    Text("Size").font(.subheadline).foregroundColor(.secondary)
                    Slider(value: $values.fontSize, in: range).accessibilityIdentifier("textSize")
                    Text("\(Int((values.fontSize / composition.width * 360).rounded()))").font(.subheadline.monospacedDigit()).frame(width: 30, alignment: .trailing)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
    }

    /// A labelled row of colour dots; the background row starts with a "none" dot (a slash).
    private func swatchRow(title: String, selected: String?, includesNone: Bool, idPrefix: String, pick: @escaping (String?) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if includesNone {
                        Button { pick(nil) } label: {
                            Image(systemName: "nosign").font(.system(size: 22)).foregroundColor(.secondary)
                                .frame(width: 34, height: 34)
                                .overlay(Circle().strokeBorder(selected == nil ? Color.accentColor : .clear, lineWidth: 3).padding(-4))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("\(idPrefix)-none")
                    }
                    ForEach(Self.swatches, id: \.self) { hex in
                        let on = selected?.lowercased() == hex.lowercased()
                        Button { pick(hex) } label: {
                            Circle().fill(Color(hex: hex)).frame(width: 34, height: 34)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                                .overlay(Circle().strokeBorder(on ? Color.accentColor : .clear, lineWidth: 3).padding(-4))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("\(idPrefix)-\(hex)")
                    }
                }
                .padding(.horizontal, 4).padding(.vertical, 6)
            }
        }
    }
}
