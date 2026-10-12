import ImageIO
import SwiftUI

/// Design lab for the Adjust tool: 13 controls instead of Transform's 5, so the question here is how the round
/// buttons behave when they no longer fit - scroll sideways, or split into groups (both open the Curves-style sheet). Same mock editor around it,
/// a real photo whose look follows the values (an approximation: sharpen, clarity and noise do not show), and
/// press-and-hold on the photo to compare with the original, like Photos.
struct AdjustLabView: View {
    @Environment(\.dismiss) private var dismiss

    enum Variant: String, CaseIterable, Identifiable {
        case scroll = "Scroll", groups = "Groups"
        var id: String { rawValue }

        var summary: String {
            switch self {
            case .scroll: return "Sheet: ruler + one scrolling row of all 13 buttons (selected one auto-centres)"
            case .groups: return "Sheet: ruler + Light / Color / Detail tabs, 4-5 fixed buttons each"
            }
        }
    }

    @State private var variant: Variant = .scroll
    @State private var values = LabAdjustValues()
    @State private var param: LabAdjustParam = .brightness
    @State private var sheetOpen = false
    @State private var haptics = true
    @State private var sheetHeight: LabSheetHeight = .standard
    @State private var photo: UIImage?
    @State private var showsOriginal = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Picker("Layout", selection: $variant) {
                ForEach(Variant.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .accessibilityIdentifier("adjVariantPicker")
            Text(variant.summary).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal).padding(.top, 4)

            stage
                .padding(.horizontal, 44).padding(.vertical, 8)
                .frame(maxHeight: .infinity)

            bottomBar
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .task { photo = await Self.loadPhoto() }
        .onChange(of: variant) { _, _ in sheetOpen = false }
        .sheet(isPresented: $sheetOpen) { adjustSheet }
    }

    // MARK: Top + stage

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.title3).frame(width: 44, height: 44) }
                .accessibilityIdentifier("adjClose")
            Spacer()
            Text("Adjust lab").font(.headline)
            Spacer()
            Menu {
                Toggle("Haptics on ruler", isOn: $haptics)
                Picker("Sheet height", selection: $sheetHeight) { ForEach(LabSheetHeight.allCases) { Text($0.rawValue).tag($0) } }
                Button("Reset all", role: .destructive) { values = LabAdjustValues() }
            } label: { Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44) }
        }
        .padding(.horizontal, 8)
    }

    private var stage: some View {
        // The photo is an overlay so its own size never decides the layout (a scaledToFill image would widen the
        // whole screen when there is room): the frame takes the space offered and the photo is cropped to it.
        Color(.tertiarySystemBackground)
            .overlay {
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                        .modifier(LabAdjustLook(values: showsOriginal ? LabAdjustValues() : values))
                } else {
                    ProgressView()
                }
            }
            .clipped()
            .aspectRatio(9.0 / 16.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .topLeading) {
            if showsOriginal {
                Text("Original").font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: Capsule()).foregroundColor(.white).padding(8)
            }
        }
        // Hold to compare with the untouched photo.
        .onLongPressGesture(minimumDuration: 0.15, maximumDistance: 40, perform: {}, onPressingChanged: { showsOriginal = $0 })
        .accessibilityIdentifier("adjStage")
    }

    // MARK: Bottom bar (what the editor's one row will look like)

    private var bottomBar: some View { mockSelectionRow }

    /// The row the editor shows while a photo is selected; Adjust is one of its buttons.
    private var mockSelectionRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left.2").font(.body.weight(.semibold)).frame(width: 44, height: 44)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Divider().frame(height: 28)
            ForEach([("scissors", "Split"), ("slider.horizontal.3", "Adjust"), ("trash", "Delete")], id: \.1) { symbol, title in
                Button {
                    if title == "Adjust" { sheetOpen = true }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: symbol).font(.title3)
                        Text(title).font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(title == "Delete" ? .red : (title == "Split" ? .secondary : .primary))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("adjAction-\(title)")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: Sheet

    private var adjustSheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                RulerDial(value: binding(param), mapping: param.mapping, detents: [param.neutral], neutral: param.neutral, haptics: haptics, format: param.display)
                    .id(param)
                    .padding(.bottom, 20)   // 12 (stack spacing) + 20 = 32 pt between the ruler and what is below it
                if variant == .groups { groupTabs; groupChips } else { scrollingChips(idPrefix: "sheetChip") }
            }
            .padding(.top, 8)
            .navigationTitle(param.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset all") { values = LabAdjustValues() }.disabled(LabAdjustParam.allCases.allSatisfy { !values.isChanged($0) })
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { sheetOpen = false }.accessibilityIdentifier("adjDone")
                }
            }
        }
        .presentationDetents(sheetHeight.detents(extra: variant == .groups ? 30 : 0))
        .presentationDragIndicator(sheetHeight.showsGrabber ? .visible : .hidden)
        .presentationBackgroundInteraction(.enabled)
    }

    // MARK: Chips

    /// All 13 in one row. The selected one is scrolled to the centre, the edges fade, and a dot marks every button
    /// whose value has been changed - including the ones scrolled out of sight.
    private func scrollingChips(idPrefix: String) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(LabAdjustParam.allCases) { item in chip(item, idPrefix: idPrefix).id(item) }
                }
                .padding(.horizontal, 16)
            }
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                                         .init(color: .black, location: 0.94), .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
            .onChange(of: param) { _, new in withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(new, anchor: .center) } }
            .onAppear { proxy.scrollTo(param, anchor: .center) }
            .accessibilityIdentifier("chipsScroll")
        }
    }

    private var groupTabs: some View {
        HStack(spacing: 8) {
            ForEach(LabAdjustGroup.allCases) { group in
                let selected = param.group == group
                let changed = values.changedCount(in: group)
                Button {
                    if param.group != group, let first = LabAdjustParam.allCases.first(where: { $0.group == group }) { param = first }
                } label: {
                    HStack(spacing: 5) {
                        Text(group.rawValue).font(.subheadline.weight(.medium))
                        if changed > 0 { Circle().fill(selected ? Color.white : Color.accentColor).frame(width: 6, height: 6) }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .background(selected ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                    .foregroundColor(selected ? .white : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("group-\(group.rawValue)")
            }
        }
    }

    /// 4-5 buttons of the current group: they fit, so nothing scrolls.
    private var groupChips: some View {
        HStack(spacing: 14) {
            ForEach(LabAdjustParam.allCases.filter { $0.group == param.group }) { item in chip(item, idPrefix: "groupChip") }
        }
        .padding(.horizontal, 16)
    }

    private func chip(_ item: LabAdjustParam, idPrefix: String) -> some View {
        let selected = param == item
        let changed = values.isChanged(item)
        return Button { param = item } label: {
            VStack(spacing: 3) {
                Circle()
                    .fill(selected ? Color.accentColor : Color(.tertiarySystemBackground))
                    .frame(width: 48, height: 48)
                    .overlay(Image(systemName: item.symbol).font(.system(size: 18, weight: .medium)).foregroundColor(selected ? .white : .primary))
                Text(item.display(values[item])).font(.caption2.monospacedDigit()).foregroundColor(changed ? .accentColor : .secondary)
                Circle().fill(changed ? Color.accentColor : .clear).frame(width: 5, height: 5)
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded { values[item] = item.neutral })
        .accessibilityIdentifier("\(idPrefix)-\(item.rawValue)")
        .accessibilityLabel(item.title)
        .accessibilityValue(item.display(values[item]))
    }

    private func binding(_ p: LabAdjustParam) -> Binding<Double> {
        Binding(get: { values[p] }, set: { values[p] = $0 })
    }

    // MARK: Photo

    private static func loadPhoto() async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let url = bundledURL(filename: "pexels-followingnyc-38428141.jpg"),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                           kCGImageSourceThumbnailMaxPixelSize: 1100] as CFDictionary
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options).map { UIImage(cgImage: $0) }
        }.value
    }
}

/// SwiftUI stand-ins for the real Core Image filters, enough to see the values do something while judging the UI.
private struct LabAdjustLook: ViewModifier {
    let values: LabAdjustValues

    func body(content: Content) -> some View {
        content
            .brightness(values[.brightness] * 0.5 + values[.exposure] * 0.2)
            .contrast(values[.contrast])
            .saturation(values[.saturation])
            .hueRotation(.degrees(values[.hue]))
            .overlay(Color(red: 1, green: 0.55, blue: 0.1).opacity(max(0, values[.temperature]) * 0.4).blendMode(.overlay).allowsHitTesting(false))
            .overlay(Color(red: 0.1, green: 0.5, blue: 1).opacity(max(0, -values[.temperature]) * 0.4).blendMode(.overlay).allowsHitTesting(false))
            .overlay(Color(red: 0.2, green: 1, blue: 0.3).opacity(max(0, values[.tint]) * 0.3).blendMode(.overlay).allowsHitTesting(false))
            .overlay(Color(red: 1, green: 0.2, blue: 0.8).opacity(max(0, -values[.tint]) * 0.3).blendMode(.overlay).allowsHitTesting(false))
            .overlay(
                RadialGradient(colors: [.clear, .black.opacity(min(values[.vignette], 2) * 0.35)], center: .center, startRadius: 40, endRadius: 360)
                    .allowsHitTesting(false)
            )
    }
}
