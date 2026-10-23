import AVFoundation
import ImageIO
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers

/// Sandbox for trying UI before it goes into the editor: each experiment is self-contained and cannot change projects.
struct DesignLabView: View {
    @State private var showingTransform = false
    @State private var showingAdjust = false
    @State private var showingFilter = false
    @State private var showingKeyframe = false
    @State private var showingText = false
    @State private var showingAudioWave = false
    @State private var showingAudioFade = false
    @State private var showingSound = false
    @State private var showingRecorder = false
    @State private var showingCrop = false
    @State private var showingMask = false
    @State private var showingChromaKey = false
    @State private var showingExportButtons = false

    var body: some View {
        List {
            Section {
                Button { showingTransform = true } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Transform controls").font(.body.weight(.semibold)).foregroundColor(.primary)
                        Text("Round buttons; tapping one opens a Curves-style sheet with the ruler and the buttons inside. Drag, pinch and twist the layer too.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
                .accessibilityIdentifier("lab-transform")

                Button { showingAdjust = true } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Adjust controls").font(.body.weight(.semibold)).foregroundColor(.primary)
                        Text("13 controls on a live photo: a scrolling row vs Light / Color / Detail groups, both in the sheet. Hold the photo to compare.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
                .accessibilityIdentifier("lab-adjust")

                Button { showingFilter = true } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Filter picker").font(.body.weight(.semibold)).foregroundColor(.primary)
                        Text("16 fake filters on a live photo with an Intensity ruler: a 4-column grid in a fixed sheet, the same with a pull-up detent, or one row of thumbnails.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
                .accessibilityIdentifier("lab-filter")

                Button { showingKeyframe = true } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Keyframes & graphs").font(.body.weight(.semibold)).foregroundColor(.primary)
                        Text("Three keyframes on a moving layer; pick each segment's graph from a row of curves, a grid sheet or a big live curve, or edit it with two handles.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
                .accessibilityIdentifier("lab-keyframe")

                Button { showingText = true } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Text picker").font(.body.weight(.semibold)).foregroundColor(.primary)
                        Text("Two tabs, Font and Style, on a live photo; the text field heads the sheet (CapCut) or sits at the bottom like Filter's Intensity bar.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
                .accessibilityIdentifier("lab-text")

                Button { showingAudioWave = true } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Audio waveform").font(.body.weight(.semibold)).foregroundColor(.primary)
                        Text("The sound-library peak waveform (hairlines as tall as the loudest sample), top half only, against the smooth curve the timeline draws now and the mirrored original; shown big and on lane clips at any zoom.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
                .accessibilityIdentifier("lab-audiowave")

                Button { showingAudioFade = true } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Audio fade").font(.body.weight(.semibold)).foregroundColor(.primary)
                        Text("How a clip shows its fade in / out: the envelope curve, the waveform shrinking along it, or both with the faded part darkened; dark or light clip body and a volume badge.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
                .accessibilityIdentifier("lab-audiofade")

                Button { showingSound = true } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sound FX picker").font(.body.weight(.semibold)).foregroundColor(.primary)
                        Text("The 20 starter sounds with pretend playback and download: rows with a play button, rows with a waveform that fills while it plays, or a grid with a Use bar; Use puts the sound at the playhead.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
                .accessibilityIdentifier("lab-sound")

                Button { showingRecorder = true } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recorder popup").font(.body.weight(.semibold)).foregroundColor(.primary)
                        Text("After iPhone's Voice Memos: name and running time, a red waveform scrolling in while it records, one big round button; stop turns it into a review with Delete, Play and Add.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
                .accessibilityIdentifier("lab-recorder")

                Button { showingCrop = true } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Crop").font(.body.weight(.semibold)).foregroundColor(.primary)
                        Text("After CapCut's Resize: a working crop frame (corners, move, aspect lock, Rotate, Flip) with the controls as a full-screen editor, the editor's sheet, or an iPhone Photos style.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
                .accessibilityIdentifier("lab-crop")

                Button { showingMask = true } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mask").font(.body.weight(.semibold)).foregroundColor(.primary)
                        Text("After CapCut's Mask: Horizontal, Mirror, Circle, Rectangle on a live photo with handles on the stage; the controls as CapCut's own flow, the editor's sheet, or a lighter sheet with sliders.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
                .accessibilityIdentifier("lab-mask")

                Button { showingChromaKey = true } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Chroma key").font(.body.weight(.semibold)).foregroundColor(.primary)
                        Text("Pick a background color on a sample or your own photo/video frame; adjust the key live and inspect transparency.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
                .accessibilityIdentifier("lab-chroma-key")

                Button { showingExportButtons = true } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Export buttons").font(.body.weight(.semibold)).foregroundColor(.primary)
                        Text("Compare the current Quality and Export controls with native iOS bordered, prominent and glass button styles.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
                .accessibilityIdentifier("lab-export-buttons")
            } header: {
                Text("Experiments")
            } footer: {
                Text("Experiments don't change projects or contact the server.")
            }
        }
        .navigationTitle("Design Lab")
        .fullScreenCover(isPresented: $showingTransform) { TransformLabView() }
        .fullScreenCover(isPresented: $showingAdjust) { AdjustLabView() }
        .fullScreenCover(isPresented: $showingFilter) { FilterLabView() }
        .fullScreenCover(isPresented: $showingKeyframe) { KeyframeLabView() }
        .fullScreenCover(isPresented: $showingText) { TextLabView() }
        .fullScreenCover(isPresented: $showingAudioWave) { AudioWaveLabView() }
        .fullScreenCover(isPresented: $showingAudioFade) { AudioFadeLabView() }
        .fullScreenCover(isPresented: $showingSound) { SoundLabView() }
        .fullScreenCover(isPresented: $showingRecorder) { RecorderLabView() }
        .fullScreenCover(isPresented: $showingCrop) { CropLabView() }
        .fullScreenCover(isPresented: $showingMask) { MaskLabView() }
        .fullScreenCover(isPresented: $showingChromaKey) { ChromaKeyLabView() }
        .fullScreenCover(isPresented: $showingExportButtons) { ExportButtonsLabView() }
    }
}

/// A working color-key experiment. It renders one picture at a time through Core Image; for video, the time slider
/// decodes a source frame. Nothing in this view edits a project or introduces a V2 filter primitive.
private struct ChromaKeyLabView: View {
    @Environment(\.dismiss) private var dismiss

    fileprivate enum PickerStyle: String, CaseIterable, Identifiable {
        case halo = "Halo"
        case lens = "Lens"
        case reticle = "Reticle"
        var id: String { rawValue }
    }

    @State private var settings = LabChromaSettings()
    @State private var method: LabChromaMethod = .matrix
    @State private var source: CGImage?
    @State private var rendered: CGImage?
    @State private var sourceVersion = 0
    @State private var videoURL: URL?
    @State private var videoDuration = 0.0
    @State private var videoTime = 0.0
    @State private var importedVideoURL: URL?
    @State private var sourceName = "Sample green screen"
    @State private var showingImporter = false
    @State private var isPicking = false
    @State private var pickedPoint: CGPoint?
    @State private var pickedColor: LabKeyColor?
    @State private var pickerStyle: PickerStyle = .halo
    @State private var pickerDragOrigin: CGPoint?
    @State private var didMovePicker = false
    @State private var showOriginal = false
    @State private var showCheckerboard = true
    @State private var isRendering = false
    @State private var lastRenderMs: Double?
    @State private var errorMessage: String?

    private struct RenderRequest: Equatable {
        let sourceVersion: Int
        let settings: LabChromaSettings
        let method: LabChromaMethod
    }

    private var renderRequest: RenderRequest { RenderRequest(sourceVersion: sourceVersion, settings: settings, method: method) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            HStack(spacing: 10) {
                Button("Sample") { useSample() }.accessibilityIdentifier("chromaSample")
                Button("Choose file") { showingImporter = true }.accessibilityIdentifier("chromaImport")
                Spacer()
                Toggle("Grid", isOn: $showCheckerboard).labelsHidden().accessibilityLabel("Checkerboard")
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 20).padding(.bottom, 8)

            let stagedVideos = stagedVideoNames
            if !stagedVideos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(stagedVideos, id: \.self) { name in
                            Button(name.replacingOccurrences(of: ".MOV", with: "")) {
                                Task { await loadStagedVideo(named: name) }
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("chromaStaged-\(name)")
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 8)
            }

            Text(sourceName).font(.caption).foregroundColor(.secondary).lineLimit(1).padding(.horizontal, 20)
            stage.padding(.horizontal, 30).padding(.vertical, 8).frame(maxHeight: .infinity)
            if videoURL != nil {
                HStack {
                    Text(String(format: "%.1f s", videoTime)).font(.caption.monospacedDigit()).frame(width: 46)
                        .accessibilityIdentifier("chromaTimeReadout")
                    Slider(value: $videoTime, in: 0...max(videoDuration - 0.05, 0.1))
                        .accessibilityIdentifier("chromaVideoTime")
                    Text(String(format: "%.1f s", videoDuration)).font(.caption.monospacedDigit()).frame(width: 46)
                }
                .padding(.horizontal, 20)
                HStack(spacing: 12) {
                    Text("Sample").font(.caption).foregroundColor(.secondary)
                    ForEach([3.0, 10.0, 20.0, 30.0, 40.0], id: \.self) { seconds in
                        Button("\(Int(seconds))s") { videoTime = seconds }
                            .font(.caption.monospacedDigit())
                            .accessibilityIdentifier("chromaSeek-\(Int(seconds))")
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 4)
            }
            controls
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .task { if source == nil { useSample() } }
        .task(id: renderRequest) { await renderCurrentFrame() }
        .task(id: "\(videoURL?.lastPathComponent ?? "")-\(Int(videoTime * 10))") { await loadVideoFrame() }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.image, .movie]) { result in
            if case .success(let url) = result { Task { await importFile(url) } }
        }
        .alert("Couldn't open media", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .onDisappear { removeImportedVideo() }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .accessibilityIdentifier("chromaClose")
            Spacer()
            Text("Chroma key lab").font(.headline)
            Spacer()
            Button("Reset") { settings = LabChromaSettings(); showOriginal = false; isPicking = false }
                .frame(minWidth: 44).accessibilityIdentifier("chromaReset")
        }
        .padding(.horizontal, 8)
    }

    private var stage: some View {
        GeometryReader { proxy in
            if let source {
                let ratio = CGFloat(source.width) / CGFloat(source.height)
                let fit = ratio > proxy.size.width / proxy.size.height
                    ? CGSize(width: proxy.size.width, height: proxy.size.width / ratio)
                    : CGSize(width: proxy.size.height * ratio, height: proxy.size.height)
                ZStack {
                    if showCheckerboard { Checkerboard() } else { Color.black }
                    Image(decorative: isPicking || showOriginal ? source : (rendered ?? source), scale: 1)
                        .resizable().frame(width: fit.width, height: fit.height)
                    if isPicking {
                        let point = pickedPoint ?? CGPoint(x: 0.5, y: 0.5)
                        ChromaPickerMark(
                            style: pickerStyle,
                            sampledColor: pickedColor.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
                        )
                            .frame(width: 88, height: 88)
                            .position(x: point.x * fit.width, y: point.y * fit.height)
                    }
                }
                .frame(width: fit.width, height: fit.height)
                .contentShape(Rectangle())
                .gesture(pickGesture(size: fit), including: isPicking ? .all : .none)
                .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .bottom) {
            if isPicking {
                Text("Drag to select color").font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.black.opacity(0.75), in: Capsule()).foregroundColor(.white).padding(10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("chromaStage")
        .accessibilityValue("Frame \(sourceVersion)")
    }

    private func pickGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if pickerDragOrigin == nil {
                    pickerDragOrigin = value.startLocation
                    didMovePicker = false
                }
                pickedPoint = CGPoint(x: min(max(value.location.x / size.width, 0), 1),
                                      y: min(max(value.location.y / size.height, 0), 1))
                if let pickerDragOrigin,
                   hypot(value.location.x - pickerDragOrigin.x, value.location.y - pickerDragOrigin.y) >= 3 {
                    didMovePicker = true
                    sample(at: value.location, size: size)
                }
            }
            .onEnded { value in
                if didMovePicker {
                    sample(at: value.location, size: size)
                    if let pickedColor { settings.key = pickedColor }
                } else {
                    pickedPoint = nil
                    pickedColor = nil
                }
                pickerDragOrigin = nil
                didMovePicker = false
            }
    }

    private func sample(at location: CGPoint, size: CGSize) {
        guard let source, size.width > 0, size.height > 0 else { return }
        let point = CGPoint(x: min(max(location.x / size.width, 0), 1), y: min(max(location.y / size.height, 0), 1))
        pickedPoint = point
        pickedColor = LabChromaProcessor.color(in: source, at: point)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Chroma key").font(.headline)
                Spacer()
                if let lastRenderMs { Text(String(format: "%.0f ms/frame", lastRenderMs)).font(.caption.monospacedDigit()).foregroundColor(.secondary) }
                if isRendering { ProgressView().controlSize(.mini).accessibilityIdentifier("chromaRendering") }
                Button(showOriginal ? "Keyed" : "Original") { showOriginal.toggle() }
                    .font(.caption).accessibilityIdentifier("chromaCompare")
            }
            Picker("Method", selection: $method) {
                ForEach(LabChromaMethod.allCases) { item in Text(item.rawValue).tag(item) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("chromaMethod")
            HStack(spacing: 8) {
                Text("Picker design").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Picker("Picker design", selection: $pickerStyle) {
                    ForEach(PickerStyle.allCases) { style in Text(style.rawValue).tag(style) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 230)
                .accessibilityIdentifier("chromaPickerDesign")
            }
            HStack(spacing: 10) {
                Button {
                    isPicking.toggle()
                    pickedColor = nil
                    pickedPoint = nil
                } label: {
                    Image(systemName: "scope").font(.title3).frame(width: 46, height: 46)
                        .background(isPicking ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemBackground), in: Circle())
                }
                .accessibilityIdentifier("chromaPicker")
                Circle().fill(Color(red: settings.key.red, green: settings.key.green, blue: settings.key.blue))
                    .frame(width: 22, height: 22).overlay(Circle().strokeBorder(.secondary, lineWidth: 1))
                Text(settings.key.hex).font(.caption.monospaced())
                Spacer()
                Text(isPicking ? "Pick on the picture" : "Color picker").font(.caption).foregroundColor(.secondary)
            }
            slider("Intensity", value: $settings.intensity, id: "chromaIntensity")
            slider("Shadow", value: $settings.shadow, id: "chromaShadow").disabled(method != .colorCube)
            slider("Feather edge", value: $settings.feather, id: "chromaFeather")
            slider("Clean up edge", value: $settings.cleanup, id: "chromaCleanup").disabled(method != .colorCube)
            Text(method == .matrix
                 ? "Current V2 uses one color matrix. Shadow and edge cleanup need operations it cannot express here."
                 : method == .v2Graph
                    ? "V2 graph composes color matrix and alpha transfer. Shadow matching and mask contraction are not available in this graph."
                    : "Color cube includes darker screen colors and can contract the matte. Video is inspected one frame at a time.")
                .font(.caption2).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
    }

    private func slider(_ title: String, value: Binding<Double>, id: String) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.subheadline).frame(width: 112, alignment: .leading)
            Slider(value: value, in: 0...1).accessibilityIdentifier(id)
            Text(String(format: "%.0f", value.wrappedValue * 100)).font(.caption.monospacedDigit()).frame(width: 28, alignment: .trailing)
                .accessibilityIdentifier("\(id)Value")
        }
    }

    private func useSample() {
        videoURL = nil
        removeImportedVideo()
        sourceName = "Sample green screen"
        settings = LabChromaSettings()
        setSource(LabChromaProcessor.sampleImage())
    }

    private var stagedVideoNames: [String] {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedMedia", isDirectory: true)
        return ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { ["mov", "mp4", "m4v"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
            .sorted()
    }

    private func loadStagedVideo(named name: String) async {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedMedia", isDirectory: true)
            .appendingPathComponent(name)
        await importFile(url)
    }

    private func setSource(_ image: CGImage?) {
        source = image
        rendered = nil
        lastRenderMs = nil
        sourceVersion += 1
    }

    private func renderCurrentFrame() async {
        guard let source else { rendered = nil; return }
        // Slider ticks arrive faster than a still-frame render; coalesce them before starting GPU work.
        try? await Task.sleep(for: .milliseconds(25))
        guard !Task.isCancelled else { return }
        let currentSettings = settings
        let currentMethod = method
        isRendering = true
        let (result, elapsed) = await Task.detached(priority: .userInitiated) {
            let start = CACurrentMediaTime()
            let image = LabChromaProcessor.render(source, settings: currentSettings, method: currentMethod)
            return (image, (CACurrentMediaTime() - start) * 1000)
        }.value
        guard !Task.isCancelled else { return }
        rendered = result
        lastRenderMs = elapsed
        isRendering = false
    }

    private func importFile(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true {
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                             kCGImageSourceCreateThumbnailWithTransform: true,
                                             kCGImageSourceThumbnailMaxPixelSize: 1600]
            guard let sourceRef = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(sourceRef, 0, options as CFDictionary) else {
                errorMessage = "This image couldn't be decoded."
                return
            }
            videoURL = nil
            removeImportedVideo()
            sourceName = url.lastPathComponent
            setSource(image)
        } else {
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("chroma-lab-\(UUID().uuidString)").appendingPathExtension(url.pathExtension)
            do { try FileManager.default.copyItem(at: url, to: copy) }
            catch { errorMessage = error.localizedDescription; return }
            let asset = AVURLAsset(url: copy)
            guard let duration = try? await asset.load(.duration), duration.seconds.isFinite, duration.seconds > 0 else {
                try? FileManager.default.removeItem(at: copy)
                errorMessage = "This video has no readable frames."
                return
            }
            removeImportedVideo()
            importedVideoURL = copy
            videoDuration = duration.seconds
            videoTime = 0
            videoURL = copy
            sourceName = url.lastPathComponent
            setSource(nil)
        }
    }

    private func loadVideoFrame() async {
        guard let videoURL else { return }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1600, height: 1600)
        let time = CMTime(seconds: max(0, videoTime), preferredTimescale: 600)
        guard let frame = try? await generator.image(at: time), !Task.isCancelled else { return }
        setSource(frame.image)
    }

    private func removeImportedVideo() {
        if let importedVideoURL { try? FileManager.default.removeItem(at: importedVideoURL) }
        importedVideoURL = nil
    }
}

/// Three lab-only alternatives for the chroma sampling loupe. None displays a sampled color until the user moves.
private struct ChromaPickerMark: View {
    let style: ChromaKeyLabView.PickerStyle
    let sampledColor: Color?

    private let teal = Color.accentColor

    var body: some View {
        ZStack {
            switch style {
            case .halo:
                Circle().fill(.white.opacity(0.94))
                Circle().inset(by: 5).stroke(teal, lineWidth: 3)
                Circle().inset(by: 12).fill(sampledColor ?? .clear)
                Circle().inset(by: 12).stroke(.white, lineWidth: 1.5)
            case .lens:
                if let sampledColor {
                    Circle().fill(sampledColor)
                    Circle().inset(by: 10).fill(.white.opacity(0.92))
                    Circle().inset(by: 7).stroke(sampledColor.opacity(0.56), lineWidth: 3)
                } else {
                    CheckerboardPickerRing()
                    Circle().inset(by: 10).fill(.white.opacity(0.92))
                }
            case .reticle:
                Circle().fill(.white.opacity(0.92))
                Circle().inset(by: 5).stroke(teal.opacity(0.22), lineWidth: 1)
                ReticleArcs().stroke(teal, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .padding(7)
                Circle().fill(sampledColor ?? .clear).frame(width: 9, height: 9)
                Circle().stroke(.white, lineWidth: 1.5).frame(width: 9, height: 9)
            }
        }
        .overlay {
            if style == .halo {
                Rectangle().fill(.primary.opacity(0.65)).frame(width: 1, height: 14)
                Rectangle().fill(.primary.opacity(0.65)).frame(width: 14, height: 1)
            } else if style == .lens {
                ZStack {
                    Circle().fill(sampledColor ?? .white)
                    Rectangle().fill(.black.opacity(0.78)).frame(width: 1.5, height: 13)
                    Rectangle().fill(.black.opacity(0.78)).frame(width: 13, height: 1.5)
                }
                .frame(width: 10, height: 10)
            } else {
                EmptyView()
            }
        }
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.2), radius: 7, y: 2)
        .accessibilityHidden(true)
    }
}

private struct CheckerboardPickerRing: View {
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 7
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let innerRadius = size.width * 0.38
            let outerRadius = size.width * 0.5
            for row in 0..<Int(ceil(size.height / tile)) {
                for column in 0..<Int(ceil(size.width / tile)) {
                    let rect = CGRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile, width: tile, height: tile)
                    let radius = hypot(rect.midX - center.x, rect.midY - center.y)
                    guard radius >= innerRadius, radius <= outerRadius else { continue }
                    let shade: Double = (row + column).isMultiple(of: 2) ? 0.84 : 0.96
                    context.fill(Path(rect), with: .color(Color(white: shade)))
                }
            }
        }
        .clipShape(Circle())
    }
}

private struct ReticleArcs: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        for start in [CGFloat(-40), CGFloat(50), CGFloat(140), CGFloat(230)] {
            path.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(start + 50), clockwise: false)
        }
        return path
    }
}
