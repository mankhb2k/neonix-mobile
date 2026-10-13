import SwiftUI

/// Design lab for keyframes + the graph (easing) between them. The question is how the user picks the graph of a
/// segment: CapCut's single row of curve tiles with an Edit tile (A), a grid sheet with family chips and a pull-up
/// detent (B), or a big live curve with In / Out / In Out + family pickers (C). All three can open the same full-screen
/// graph editor (two draggable handles). The mock stage replays the three keyframes in a loop with each segment's graph,
/// so a choice is judged by how it moves, not just by its thumbnail.
struct KeyframeLabView: View {
    @Environment(\.dismiss) private var dismiss

    enum Variant: String, CaseIterable, Identifiable {
        case row = "A Row", grid = "B Grid+", big = "C Big curve"
        var id: String { rawValue }

        var summary: String {
            switch self {
            case .row: return "CapCut style: one row of curve tiles, the Edit tile opens the graph editor"
            case .grid: return "Family chips + 4-column grid of curves, pull the sheet up to see them all"
            case .big: return "A large live curve with a moving dot; pick family and In / Out / In Out under it"
            }
        }
    }

    @State private var variant: Variant = .row
    @State private var easings: [LabEasing] = [.original, .original]   // segment 0 = keyframe 1 -> 2, segment 1 = 2 -> 3
    @State private var active = 0
    @State private var sheetOpen = false
    @State private var editing = false
    @State private var family: LabEasingFamily? = .basic

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Picker("Layout", selection: $variant) {
                ForEach(Variant.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).padding(.horizontal)
            .accessibilityIdentifier("keyframeVariantPicker")
            Text(variant.summary).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal).padding(.top, 4)

            KeyframeStage(easings: easings, active: active)
                .padding(.horizontal, 60).padding(.vertical, 8)
                .frame(maxHeight: .infinity)

            keyframeStrip
            mockSelectionRow
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .onChange(of: variant) { _, _ in sheetOpen = false }
        .sheet(isPresented: $sheetOpen) { graphSheet }
        .fullScreenCover(isPresented: $editing) {
            GraphEditorView(bezier: easings[active].bezier) { easings[active] = .custom($0) }
        }
    }

    // MARK: Top, strip, row

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.title3).frame(width: 44, height: 44) }
                .accessibilityIdentifier("keyframeClose")
            Spacer()
            Text("Keyframe lab").font(.headline)
            Spacer()
            Menu {
                Button("Reset both graphs", role: .destructive) { easings = [.original, .original] }
            } label: { Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44) }
        }
        .padding(.horizontal, 8)
    }

    /// The clip's keyframe track: three diamonds, and between them one block per segment that shows its graph's name
    /// (CapCut's "Graphs" label). Tap a block to choose which segment the sheet edits.
    private var keyframeStrip: some View {
        HStack(spacing: 0) {
            diamond
            ForEach(0..<2, id: \.self) { index in
                Button { active = index } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.xyaxis.line").font(.caption2)
                        Text(easings[index].name).font(.caption.weight(.semibold)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(index == active ? Color.accentColor.opacity(0.25) : Color(.tertiarySystemBackground))
                    .overlay(Rectangle().strokeBorder(index == active ? Color.accentColor : .clear, lineWidth: 2))
                    .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("keyframeSegment-\(index)")
                diamond
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var diamond: some View {
        Image(systemName: "diamond.fill").font(.caption).foregroundColor(.accentColor).frame(width: 22)
    }

    private var mockSelectionRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left.2").font(.body.weight(.semibold)).frame(width: 44, height: 44)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Divider().frame(height: 28)
            ForEach([("scissors", "Split"), ("diamond", "Keyframe"), ("chart.xyaxis.line", "Graphs"), ("trash", "Delete")], id: \.1) { symbol, title in
                Button { if title == "Graphs" { sheetOpen = true } } label: {
                    VStack(spacing: 4) {
                        Image(systemName: symbol).font(.title3)
                        Text(title).font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(title == "Split" ? .secondary : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("keyframeAction-\(title)")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: Sheet

    private var graphSheet: some View {
        NavigationStack {
            VStack(spacing: 10) {
                switch variant {
                case .row: tileRow
                case .grid: familyChips(includeAll: true); grid
                case .big: bigCurve
                }
            }
            .padding(.top, 4)
            .navigationTitle("Graphs · segment \(active + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { easings[active] = .original }
                        .disabled(easings[active] == .original).accessibilityIdentifier("graphReset")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { sheetOpen = false }.accessibilityIdentifier("graphDone")
                }
            }
        }
        .presentationDetents(detents)
        .presentationDragIndicator(variant == .grid ? .visible : .hidden)
        .presentationBackgroundInteraction(.enabled)
    }

    private var detents: Set<PresentationDetent> {
        switch variant {
        case .row: return [.height(250)]
        case .grid: return [.height(340), .large]
        case .big: return [.height(400)]
        }
    }

    private var tileRow: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    tile(.original)
                    ForEach(LabEasing.catalogue) { tile($0) }
                    editTile
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
            .accessibilityIdentifier("graphRow")
            Spacer(minLength: 0)
        }
    }

    private func familyChips(includeAll: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LabEasingFamily.allCases) { item in
                    let on = family == item
                    Button { family = item } label: {
                        Text(item.rawValue).font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(on ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                            .foregroundColor(on ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("graphChip-\(item.rawValue)")
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                tile(.original)
                ForEach(LabEasing.list(in: family ?? .basic)) { tile($0) }
                editTile
            }
            .padding(.horizontal, 16).padding(.bottom, 12)
        }
        .accessibilityIdentifier("graphGrid")
    }

    private func tile(_ easing: LabEasing) -> some View {
        let on = easings[active].id == easing.id
        return Button { easings[active] = easing } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.tertiarySystemBackground))
                    if easing == .original {
                        Image(systemName: "nosign").font(.title2).foregroundColor(.secondary)
                    } else {
                        LabCurveShape(bezier: easing.bezier).stroke(on ? Color.accentColor : Color.primary, lineWidth: 2).padding(10)
                    }
                }
                .frame(width: 64, height: 64)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2.5))
                Text(easing.name).font(.caption2).foregroundColor(on ? .accentColor : .secondary).lineLimit(1)
            }
            .frame(width: variant == .row ? 72 : nil)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("graphTile-\(easing.id)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var editTile: some View {
        Button { sheetOpen = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { editing = true } } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor)
                    Image(systemName: "pencil").font(.title2).foregroundColor(.white)
                }
                .frame(width: 64, height: 64)
                Text("Edit").font(.caption2).foregroundColor(.accentColor)
            }
            .frame(width: variant == .row ? 72 : nil)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("graphEdit")
    }

    // MARK: Variant C

    private var bigCurve: some View {
        VStack(spacing: 12) {
            BigCurve(bezier: easings[active].bezier, isOriginal: easings[active] == .original)
                .frame(height: 150).padding(.horizontal, 16)
            familyChips(includeAll: false)
            HStack(spacing: 8) {
                ForEach(LabEasing.list(in: family ?? .basic)) { easing in
                    let on = easings[active].id == easing.id
                    Button { easings[active] = easing } label: {
                        Text(easing.name.replacingOccurrences(of: (family ?? .basic).rawValue + " ", with: ""))
                            .font(.subheadline.weight(.medium)).lineLimit(1).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(on ? Color.accentColor : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .foregroundColor(on ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("graphTile-\(easing.id)")
                }
            }
            .padding(.horizontal, 16)
            Button { sheetOpen = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { editing = true } } label: {
                Label("Edit graph", systemImage: "pencil").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).padding(.horizontal, 16)
            .accessibilityIdentifier("graphEdit")
        }
    }
}

// MARK: - Stage

/// A 9:16 stand-in canvas: one layer flies through three keyframes in a loop, each segment with its own graph.
private struct KeyframeStage: View {
    let easings: [LabEasing]
    let active: Int

    private let points = [CGPoint(x: 0.22, y: 0.5), CGPoint(x: 0.78, y: 0.3), CGPoint(x: 0.3, y: 0.1)]   // kept in the top half: the sheet covers the rest
    private let segmentSeconds = 1.3
    private let pauseSeconds = 0.6

    var body: some View {
        SwiftUI.TimelineView(.animation) { context in
            GeometryReader { proxy in
                let size = proxy.size
                let position = layerPosition(at: context.date.timeIntervalSinceReferenceDate)
                ZStack {
                    Color(.tertiarySystemBackground)
                    Path { path in
                        for (i, p) in points.enumerated() {
                            let point = CGPoint(x: p.x * size.width, y: p.y * size.height)
                            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                        }
                    }
                    .stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    ForEach(0..<3, id: \.self) { i in
                        Image(systemName: "diamond.fill").font(.caption).foregroundColor(.accentColor)
                            .position(x: points[i].x * size.width, y: points[i].y * size.height)
                    }
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: size.width * 0.26, height: size.width * 0.26)
                        .position(x: position.x * size.width, y: position.y * size.height)
                }
            }
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("keyframeStage")
    }

    private func layerPosition(at time: TimeInterval) -> CGPoint {
        let cycle = segmentSeconds * 2 + pauseSeconds
        let local = time.truncatingRemainder(dividingBy: cycle)
        let segment = min(Int(local / segmentSeconds), 2)
        if segment >= 2 { return points[2] }
        let t = (local - Double(segment) * segmentSeconds) / segmentSeconds
        let eased = easings[segment].bezier.value(at: t)
        let a = points[segment], b = points[segment + 1]
        return CGPoint(x: a.x + (b.x - a.x) * eased, y: a.y + (b.y - a.y) * eased)
    }
}

// MARK: - Big live curve (variant C)

/// The curve large, with a dot that runs along it (x = time, y = eased progress) in a loop.
private struct BigCurve: View {
    let bezier: LabBezier
    let isOriginal: Bool

    var body: some View {
        SwiftUI.TimelineView(.animation) { context in
            let t = (context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.2)) / 1.6
            let progress = min(t, 1)
            GeometryReader { proxy in
                let range = -0.3...1.3
                let size = proxy.size
                let y = (bezier.value(at: progress) - range.lowerBound) / (range.upperBound - range.lowerBound)
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.tertiarySystemBackground))
                    ForEach([0.0, 1.0], id: \.self) { level in
                        let ly = size.height * (1 - (level - range.lowerBound) / (range.upperBound - range.lowerBound))
                        Path { p in p.move(to: CGPoint(x: 0, y: ly)); p.addLine(to: CGPoint(x: size.width, y: ly)) }
                            .stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    LabCurveShape(bezier: bezier, range: range).stroke(Color.accentColor, lineWidth: 3)
                    Circle().fill(Color.accentColor).frame(width: 14, height: 14)
                        .position(x: progress * size.width, y: size.height * (1 - y))
                }
            }
        }
        .accessibilityIdentifier("bigCurve")
    }
}

// MARK: - Graph editor

/// Full-screen editor for one segment's graph: drag the two handles (CapCut's "Edit"). Reset goes back to Linear.
struct GraphEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var bezier: LabBezier
    let onDone: (LabBezier) -> Void

    init(bezier: LabBezier, onDone: @escaping (LabBezier) -> Void) {
        _bezier = State(initialValue: bezier)
        self.onDone = onDone
    }

    private let range = -0.7...1.7

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button("Reset") { bezier = .linear }.accessibilityIdentifier("graphEditorReset")
                Spacer()
                Text("Edit graph").font(.headline)
                Spacer()
                Button { onDone(bezier); dismiss() } label: { Image(systemName: "checkmark").font(.title3.weight(.semibold)) }
                    .accessibilityIdentifier("graphEditorDone")
            }
            .padding(.horizontal, 20).padding(.top, 12)

            GeometryReader { proxy in
                let size = proxy.size
                let point = { (x: Double, y: Double) -> CGPoint in
                    CGPoint(x: x * size.width, y: size.height * (1 - (y - range.lowerBound) / (range.upperBound - range.lowerBound)))
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.tertiarySystemBackground))
                    ForEach([0.0, 1.0], id: \.self) { level in
                        Path { p in p.move(to: point(0, level)); p.addLine(to: point(1, level)) }
                            .stroke(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    }
                    Path { p in
                        p.move(to: point(0, 0)); p.addLine(to: point(bezier.x1, bezier.y1))
                        p.move(to: point(1, 1)); p.addLine(to: point(bezier.x2, bezier.y2))
                    }
                    .stroke(Color.secondary, lineWidth: 1.5)
                    LabCurveShape(bezier: bezier, range: range).stroke(Color.accentColor, lineWidth: 3)
                    handle(point(bezier.x1, bezier.y1)) { loc in
                        bezier.x1 = min(max(Double(loc.x / size.width), 0), 1)
                        bezier.y1 = clampY(loc.y, size.height)
                    }
                    handle(point(bezier.x2, bezier.y2)) { loc in
                        bezier.x2 = min(max(Double(loc.x / size.width), 0), 1)
                        bezier.y2 = clampY(loc.y, size.height)
                    }
                }
                .coordinateSpace(name: "plot")
            }
            .frame(height: 360).padding(.horizontal, 20).padding(.vertical, 24)
            .accessibilityIdentifier("graphEditorPlot")

            EditorPreviewTrack(bezier: bezier).frame(height: 44).padding(.horizontal, 20)

            Text(String(format: "cubic-bezier(%.2f, %.2f, %.2f, %.2f)", bezier.x1, bezier.y1, bezier.x2, bezier.y2))
                .font(.footnote.monospacedDigit()).foregroundColor(.secondary)
            Spacer()
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    private func clampY(_ y: CGFloat, _ height: CGFloat) -> Double {
        let value = range.upperBound - Double(y / height) * (range.upperBound - range.lowerBound)
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private func handle(_ position: CGPoint, drag: @escaping (CGPoint) -> Void) -> some View {
        Circle().fill(Color.white).overlay(Circle().stroke(Color.accentColor, lineWidth: 3))
            .frame(width: 26, height: 26)
            .shadow(radius: 2)
            .contentShape(Circle().inset(by: -12))
            .position(position)
            .gesture(DragGesture(coordinateSpace: .named("plot")).onChanged { drag($0.location) })
    }
}

/// A small layer slides left to right with the edited graph, looping, so the handles can be judged by motion.
private struct EditorPreviewTrack: View {
    let bezier: LabBezier

    var body: some View {
        SwiftUI.TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.2) / 1.4
            GeometryReader { proxy in
                let travel = proxy.size.width - 36
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemBackground)).frame(height: 6)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 36, height: 36)
                        .offset(x: bezier.value(at: min(t, 1)) * travel)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .accessibilityIdentifier("graphEditorPreview")
    }
}
