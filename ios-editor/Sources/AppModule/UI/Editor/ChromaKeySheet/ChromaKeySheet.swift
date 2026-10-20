import SwiftUI
import UIKit

/// Chroma key controls use the editor's light sheet, native controls and live stage preview.
struct ChromaKeySheet: View {
    @Binding var draft: ChromaKeyDraft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                colorControl
                VStack(spacing: 13) {
                    slider("Intensity", value: $draft.similarity, id: "chromaSimilarity")
                    slider("Shadow", value: $draft.shadow, id: "chromaShadow")
                    slider("Feather edge", value: $draft.smoothness, id: "chromaSmoothness")
                    slider("Clean up edge", value: $draft.edgeCleanup, id: "chromaCleanup")
                }
                .padding(.horizontal, 16)
                Spacer(minLength: 0)
            }
            .padding(.top, 16)
            .navigationTitle("Chroma key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        draft = ChromaKeyDraft()
                    }
                        .accessibilityIdentifier("chromaReset")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold).accessibilityIdentifier("chromaDone")
                }
            }
        }
        .preferredColorScheme(.light)
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(uiColor: .systemBackground))
        .presentationBackgroundInteraction(.enabled)
    }

    private var colorControl: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Key color").font(.subheadline.weight(.medium))
                Text("Drag the picker on the preview to sample")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(draft.enabled ? draft.keyColor.uppercased() : "No color selected")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Key color")
        .accessibilityValue(draft.enabled ? draft.keyColor.uppercased() : "No color selected")
        .accessibilityIdentifier("chromaKeyColor")
    }

    private func slider(_ title: String, value: Binding<Double>, id: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(width: 112, alignment: .leading)
            Slider(value: value, in: 0...1)
                .tint(.accentColor)
                .accessibilityIdentifier(id)
            Text("\(Int((value.wrappedValue * 100).rounded()))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
    }

}

/// A draggable loupe over the live stage. Its touch point is mapped back into the selected layer's source pixels,
/// then the sampled color is written into the same live Chroma Key draft as the controls in the sheet.
struct ChromaKeyPickerOverlay: View {
    let layer: V2Layer
    let project: V2Project
    let composition: V2Composition
    let atMs: Double
    let onSample: (String) -> Void

    @State private var sourceImage: UIImage?
    @State private var pickerPosition: CGPoint?
    @State private var hasSampledColor = false
    @State private var lastPublishedAt = Date.distantPast
    @State private var dragOrigin: CGPoint?
    @State private var didMovePicker = false
    @State private var previewColor: String?

    private let pickerSize: CGFloat = 92

    var body: some View {
        GeometryReader { proxy in
            let center = pickerPosition ?? CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ZStack {
                Color.clear.contentShape(Rectangle())
                picker
                    .position(center)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                if pickerPosition == nil {
                    Text("Drag on preview to sample")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.7), lineWidth: 1))
                        .position(x: center.x, y: center.y + pickerSize * 0.78)
                        .accessibilityHidden(true)
                }
            }
            // Keep gesture and accessibility coordinates in the exact same full-stage space as PreviewCanvas.
            // Without an explicit frame, SwiftUI can shrink the interactive ZStack to its visible loupe/content,
            // which makes `DragGesture.Value.location` drift from the video coordinates on portrait footage.
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragOrigin == nil {
                        dragOrigin = value.startLocation
                        didMovePicker = false
                    }
                    pickerPosition = value.location
                    if let dragOrigin, hypot(value.location.x - dragOrigin.x, value.location.y - dragOrigin.y) >= 3 {
                        didMovePicker = true
                        sampleAndPublish(at: value.location, stageSize: proxy.size)
                    }
                }
                .onEnded { value in
                    pickerPosition = value.location
                    if didMovePicker {
                        sampleAndPublish(at: value.location, stageSize: proxy.size, commit: true)
                    }
                    dragOrigin = nil
                    didMovePicker = false
                }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Color sampler")
            .accessibilityValue(sourceImage == nil ? "Loading" : (hasSampledColor ? "Active" : "Ready"))
            .accessibilityIdentifier("chromaColorSampler")
            .task(id: "\(layer.id)-\(Int(atMs))") {
                sourceImage = await CropStill.image(for: layer, project: project, atMs: atMs)
            }
        }
    }

    private var picker: some View {
        ZStack {
            if let previewColor {
                Circle()
                    .inset(by: 2)
                    .strokeBorder(Color(hex: previewColor), lineWidth: 12)
            } else {
                Image(uiImage: Self.transparencyChecker)
                    .resizable()
                    .frame(width: pickerSize, height: pickerSize)
                    .mask { Circle().strokeBorder(.white, lineWidth: 12) }
            }

            // A 1 px sample is shown at the exact centre; the checker or sampled-color annulus remains around it.
            ZStack {
                Circle()
                    .fill(previewColor.map(Color.init(hex:)) ?? Color(.systemBackground))
                    .frame(width: 10, height: 10)
                Rectangle().fill(.black.opacity(0.78)).frame(width: 1.5, height: 13)
                Rectangle().fill(.black.opacity(0.78)).frame(width: 13, height: 1.5)
            }
        }
        .frame(width: pickerSize, height: pickerSize)
        .shadow(color: .black.opacity(0.28), radius: 5, y: 2)
    }

    private static let transparencyChecker: UIImage = {
        guard let url = Bundle.main.url(forResource: "transparency-checker", withExtension: "png"),
              let image = UIImage(contentsOfFile: url.path) else {
            assertionFailure("Missing transparency-checker.png app resource")
            return UIImage()
        }
        return image
    }()

    /// Keep the live preview responsive while following the finger; always commit the exact release pixel.
    private func sampleAndPublish(at point: CGPoint, stageSize: CGSize, commit: Bool = false) {
        guard let sourceImage,
              let color = Self.sample(sourceImage, at: point, in: stageSize,
                                      layer: layer, composition: composition, atMs: atMs) else { return }
        let now = Date()
        guard commit || now.timeIntervalSince(lastPublishedAt) >= 1.0 / 24 else { return }
        lastPublishedAt = now
        previewColor = color
        if commit {
            hasSampledColor = true
            onSample(color)
        }
    }

    private static func sample(_ image: UIImage, at point: CGPoint, in stageSize: CGSize,
                               layer: V2Layer, composition: V2Composition, atMs: Double) -> String? {
        guard let cgImage = image.cgImage, composition.width > 0, composition.height > 0,
              layer.frame.width > 0, layer.frame.height > 0 else { return nil }
        let stageScale = min(stageSize.width / composition.width, stageSize.height / composition.height)
        let renderedWidth = composition.width * stageScale
        let renderedHeight = composition.height * stageScale
        let compositionPoint = CGPoint(x: (point.x - (stageSize.width - renderedWidth) / 2) / stageScale,
                                       y: (point.y - (stageSize.height - renderedHeight) / 2) / stageScale)
        let frame = sampleLayer(layer, atMs: atMs)
        let angle = (frame.rotateZ + frame.motionRotation) * .pi / 180
        let anchor = CGPoint(x: frame.frameWidth / 2 + frame.anchorX, y: frame.frameHeight / 2 + frame.anchorY)
        let translated = CGPoint(x: compositionPoint.x - composition.width / 2 - frame.translateX - frame.motionDx,
                                 y: compositionPoint.y - composition.height / 2 - frame.translateY - frame.motionDy)
        let dx = translated.x - frame.anchorX
        let dy = translated.y - frame.anchorY
        let rotatedX = cos(angle) * dx + sin(angle) * dy
        let rotatedY = -sin(angle) * dx + cos(angle) * dy
        guard abs(frame.scaleX) > 0.0001, abs(frame.scaleY) > 0.0001 else { return nil }
        let localX = anchor.x + rotatedX / frame.scaleX
        let localY = anchor.y + rotatedY / frame.scaleY
        let u = localX / frame.frameWidth
        let v = localY / frame.frameHeight
        guard (0...1).contains(u), (0...1).contains(v) else { return nil }

        let imageAspect = CGFloat(cgImage.width) / CGFloat(cgImage.height)
        let frameAspect = CGFloat(frame.frameWidth / max(frame.frameHeight, 1))
        let needsQuarterTurn = abs(imageAspect - frameAspect) > 0.05 && abs(1 / imageAspect - frameAspect) < 0.05
        let uprightWidth = needsQuarterTurn ? cgImage.height : cgImage.width
        let uprightHeight = needsQuarterTurn ? cgImage.width : cgImage.height
        let fit: CGFloat = frame.fit == "contain" ? min(CGFloat(frame.frameWidth) / CGFloat(uprightWidth), CGFloat(frame.frameHeight) / CGFloat(uprightHeight))
                                                   : max(CGFloat(frame.frameWidth) / CGFloat(uprightWidth), CGFloat(frame.frameHeight) / CGFloat(uprightHeight))
        let visibleWidth = CGFloat(uprightWidth) * fit / CGFloat(frame.frameWidth)
        let visibleHeight = CGFloat(uprightHeight) * fit / CGFloat(frame.frameHeight)
        let uprightU = (u - (1 - visibleWidth) / 2) / visibleWidth
        let uprightV = (v - (1 - visibleHeight) / 2) / visibleHeight
        guard (0...1).contains(uprightU), (0...1).contains(uprightV) else { return nil }
        // For this track's 90° counter-clockwise display transform, map upright preview coordinates back to its raw buffer.
        let sourceU = needsQuarterTurn ? 1 - uprightV : uprightU
        let sourceV = needsQuarterTurn ? uprightU : uprightV
        // Chroma key uses the exact source pixel under the touch point (1×1), not an averaged neighborhood.
        let x = min(max(Int(sourceU * CGFloat(cgImage.width - 1)), 0), cgImage.width - 1)
        let y = min(max(Int(sourceV * CGFloat(cgImage.height - 1)), 0), cgImage.height - 1)
        guard let pixel = cgImage.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
              let bytes = context.data else { return nil }
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let rgba = bytes.assumingMemoryBound(to: UInt8.self)
        let alpha = max(Int(rgba[3]), 1)
        let red = min(255, Int(rgba[0]) * 255 / alpha)
        let green = min(255, Int(rgba[1]) * 255 / alpha)
        let blue = min(255, Int(rgba[2]) * 255 / alpha)
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
