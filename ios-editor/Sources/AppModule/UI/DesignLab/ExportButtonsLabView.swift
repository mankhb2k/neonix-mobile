import SwiftUI

/// Side-by-side preview of the editor's current export actions and native SwiftUI button styles.
struct ExportButtonsLabView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var resolution: ExportResolution = .p720
    @State private var frameRate = 30
    @State private var bitrateMbps = 5

    fileprivate enum Variant: String, CaseIterable, Identifiable {
        case current = "Current Neonix"
        case bordered = "iOS Bordered"
        case filled = "iOS Filled"
        case glass = "iOS Glass"

        var id: Self { self }
        var detail: String {
            switch self {
            case .current: "Custom cyan Export and subtle Quality button, matching the editor today."
            case .bordered: "Both actions use the native bordered style with the app's cyan tint."
            case .filled: "Quality stays bordered; Export uses the native prominent hierarchy."
            case .glass: "Native glass materials; available on iOS 26 and later."
            }
        }
    }

    private var availableVariants: [Variant] {
        if #available(iOS 26.0, *) { return Variant.allCases }
        return Variant.allCases.filter { $0 != .glass }
    }

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Compare the editor header buttons. Tap any Quality button to test resolution, frame rate and bitrate.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    headerPreview

                    VStack(spacing: 12) {
                        ForEach(availableVariants) { variant in
                            variantCard(variant)
                        }
                    }

                    Label("Preview only · Quality values stay in this lab; Export does not render a video", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .preferredColorScheme(.light)
        .accessibilityIdentifier("exportButtonsLab")
    }

    private var navigationBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color(.secondarySystemBackground), in: Circle())
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier("exportButtonsLabClose")

            Text("Export buttons")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private var headerPreview: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button("Cancel") {}
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .frame(width: 68, height: 32)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                Spacer(minLength: 0)
                currentQualityButton
                currentExportButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))

            ZStack {
                LinearGradient(colors: [Color(red: 0.05, green: 0.12, blue: 0.18), .black],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 8) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 30, weight: .regular))
                        .foregroundStyle(Color.cyan)
                    Text("Editor preview")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .frame(height: 105)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
        .accessibilityIdentifier("exportButtonsHeaderPreview")
    }

    private func variantCard(_ variant: Variant) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(variant.rawValue)
                    .font(.headline)
                Spacer()
                if variant == .current {
                    Text("NOW")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.cyan)
                }
            }

            Text(variant.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)

            StyledExportButtonPair(
                variant: variant,
                resolution: $resolution,
                frameRate: $frameRate,
                bitrateMbps: $bitrateMbps
            )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityIdentifier("exportButtons-\(variant.id.rawValue)")

            Text("Selected · \(resolution.title) · \(frameRate) fps · \(bitrateMbps) Mbps")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var currentQualityButton: some View {
        ExportQualityLabButton(resolution: $resolution, frameRate: $frameRate, bitrateMbps: $bitrateMbps)
            .frame(width: 68, height: 32)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
            .buttonStyle(.plain)
    }

    private var currentExportButton: some View {
        Button("Export") {}
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.black)
            .frame(width: 68, height: 32)
            .background(Color.cyan, in: RoundedRectangle(cornerRadius: 10))
            .buttonStyle(.plain)
    }

}

private struct StyledExportButtonPair: View {
    let variant: ExportButtonsLabView.Variant
    @Binding var resolution: ExportResolution
    @Binding var frameRate: Int
    @Binding var bitrateMbps: Int

    private var qualitySettingsButton: some View {
        ExportQualityLabButton(resolution: $resolution, frameRate: $frameRate, bitrateMbps: $bitrateMbps)
    }

    var body: some View {
        Group {
            switch variant {
            case .current:
                HStack(spacing: 8) {
                    qualitySettingsButton
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                    }
                    Button("Export") {}
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .frame(width: 68, height: 32)
                        .background(Color.cyan, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            case .bordered:
                pair
                    .tint(.cyan)
                    .buttonStyle(.bordered)
            case .filled:
                HStack(spacing: 8) {
                    qualitySettingsButton.buttonStyle(.bordered)
                    exportButton.buttonStyle(.borderedProminent)
                }
                .tint(.cyan)
            case .glass:
                if #available(iOS 26.0, *) {
                    HStack(spacing: 8) {
                        qualitySettingsButton.buttonStyle(.glass)
                        exportButton.buttonStyle(.glassProminent)
                    }
                    .tint(.cyan)
                }
            }
        }
    }

    private var pair: some View {
        HStack(spacing: 8) {
            qualitySettingsButton
            exportButton
        }
    }

    private var exportButton: some View {
        Button("Export") {}
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 68, height: 32)
    }
}

private struct ExportQualityLabButton: View {
    @Binding var resolution: ExportResolution
    @Binding var frameRate: Int
    @Binding var bitrateMbps: Int
    @State private var isShowingQuality = false

    var body: some View {
        Button { isShowingQuality = true } label: {
            HStack(spacing: 4) {
                Text(resolution.buttonTitle).font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .regular))
            }
            .frame(width: 68, height: 32)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Quality, \(resolution.title)")
        .accessibilityIdentifier("exportQualityLabButton")
        .popover(isPresented: $isShowingQuality, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            ExportQualityPopover(
                selection: resolution,
                frameRate: frameRate,
                bitrateMbps: bitrateMbps,
                onResolutionChange: { resolution = $0 },
                onFrameRateChange: { frameRate = $0 },
                onBitrateChange: { bitrateMbps = $0 }
            )
            .presentationCompactAdaptation(.popover)
            .preferredColorScheme(.light)
        }
    }
}
