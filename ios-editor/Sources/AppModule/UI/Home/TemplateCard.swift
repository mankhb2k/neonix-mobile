import SwiftUI

/// "12s · 5 slots".
func templateCaption(_ template: APITemplate) -> String {
    var parts: [String] = []
    if let ms = template.version?.durationMs { parts.append("\(Int((Double(ms) / 1000).rounded()))s") }
    if let slots = template.version?.slotCount { parts.append("\(slots) slots") }
    return parts.joined(separator: " · ")
}

/// 61100 -> "61.1K".
func compactCount(_ value: Int) -> String {
    switch value {
    case 1_000_000...: return String(format: "%.1fM", Double(value) / 1_000_000)
    case 1_000...: return String(format: "%.1fK", Double(value) / 1_000)
    default: return String(value)
    }
}

/// Small round creator picture with the initial as fallback.
struct CreatorAvatar: View {
    let creator: APITemplateCreator
    var size: CGFloat = 22

    var body: some View {
        RemotePreview(url: creator.avatarUrl, gradient: [.blue, .purple])
            .overlay {
                if creator.avatarUrl == nil {
                    Text(String((creator.name ?? "N").prefix(1)).uppercased())
                        .font(.system(size: size * 0.5, weight: .bold)).foregroundColor(.white)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
    }
}

/// One card of the waterfall: the poster (a still, nothing plays here), use count, title and creator underneath.
/// The preview video plays only once a template is opened in the viewer.
struct TemplateCard: View {
    let template: APITemplate
    let onOpen: () -> Void

    private var aspect: Double {
        guard let w = template.version?.width, let h = template.version?.height, w > 0 else { return 9.0 / 16.0 }
        return min(max(Double(w) / Double(h), 0.5), 1.25)
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomLeading) {
                    RemotePreview(url: template.posterUrl ?? template.previewUrl, gradient: [.purple, .black])
                    if template.useCount > 0 {
                        Label(compactCount(template.useCount), systemImage: "scissors")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(8)
                    }
                    if template.owned == true {
                        Label("Owned", systemImage: "checkmark.seal.fill")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.white.opacity(0.9), in: Capsule())
                            .foregroundColor(.black)
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                    if TemplateCatalog.isNew(template) {
                        Text("New")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.white.opacity(0.9), in: Capsule())
                            .foregroundColor(.black)
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .aspectRatio(aspect, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text(template.title.uppercased())
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    CreatorAvatar(creator: template.creator)
                    Text(template.creator.name ?? "Neonix")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("templateCard")
    }
}
