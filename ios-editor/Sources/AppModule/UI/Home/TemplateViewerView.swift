import SwiftUI

/// Full-screen, vertical, one template per page (swipe up/down). The poster shows first, the preview video
/// plays on the current page, and "Use template" starts the slot-filling flow.
struct TemplateViewerView: View {
    let templates: [APITemplate]
    @State var currentID: String?

    @Environment(\.dismiss) private var dismiss
    @State private var isMuted = false
    @State private var using: APITemplate?

    init(templates: [APITemplate], startID: String) {
        self.templates = templates
        self.startID = startID
        _currentID = State(initialValue: startID)
    }

    private let startID: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(templates) { template in
                        TemplatePage(template: template, isCurrent: currentID == template.id, isMuted: $isMuted) { using = template }
                            .containerRelativeFrame([.horizontal, .vertical])
                            .id(template.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentID)
            // `scrollPosition` alone does not jump to the initial id inside a lazy stack, so go there explicitly.
            .onAppear { DispatchQueue.main.async { proxy.scrollTo(startID, anchor: .top) } }
        }
        .background(Color.black.ignoresSafeArea())
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.title3.weight(.semibold)).foregroundColor(.white)
                    .frame(width: 44, height: 44).background(.black.opacity(0.35), in: Circle())
            }
            .padding(.leading, 16).padding(.top, 54)
        }
        .overlay(alignment: .topTrailing) {
            Button { isMuted.toggle() } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.body).foregroundColor(.white)
                    .frame(width: 44, height: 44).background(.black.opacity(0.35), in: Circle())
            }
            .padding(.trailing, 16).padding(.top, 54)
        }
        .fullScreenCover(item: $using) { template in TemplateUseFlowView(template: template) }
    }
}

private struct TemplatePage: View {
    let template: APITemplate
    let isCurrent: Bool
    @Binding var isMuted: Bool
    let onUse: () -> Void

    @State private var videoReady = false

    var body: some View {
        ZStack(alignment: .bottom) {
            RemotePreview(url: template.posterUrl ?? template.previewUrl, gradient: [.purple, .black])
            if isCurrent, let url = template.previewUrl, isVideoURL(url) {
                LoopingVideoView(url: url, isMuted: isMuted) { videoReady = true }
                    .opacity(videoReady ? 1 : 0)
            }

            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    CreatorAvatar(creator: template.creator, size: 32)
                    Text(template.creator.name ?? "Neonix").font(.subheadline.weight(.semibold))
                }
                Text(template.title).font(.title3.bold())
                if !template.description.isEmpty {
                    Text(template.description).font(.footnote).opacity(0.85).lineLimit(2)
                }
                chips

                Button(action: onUse) {
                    Text("Use template").font(.headline).foregroundColor(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .accessibilityIdentifier(isCurrent ? "useTemplate-current" : "useTemplate")
                Text(priceNote)
                    .font(.caption2).opacity(0.7).frame(maxWidth: .infinity)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.bottom, 34)
        }
        .clipped()
    }

    /// Bought once by the first export, then free for good.
    private var priceNote: String {
        if template.owned == true { return "Owned · free to export" }
        if template.creditCost == 0 { return "Free" }
        return "\(template.creditCost) credits once on your first export · then free"
    }

    private var chips: some View {
        HStack(spacing: 8) {
            if let ms = template.version?.durationMs { chip("clock", "\(Int((Double(ms) / 1000).rounded()))s") }
            if let slots = template.version?.slotCount { chip("photo.on.rectangle", "\(slots) slots") }
            chip("music.note", "Music")
        }
    }

    private func chip(_ symbol: String, _ title: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.white.opacity(0.18), in: Capsule())
    }
}
