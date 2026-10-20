import SwiftUI

/// Design lab for the Crop tool, after CapCut's Resize screen (user's reference 2026-10-18). One working crop frame - drag a corner to resize, drag inside to
/// move, an aspect ratio locks it, Rotate straightens the picture behind it (-20...20 degrees), Flip mirrors it - and three ways to put the controls around it:
/// A a full-screen editor like the reference (Rotate ruler, a row of aspect tiles, Reset), B the editor's sheet pattern (stage stays live, round buttons
/// Aspect / Rotate / Flip, ruler or tiles in the sheet), C an iPhone Photos style (ruler right under the picture, one aspect menu). Fake data: nothing is cropped.
struct CropLabView: View {
    @Environment(\.dismiss) private var dismiss

    enum Variant: String, CaseIterable, Identifiable {
        case full = "A Full screen", sheet = "B Sheet", photos = "C Photos"
        var id: String { rawValue }

        var summary: String {
            switch self {
            case .full: return "CapCut's Resize: ✕ / ✓ on top, a big picture, the Rotate ruler, a row of aspect tiles and Reset - everything on one screen"
            case .sheet: return "The editor's usual sheet: picture stays live above, round buttons Aspect / Rotate / Flip, the ruler or the tiles inside"
            case .photos: return "iPhone Photos: ruler right under the picture, one Aspect menu and Flip below - the least chrome, aspect takes two taps"
            }
        }
    }

    enum SheetParam: String, CaseIterable, Identifiable {
        case aspect, rotate
        var id: String { rawValue }
        var title: String { self == .aspect ? "Aspect ratio" : "Rotate" }
        var symbol: String { self == .aspect ? "crop" : "rotate.right" }
    }

    @State private var variant: Variant = .full
    @State private var crop = CropDraft()
    @State private var photo: UIImage?
    @State private var sheetOpen = false
    @State private var sheetParam: SheetParam = .aspect
    @State private var scrub = 0.7
    @State private var haptics = true
    @State private var toast: String?

    private let rotation = RulerMapping.linear(-20...20, step: 1, majorEvery: 10)

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Picker("Layout", selection: $variant) {
                ForEach(Variant.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .accessibilityIdentifier("cropVariantPicker")
            Text(variant.summary).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal).padding(.top, 4)

            switch variant {
            case .full: fullScreen
            case .sheet: sheetLayout
            case .photos: photosLayout
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .task { photo = await AdjustLabView.loadPhoto() }
        .onChange(of: variant) { _, _ in sheetOpen = false }
        .sheet(isPresented: $sheetOpen) { cropSheet }
        .overlay(alignment: .center) {
            if let toast {
                Text(toast).font(.footnote.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.75), in: Capsule()).foregroundColor(.white).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: toast)
    }

    // MARK: Lab chrome

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.title3).frame(width: 44, height: 44) }
                .accessibilityIdentifier("cropClose")
            Spacer()
            Text("Crop lab").font(.headline)
            Spacer()
            Menu {
                Toggle("Haptics on ruler", isOn: $haptics)
                Button("Reset crop", role: .destructive) { crop = CropDraft() }
            } label: { Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44) }
        }
        .padding(.horizontal, 8)
    }

    private var stage: some View {
        CropStage(image: photo, crop: $crop)
            .padding(.horizontal, 16).padding(.vertical, 8)
            // The sheet covers the lower part of the screen: the picture fits the room above it, like the editor's stage does.
            .padding(.bottom, variant == .sheet && sheetOpen ? 290 : 0)
            .frame(maxHeight: .infinity)
            .animation(.easeOut(duration: 0.25), value: sheetOpen)
    }

    private func applied() {
        toast = "Crop applied (fake)"
        Task { try? await Task.sleep(for: .milliseconds(1300)); toast = nil }
    }

    // MARK: A - full screen, after the reference

    private var fullScreen: some View {
        VStack(spacing: 0) {
            fauxBar(title: "Resize", leading: "xmark", trailing: "checkmark")
            stage
            HStack(spacing: 10) {
                Text("00:00").font(.caption.monospacedDigit()).foregroundColor(.secondary)
                Slider(value: $scrub)
                Text("00:02").font(.caption.monospacedDigit()).foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 6) {
                Text("Rotate").font(.subheadline.weight(.semibold))
                rotateDial
                Text("Aspect ratio").font(.subheadline.weight(.semibold)).padding(.top, 2)
                aspectTiles(idPrefix: "cropAspect")
                resetButton
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)
        }
    }

    private func fauxBar(title: String, leading: String, trailing: String) -> some View {
        HStack {
            Button { crop = CropDraft() } label: { Image(systemName: leading).font(.title3.weight(.semibold)).frame(width: 44, height: 40) }
                .accessibilityIdentifier("cropCancel")
            Spacer()
            Text(title).font(.headline)
            Spacer()
            Button(action: applied) { Image(systemName: trailing).font(.title3.weight(.semibold)).frame(width: 44, height: 40) }
                .accessibilityIdentifier("cropApply")
        }
        .padding(.horizontal, 12)
    }

    private var resetButton: some View {
        Button { crop = CropDraft() } label: {
            Label("Reset", systemImage: "arrow.counterclockwise").font(.subheadline.weight(.medium))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .overlay(Capsule().strokeBorder(Color(.systemGray3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!crop.isChanged)
        .opacity(crop.isChanged ? 1 : 0.4)
        .accessibilityIdentifier("cropReset")
    }

    // MARK: B - the editor's sheet

    private var sheetLayout: some View {
        VStack(spacing: 0) {
            stage
            HStack(spacing: 8) {
                Image(systemName: "chevron.left.2").font(.body.weight(.semibold)).frame(width: 44, height: 44)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Divider().frame(height: 28)
                ForEach([("scissors", "Split"), ("crop", "Crop"), ("trash", "Delete")], id: \.1) { symbol, title in
                    Button { if title == "Crop" { sheetOpen = true } } label: {
                        VStack(spacing: 4) {
                            Image(systemName: symbol).font(.title3)
                            Text(title).font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundColor(title == "Delete" ? .red : (title == "Split" ? .secondary : .primary))
                    }
                    .accessibilityIdentifier(title == "Crop" ? "cropOpen" : "cropMock-\(title)")
                }
            }
            .padding(.horizontal, 12).frame(height: 56)
        }
    }

    private var cropSheet: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Group {
                    switch sheetParam {
                    case .aspect: aspectTiles(idPrefix: "sheetAspect")
                    case .rotate: rotateDial
                    }
                }
                .frame(height: 96, alignment: .center)
                HStack(spacing: 26) {
                    sheetButton(.aspect, value: crop.aspect.title)
                    sheetButton(.rotate, value: crop.rotation == 0 ? "0°" : String(format: "%+.0f°", crop.rotation))
                    flipButton
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 8)
            .navigationTitle(sheetParam.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { crop = CropDraft() } label: { Image(systemName: "arrow.counterclockwise") }
                        .disabled(!crop.isChanged).accessibilityLabel("Reset").accessibilityIdentifier("cropSheetReset")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { sheetOpen = false }.accessibilityIdentifier("cropSheetDone") }
            }
        }
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.hidden)
        .presentationBackgroundInteraction(.enabled)
    }

    private func sheetButton(_ item: SheetParam, value: String) -> some View {
        let selected = sheetParam == item
        return Button { sheetParam = item } label: {
            VStack(spacing: 4) {
                Circle().fill(selected ? Color.accentColor : Color(.secondarySystemBackground)).frame(width: 48, height: 48)
                    .overlay(Image(systemName: item.symbol).font(.system(size: 18, weight: .medium)).foregroundColor(selected ? .white : .primary))
                Text(value).font(.caption2.monospacedDigit()).foregroundColor(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cropParam-\(item.rawValue)")
    }

    private var flipButton: some View {
        Button { crop.flipped.toggle() } label: {
            VStack(spacing: 4) {
                Circle().fill(crop.flipped ? Color.accentColor : Color(.secondarySystemBackground)).frame(width: 48, height: 48)
                    .overlay(Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right").font(.system(size: 18, weight: .medium))
                        .foregroundColor(crop.flipped ? .white : .primary))
                Text(crop.flipped ? "On" : "Flip").font(.caption2).foregroundColor(crop.flipped ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cropFlip")
    }

    // MARK: C - Photos style

    private var photosLayout: some View {
        VStack(spacing: 0) {
            HStack {
                Button { crop = CropDraft() } label: { Image(systemName: "xmark").font(.title3.weight(.semibold)).frame(width: 44, height: 40) }
                    .accessibilityIdentifier("cropCancel")
                Spacer()
                Button("Reset") { crop = CropDraft() }.font(.body.weight(.medium)).disabled(!crop.isChanged).accessibilityIdentifier("cropReset")
                Spacer()
                Button(action: applied) { Image(systemName: "checkmark").font(.title3.weight(.semibold)).frame(width: 44, height: 40) }
                    .accessibilityIdentifier("cropApply")
            }
            .padding(.horizontal, 12)
            stage
            rotateDial.padding(.horizontal, 16)
            HStack(spacing: 12) {
                Menu {
                    Picker("Aspect ratio", selection: aspectBinding) {
                        ForEach(CropAspect.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        AspectGlyph(ratio: crop.aspect.ratio ?? 1, custom: crop.aspect == .custom).frame(width: 18, height: 18)
                        Text(crop.aspect.title).font(.subheadline.weight(.medium))
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color(.secondarySystemBackground), in: Capsule())
                    .foregroundColor(.primary)
                }
                .accessibilityIdentifier("cropAspectMenu")
                Button { crop.flipped.toggle() } label: {
                    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right").font(.system(size: 16, weight: .medium))
                        .frame(width: 40, height: 38)
                        .background(crop.flipped ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                        .foregroundColor(crop.flipped ? .white : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("cropFlip")
            }
            .padding(.vertical, 10)
        }
    }

    // MARK: Shared controls

    private var rotateDial: some View {
        RulerDial(value: $crop.rotation, mapping: rotation, detents: [0], neutral: 0, haptics: haptics,
                  format: { String(format: "%.0f°", $0 == 0 ? 0 : $0) })
    }

    private var aspectBinding: Binding<CropAspect> {
        Binding(get: { crop.aspect }, set: { crop.aspect = $0 })
    }

    private func aspectTiles(idPrefix: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(CropAspect.allCases) { item in
                    let on = crop.aspect == item
                    Button { crop.aspect = item } label: {
                        VStack(spacing: 5) {
                            AspectGlyph(ratio: item.ratio ?? 1, custom: item == .custom)
                                .frame(width: 22, height: 22)
                                .frame(width: 64, height: 52)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.accentColor, lineWidth: on ? 2 : 0))
                            Text(item.title).font(.caption2).foregroundColor(on ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(idPrefix)-\(item.title)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 2)
        }
    }
}
