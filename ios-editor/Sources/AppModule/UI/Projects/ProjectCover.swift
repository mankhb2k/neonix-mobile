import UIKit
import PhotosUI
import SwiftUI

/// The picture a project shows in the Folder list (user 2026-10-16): the first frame of the project - the main lane's first clip at
/// the moment it starts (a video frame through `VideoFrameCache`, or a photo's square tile), the same picture the editor's cover cell
/// uses. Overlays and text are not part of it. Nil when the project has no picture yet (the row keeps its gradient).
enum ProjectCover {
    @MainActor
    static func firstFrame(of project: V2Project, side: CGFloat) async -> UIImage? {
        guard let mainOrder = primaryVideoLaneOrder(of: project.layers),
              let clip = project.layers.filter({ $0.order == mainOrder && isPushLane($0) }).min(by: { $0.timing.start < $1.timing.start }),
              let image = await frame(of: project, atTimelineMs: clip.timing.start, side: side)
        else { return nil }
        return image
    }

    @MainActor
    static func frame(of project: V2Project, atTimelineMs timeMs: Double, side: CGFloat) async -> UIImage? {
        guard let mainOrder = primaryVideoLaneOrder(of: project.layers) else { return nil }
        let clips = project.layers.filter { $0.order == mainOrder && isPushLane($0) }.sorted { $0.timing.start < $1.timing.start }
        guard let clip = clips.first(where: { timeMs >= $0.timing.start && timeMs < $0.timing.start + $0.timing.duration }) ?? clips.first,
              let assetId = clip.assetId,
              let asset = project.assets.first(where: { $0.id == assetId })
        else { return nil }
        switch (clip.payload, asset) {
        case (.video, .video(let video)):
            guard let url = bundledURL(filename: video.uri) else { return nil }
            let sourceMs = VideoTimeMapping(layer: clip)?.sourceMs(atTimelineMs: min(max(timeMs, clip.timing.start), clip.timing.start + clip.timing.duration)) ?? 0
            return await VideoFrameCache.shared.frame(assetId: assetId, url: url, atSeconds: sourceMs / 1000)
        case (.image, .image(let image)):
            guard let url = bundledURL(filename: image.uri) else { return nil }
            return await PhotoThumbnailCache.tile(for: url, side: side)
        default:
            return nil
        }
    }
}

/// Full-height cover editor. Frame selection is a private draft: scrubbing this filmstrip never moves the editor's playhead.
struct CoverEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let project: V2Project
    let initialCover: UIImage?
    let onSave: (UIImage) -> Void

    @State private var selectedTimeMs = 0.0
    @State private var selectedPhoto: UIImage?
    @State private var frameImage: UIImage?
    @State private var selectionRevision = 0
    @State private var showOriginal = false
    @State private var stageColorID = "black"
    @State private var photoItem: PhotosPickerItem?
    @State private var undoStack: [Draft] = []
    @State private var redoStack: [Draft] = []
    @State private var stripOffset: CGFloat?
    @State private var stripViewportWidth: CGFloat = 0
    @State private var dragStartOffset: CGFloat?
    @State private var dragStartDraft: Draft?

    private struct Draft {
        var timeMs: Double
        var photo: UIImage?
    }

    private let tileWidth: CGFloat = 56

    private var clips: [V2Layer] {
        guard let order = primaryVideoLaneOrder(of: project.layers) else { return [] }
        return project.layers.filter { $0.order == order && isPushLane($0) }.sorted { $0.timing.start < $1.timing.start }
    }

    private var durationMs: Double {
        clips.map { $0.timing.start + $0.timing.duration }.max() ?? 0
    }

    private var sampleTimes: [Double] {
        guard durationMs > 0 else { return [0] }
        let step = 1000.0
        var times = stride(from: 0.0, through: durationMs, by: step).map { $0 }
        let end = max(durationMs - 1, 0)
        if times.last.map({ end - $0 > step * 0.4 }) ?? true { times.append(end) }
        return times
    }

    private var visibleImage: UIImage? {
        if showOriginal { return frameImage ?? initialCover }
        return selectedPhoto ?? frameImage ?? initialCover
    }

    private var stageColor: Color {
        CoverCanvasColorPicker.options.first(where: { $0.id == stageColorID })?.color ?? .black
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    Spacer(minLength: 16)

                    stageColorPicker
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)

                    preview
                        .frame(maxWidth: .infinity)
                        .aspectRatio(project.composition.width / max(project.composition.height, 1), contentMode: .fit)
                        .frame(maxHeight: geometry.size.height * 0.46)
                        .padding(.horizontal, 28)

                    Spacer(minLength: 14)

                    editControls
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)

                    filmstrip(width: geometry.size.width)
                        .frame(height: 86)
                        .padding(.horizontal, 20)

                    Text("Slide to select")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 18)
                        .padding(.bottom, 24)

                    toolBar
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            }
            .navigationTitle("Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                        .accessibilityIdentifier("coverClose")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let image = selectedPhoto ?? frameImage ?? initialCover else { return }
                        onSave(renderCover(image))
                        dismiss()
                    }
                    .disabled(selectedPhoto == nil && frameImage == nil && initialCover == nil)
                    .accessibilityIdentifier("coverSave")
                }
            }
        }
        .tint(.accentColor)
        .background(Color(.systemBackground).ignoresSafeArea())
        .task(id: selectionRevision) {
            guard selectedPhoto == nil else { return }
            frameImage = await ProjectCover.frame(of: project, atTimelineMs: selectedTimeMs, side: 900)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                pushUndoSnapshot()
                selectedPhoto = image
                showOriginal = false
                selectionRevision += 1
                photoItem = nil
            }
        }
    }

    private var preview: some View {
        ZStack {
            stageColor
            if let visibleImage {
                Image(uiImage: visibleImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().tint(.accentColor)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .accessibilityIdentifier("coverPreview")
    }

    private var stageColorPicker: some View {
        CoverCanvasColorPicker(selectedID: $stageColorID)
    }

    private func renderCover(_ image: UIImage) -> UIImage {
        let size = CGSize(width: project.composition.width, height: project.composition.height)
        guard size.width > 0, size.height > 0, image.size.width > 0, image.size.height > 0 else { return image }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor(stageColor).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let scale = min(size.width / image.size.width, size.height / image.size.height)
            let fittedSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let rect = CGRect(x: (size.width - fittedSize.width) / 2, y: (size.height - fittedSize.height) / 2,
                              width: fittedSize.width, height: fittedSize.height)
            image.draw(in: rect)
        }
    }

    private var editControls: some View {
        HStack(spacing: 26) {
            Button(action: undo) {
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 48, height: 48)
                    .overlay(Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.primary))
            }
            .disabled(undoStack.isEmpty)
            .opacity(undoStack.isEmpty ? 0.45 : 1)
            .accessibilityIdentifier("coverUndo")

            Button(action: redo) {
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 48, height: 48)
                    .overlay(Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.primary))
            }
            .disabled(redoStack.isEmpty)
            .opacity(redoStack.isEmpty ? 0.45 : 1)
            .accessibilityIdentifier("coverRedo")

            Spacer()

            Button {
                showOriginal.toggle()
            } label: {
                Circle()
                    .fill(showOriginal ? Color.accentColor : Color(.secondarySystemBackground))
                    .frame(width: 48, height: 48)
                    .overlay(Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(showOriginal ? Color.white : Color.primary))
            }
            .accessibilityLabel("Compare original cover")
            .accessibilityIdentifier("coverCompare")
        }
        .buttonStyle(.plain)
        .transaction { $0.animation = nil }
        .frame(height: 32)
    }

    private func filmstrip(width: CGFloat) -> some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                VStack(spacing: 5) {
                    Circle()
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: 48, height: 48)
                        .overlay(Image(systemName: "plus")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color.primary))
                    Text("Upload")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 64, height: 76)
            }
            .accessibilityIdentifier("coverUpload")

            GeometryReader { proxy in
                let times = sampleTimes
                let totalWidth = CGFloat(times.count) * tileWidth
                let leftOffset = proxy.size.width / 2 - tileWidth / 2
                let rightOffset = min(leftOffset, proxy.size.width / 2 - totalWidth + tileWidth / 2)
                let offset = stripOffset ?? leftOffset

                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        ForEach(Array(times.enumerated()), id: \.offset) { index, time in
                            CoverFilmstripThumbnail(project: project, timeMs: time)
                                .frame(width: tileWidth, height: 72)
                                .overlay(alignment: .bottom) {
                                    if index == selectedIndex(in: times, width: proxy.size.width, offset: offset) {
                                        Rectangle().fill(Color.accentColor).frame(height: 3)
                                    }
                                }
                        }
                    }
                    .offset(x: offset)

                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: 2, height: 80)
                        .position(x: proxy.size.width / 2, y: 40)
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if dragStartOffset == nil {
                                dragStartOffset = stripOffset ?? leftOffset
                                dragStartDraft = Draft(timeMs: selectedTimeMs, photo: selectedPhoto)
                            }
                            guard let dragStartOffset else { return }
                            stripOffset = min(max(dragStartOffset + value.translation.width, rightOffset), leftOffset)
                            let index = selectedIndex(in: times, width: proxy.size.width, offset: stripOffset ?? leftOffset)
                            let nextTime = times[index]
                            if nextTime != selectedTimeMs || selectedPhoto != nil {
                                selectedTimeMs = nextTime
                                selectedPhoto = nil
                                showOriginal = false
                                selectionRevision += 1
                            }
                        }
                        .onEnded { _ in
                            if let dragStartDraft, dragStartDraft.timeMs != selectedTimeMs || dragStartDraft.photo != selectedPhoto {
                                undoStack.append(dragStartDraft)
                                redoStack.removeAll()
                            }
                            dragStartOffset = nil
                            dragStartDraft = nil
                        }
                )
                .onAppear {
                    stripViewportWidth = proxy.size.width
                    if stripOffset == nil { stripOffset = leftOffset }
                }
            }
            .accessibilityIdentifier("coverFilmstrip")
        }
        .frame(height: 78)
    }

    private var toolBar: some View {
        HStack(spacing: 0) {
            toolbarItem("Cover", symbol: "rectangle.on.rectangle", selected: true) {}
            toolbarItem("Text", symbol: "textformat", selected: false) {}.disabled(true)
            toolbarItem("Stickers", symbol: "face.smiling", selected: false) {}.disabled(true)
            PhotosPicker(selection: $photoItem, matching: .images) {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus").font(.system(size: 24, weight: .regular))
                    Text("Add photo").font(.caption2)
                }
                .foregroundStyle(.primary.opacity(0.8))
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("coverAddPhoto")
        }
        .padding(.top, 18)
        .padding(.bottom, 24)
        .background(Color(.secondarySystemBackground))
    }

    private func toolbarItem(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 24, weight: .medium))
                Text(title).font(.system(size: 12, weight: .medium))
                Capsule().fill(selected ? Color.accentColor : .clear).frame(width: 34, height: 3)
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func selectedIndex(in times: [Double], width: CGFloat, offset: CGFloat) -> Int {
        guard !times.isEmpty else { return 0 }
        return min(max(Int(((width / 2 - offset) / tileWidth).rounded()), 0), times.count - 1)
    }

    private func pushUndoSnapshot() {
        undoStack.append(Draft(timeMs: selectedTimeMs, photo: selectedPhoto))
        redoStack.removeAll()
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(Draft(timeMs: selectedTimeMs, photo: selectedPhoto))
        restore(previous)
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(Draft(timeMs: selectedTimeMs, photo: selectedPhoto))
        restore(next)
    }

    private func restore(_ draft: Draft) {
        selectedTimeMs = draft.timeMs
        selectedPhoto = draft.photo
        showOriginal = false
        selectionRevision += 1
        if let index = sampleTimes.enumerated().min(by: { abs($0.element - draft.timeMs) < abs($1.element - draft.timeMs) })?.offset {
            let leftOffset = stripViewportWidth / 2 - tileWidth / 2
            let rightOffset = min(leftOffset, stripViewportWidth / 2 - CGFloat(sampleTimes.count) * tileWidth + tileWidth / 2)
            stripOffset = min(max(stripViewportWidth / 2 - (CGFloat(index) * tileWidth + tileWidth / 2), rightOffset), leftOffset)
        }
    }
}

private struct CoverCanvasColorPicker: View {
    struct Option: Identifiable {
        let id: String
        let color: Color
    }

    static let options = [
        Option(id: "black", color: .black),
        Option(id: "white", color: .white),
        Option(id: "gray", color: Color(.systemGray3)),
        Option(id: "red", color: .red),
        Option(id: "orange", color: .orange),
        Option(id: "yellow", color: .yellow),
        Option(id: "green", color: .green),
        Option(id: "blue", color: .blue),
        Option(id: "purple", color: .purple)
    ]

    @Binding var selectedID: String

    var body: some View {
        HStack(spacing: 12) {
            Text("Canvas")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(Self.options) { option in
                        Button {
                            selectedID = option.id
                        } label: {
                            Circle()
                                .fill(option.color)
                                .frame(width: 20, height: 20)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(option.id == "white" ? 0.2 : 0.08), lineWidth: 1))
                                .padding(3)
                                .overlay(Circle().strokeBorder(selectedID == option.id ? Color.accentColor : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(option.id.capitalized) canvas color")
                        .accessibilityAddTraits(selectedID == option.id ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(height: 34)
        .accessibilityIdentifier("coverCanvasColorPicker")
    }
}

private struct CoverFilmstripThumbnail: View {
    let project: V2Project
    let timeMs: Double
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color(.tertiarySystemBackground)
            }
        }
        .clipped()
        .task(id: timeMs) {
            image = await ProjectCover.frame(of: project, atTimelineMs: timeMs, side: 100)
        }
    }
}
