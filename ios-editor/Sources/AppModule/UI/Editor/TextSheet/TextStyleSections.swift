import SwiftUI

/// What each badge of the Style tab shows (user 2026-10-14, after CapCut): Text, Colors, Stroke, Glow, Background, Shadow, Curve,
/// Spacing and Case, each with its own colours and sliders. Every control writes `values`, which the shell sends live to the clip.
extension TextSheet {
    @ViewBuilder var styleSectionContent: some View {
        switch section {
        case .text: textSection
        case .colors:
            ColorSwatchGrid(selected: values.color, recent: recentColors, idPrefix: "textColor",
                            pick: { values.color = $0 ?? values.color },
                            openCustom: { picker = .text(from: values.color) })
        case .stroke: strokeSection
        case .glow: glowSection
        case .background: backgroundSection
        case .shadow: shadowSection
        case .curve: curveSection
        case .spacing: spacingSection
        case .letterCase: caseSection
        }
    }

    // MARK: Text

    private var textSection: some View {
        VStack(spacing: 14) {
            presetRow.padding(.horizontal, -16)   // runs edge to edge; the content's own inset is cancelled
            slider("Size", value: $values.fontSize, in: TextStyleValues.sizeRange(for: composition), id: "textSize") { "\(Int((values.fontSize / composition.width * 360).rounded()))" }
        }
    }

    // MARK: Stroke / glow / shadow

    private var strokeSection: some View {
        VStack(spacing: 12) {
            ColorSwatchGrid(selected: values.strokeColor, recent: recentColors, includesNone: true, idPrefix: "strokeColor",
                            pick: { values.strokeColor = $0 }, openCustom: { picker = .stroke(from: values.strokeColor) })
            slider("Width", value: $values.strokeWidth, in: 0...0.2, id: "strokeWidth", enabled: values.strokeColor != nil) { percent(values.strokeWidth / 0.2) }
        }
    }

    private var glowSection: some View {
        VStack(spacing: 12) {
            ColorSwatchGrid(selected: values.glowColor, recent: recentColors, includesNone: true, idPrefix: "glowColor",
                            pick: { values.glowColor = $0 }, openCustom: { picker = .glow(from: values.glowColor) })
            slider("Intensity", value: $values.glowIntensity, in: 0...1, id: "glowIntensity", enabled: values.glowColor != nil) { percent(values.glowIntensity) }
            slider("Blur", value: $values.glowBlur, in: 0.05...0.8, id: "glowBlur", enabled: values.glowColor != nil) { percent((values.glowBlur - 0.05) / 0.75) }
        }
    }

    private var shadowSection: some View {
        VStack(spacing: 12) {
            ColorSwatchGrid(selected: values.shadowColor, recent: recentColors, includesNone: true, idPrefix: "shadowColor",
                            pick: { values.shadowColor = $0 }, openCustom: { picker = .shadow(from: values.shadowColor) })
            let on = values.shadowColor != nil
            slider("Opacity", value: $values.shadowOpacity, in: 0...1, id: "shadowOpacity", enabled: on) { percent(values.shadowOpacity) }
            slider("Blur", value: $values.shadowBlur, in: 0...0.5, id: "shadowBlur", enabled: on) { percent(values.shadowBlur / 0.5) }
            slider("Distance", value: $values.shadowDistance, in: 0...0.6, id: "shadowDistance", enabled: on) { percent(values.shadowDistance / 0.6) }
            slider("Angle", value: $values.shadowAngle, in: -180...180, id: "shadowAngle", enabled: on) { "\(Int(values.shadowAngle.rounded()))°" }
        }
    }

    // MARK: Background

    private var backgroundSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                backgroundTile(id: "none", on: values.backgroundColor == nil) { values.backgroundColor = nil } label: {
                    Image(systemName: "nosign").font(.system(size: 20)).foregroundColor(.secondary)
                }
                backgroundTile(id: "hug", on: values.backgroundColor != nil && values.backgroundStyle == "hug") { chooseBackground("hug") } label: {
                    shapeIcon(stepped: true)
                }
                backgroundTile(id: "box", on: values.backgroundColor != nil && values.backgroundStyle == "box") { chooseBackground("box") } label: {
                    shapeIcon(stepped: false)
                }
                Spacer(minLength: 0)
            }
            ColorSwatchGrid(selected: values.backgroundColor, recent: recentColors, idPrefix: "textBackground",
                            pick: { if let hex = $0 { values.backgroundColor = hex } }, openCustom: { picker = .background(from: values.backgroundColor) })
            let on = values.backgroundColor != nil
            slider("Opacity", value: $values.backgroundOpacity, in: 0...1, id: "backgroundOpacity", enabled: on) { percent(values.backgroundOpacity) }
            slider("Corner radius", value: $values.backgroundRadius, in: 0...0.6, id: "backgroundRadius", enabled: on) { percent(values.backgroundRadius / 0.6) }
            slider("Height", value: $values.backgroundPadY, in: 0...0.6, id: "backgroundHeight", enabled: on) { percent(values.backgroundPadY / 0.6) }
            slider("Width", value: $values.backgroundPadX, in: 0...1, id: "backgroundWidth", enabled: on) { percent(values.backgroundPadX) }
        }
    }

    /// A style tile: picking one turns the label on (white if it had no colour yet).
    private func chooseBackground(_ style: String) {
        if values.backgroundColor == nil { values.backgroundColor = "#FFFFFFff" }
        values.backgroundStyle = style
    }

    private func backgroundTile<Label: View>(id: String, on: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        Button(action: action) {
            label().frame(width: 64, height: 44)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("backgroundStyle-\(id)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// "AB / ABC" on a label: a stepped one (story style) or a plain box.
    private func shapeIcon(stepped: Bool) -> some View {
        VStack(spacing: stepped ? 0 : 2) {
            if stepped { Text("AB").font(.system(size: 11, weight: .semibold)).padding(.horizontal, 5).background(Color.secondary.opacity(0.45), in: RoundedRectangle(cornerRadius: 3)) }
            Text("ABC").font(.system(size: 11, weight: .semibold)).padding(.horizontal, 5).background(Color.secondary.opacity(0.45), in: RoundedRectangle(cornerRadius: 3))
        }
        .foregroundColor(.primary)
    }

    // MARK: Curve, spacing, case

    private var curveSection: some View {
        slider("Curve", value: $values.curve, in: -100...100, id: "curveSlider") { "\(Int(values.curve.rounded()))" }
    }

    private var spacingSection: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach([("left", "text.alignleft"), ("center", "text.aligncenter"), ("right", "text.alignright")], id: \.0) { align, symbol in
                    toggleTile(id: "textAlign-\(align)", on: values.align == align, action: { values.align = align }) { Image(systemName: symbol).font(.body) }
                }
            }
            slider("Character", value: $values.letterSpacing, in: -0.1...0.5, id: "letterSpacing") { percent((values.letterSpacing + 0.1) / 0.6) }
            slider("Line", value: $values.lineSpacing, in: -0.2...1, id: "lineSpacing") { percent((values.lineSpacing + 0.2) / 1.2) }
        }
    }

    private var caseSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                toggleTile(id: "caseBold", on: values.bold, action: { values.bold.toggle() }) { Image(systemName: "bold").font(.body.weight(.semibold)) }
                toggleTile(id: "caseItalic", on: values.italic, action: { values.italic.toggle() }) { Image(systemName: "italic").font(.body.weight(.semibold)) }
                toggleTile(id: "caseUnderline", on: values.underline, action: { values.underline.toggle() }) { Image(systemName: "underline").font(.body.weight(.semibold)) }
            }
            HStack(spacing: 8) {
                ForEach([("uppercase", "TT"), ("lowercase", "tt"), ("capitalize", "Tt")], id: \.0) { transform, label in
                    toggleTile(id: "case-\(transform)", on: values.textCase == transform, action: { values.textCase = values.textCase == transform ? nil : transform }) {
                        Text(label).font(.system(.body, design: .serif).weight(.semibold))
                    }
                }
            }
        }
    }

    // MARK: Pieces

    private func toggleTile<Label: View>(id: String, on: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(on ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundColor(on ? .accentColor : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, id: String, enabled: Bool = true, display: () -> String) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.subheadline).foregroundColor(.secondary).frame(width: 84, alignment: .leading).lineLimit(1).minimumScaleFactor(0.8)
            Slider(value: value, in: range).accessibilityIdentifier(id)
            Text(display()).font(.subheadline.monospacedDigit()).frame(width: 40, alignment: .trailing)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private func percent(_ fraction: Double) -> String { "\(Int((min(max(fraction, 0), 1) * 100).rounded()))" }
}
