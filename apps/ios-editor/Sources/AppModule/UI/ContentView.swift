import SwiftUI

enum Fixture: String, CaseIterable, Identifiable {
    case fadeOut = "fade-out-end-anchor"
    case loopSpin = "loop-spin"
    case flip3D = "flip-3d"
    case editorDemo = "editor-demo"
    case textWrap = "text-wrap-demo"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fadeOut: return "Fade out (end-anchored)"
        case .loopSpin: return "Loop spin"
        case .flip3D: return "3D flip"
        case .editorDemo: return "Editor demo"
        case .textWrap: return "Text wrap"
        }
    }
}

func loadFixture(_ fixture: Fixture) -> V2Project? {
    // SwiftPM's `.process()` resource rule flattens the `Fixtures/` subfolder
    // into the bundle root, so no `subdirectory:` argument here.
    guard let url = Bundle.module.url(forResource: fixture.rawValue, withExtension: "json") else {
        return nil
    }
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(V2Project.self, from: data)
}

/// Fires roughly at display refresh rate; `isPlaying` advances `currentTimeMs`
/// by the elapsed wall-clock delta between ticks, looping back to 0 at
/// `maxDurationMs` so the demo keeps playing without re-pressing Play.
let playbackTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

struct ContentView: View {
    @State private var fixture: Fixture = .fadeOut

    var body: some View {
        VStack(spacing: 16) {
            Picker("Fixture", selection: $fixture) {
                ForEach(Fixture.allCases) { fixture in
                    Text(fixture.title).tag(fixture)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if fixture == .editorDemo {
                EditorDemoView()
            } else if fixture == .textWrap {
                TextWrapDemoView()
            } else {
                StaticFixtureView(fixture: fixture)
            }

            Spacer()
        }
        .padding(.top)
    }
}

/// The 3 static, hand-authored Protocol V2 JSON fixtures proving the
/// Runtime/render half of the pipeline (see `apps/ios-editor`'s plan docs).
struct StaticFixtureView: View {
    let fixture: Fixture

    @State private var project: V2Project?
    @State private var currentTimeMs: Double = 0
    @State private var isPlaying = false
    @State private var lastTick: Date = .init()

    private var maxDurationMs: Double {
        guard let project else { return 1 }
        return max(project.layers.map { $0.timing.start + $0.timing.duration }.max() ?? 1, 1)
    }

    var body: some View {
        VStack(spacing: 16) {
            if let project {
                let frames = project.layers.map { sampleLayer($0, atMs: currentTimeMs) }
                PreviewCanvas(composition: project.composition, assets: project.assets, frames: frames)
                    .aspectRatio(project.composition.width / project.composition.height, contentMode: .fit)
                    .padding()
            } else {
                Text("Failed to load fixture").foregroundStyle(.red)
            }

            HStack {
                Button(isPlaying ? "Pause" : "Play") {
                    isPlaying.toggle()
                    lastTick = .init()
                }
                Slider(value: $currentTimeMs, in: 0...maxDurationMs) { editing in
                    if editing { isPlaying = false }
                    lastTick = .init()
                }
                Text("\(Int(currentTimeMs)) ms")
                    .monospacedDigit()
                    .frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal)
        }
        .onAppear { reload() }
        .onChange(of: fixture) { _, _ in reload() }
        .onReceive(playbackTimer) { now in
            guard isPlaying else { return }
            let deltaMs = now.timeIntervalSince(lastTick) * 1000
            lastTick = now
            currentTimeMs = (currentTimeMs + deltaMs).truncatingRemainder(dividingBy: maxDurationMs)
        }
    }

    private func reload() {
        project = loadFixture(fixture)
        currentTimeMs = 0
        lastTick = .init()
        isPlaying = false
    }
}
