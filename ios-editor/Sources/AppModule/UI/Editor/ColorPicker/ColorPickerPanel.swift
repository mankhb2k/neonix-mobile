import SwiftUI

/// CapCut's custom colour screen (user 2026-10-14): it replaces the sheet's whole content - a saturation / brightness square, a hue
/// bar, and ✕ (back to the colour it started with) and ✓ (keep). Every drag goes live through `onChange`, so the stage shows the colour
/// while it is chosen. Alpha is not offered (the colour is opaque).
struct ColorPickerPanel: View {
    let initial: String
    let onChange: (String) -> Void
    let onCancel: () -> Void
    let onDone: (String) -> Void

    @State private var hue: Double
    @State private var saturation: Double
    @State private var brightness: Double

    init(initial: String, onChange: @escaping (String) -> Void, onCancel: @escaping () -> Void, onDone: @escaping (String) -> Void) {
        self.initial = initial
        self.onChange = onChange; self.onCancel = onCancel; self.onDone = onDone
        let hsb = ColorPalette.hsb(of: initial)
        _hue = State(initialValue: hsb.hue); _saturation = State(initialValue: hsb.saturation); _brightness = State(initialValue: hsb.brightness)
    }

    private var current: String { ColorPalette.hex(hue: hue, saturation: saturation, brightness: brightness) }

    var body: some View {
        VStack(spacing: 14) {
            square
            hueBar
            HStack {
                Button(action: onCancel) { Image(systemName: "xmark").font(.title3).frame(width: 52, height: 40) }
                    .accessibilityIdentifier("colorPickerCancel")
                Spacer()
                Circle().fill(Color(hex: current)).frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                    .accessibilityIdentifier("colorPickerSwatch").accessibilityValue(current)
                Spacer()
                Button { onDone(current) } label: { Image(systemName: "checkmark").font(.title3.weight(.semibold)).frame(width: 52, height: 40) }
                    .accessibilityIdentifier("colorPickerDone")
            }
        }
        .padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 8)
    }

    private var square: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [.white, Color(hue: hue, saturation: 1, brightness: 1)], startPoint: .leading, endPoint: .trailing))
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
                Circle().strokeBorder(.white, lineWidth: 3).background(Circle().fill(Color(hex: current)))
                    .frame(width: 26, height: 26).shadow(color: .black.opacity(0.35), radius: 2)
                    .offset(x: saturation * size.width - 13, y: (1 - brightness) * size.height - 13)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                saturation = min(max(value.location.x / size.width, 0), 1)
                brightness = 1 - min(max(value.location.y / size.height, 0), 1)
                onChange(current)
            })
        }
        .frame(minHeight: 100)
        .accessibilityElement().accessibilityLabel("Saturation and brightness").accessibilityIdentifier("colorSquare")
    }

    private var hueBar: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: (0...6).map { Color(hue: Double($0) / 6, saturation: 1, brightness: 1) }, startPoint: .leading, endPoint: .trailing))
                Circle().strokeBorder(.white, lineWidth: 3).background(Circle().fill(Color(hue: hue, saturation: 1, brightness: 1)))
                    .frame(width: 28, height: 28).shadow(color: .black.opacity(0.35), radius: 2)
                    .offset(x: hue * (width - 28))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                hue = min(max((value.location.x - 14) / (width - 28), 0), 1)
                onChange(current)
            })
        }
        .frame(height: 28)
        .accessibilityElement().accessibilityLabel("Hue").accessibilityIdentifier("colorHue")
    }
}
