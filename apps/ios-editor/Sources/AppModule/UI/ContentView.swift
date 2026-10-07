import SwiftUI

enum Fixture: String, CaseIterable, Identifiable {
    case editorDemo = "editor-demo"
    case textWrap = "text-wrap-demo"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .editorDemo: return "Editor demo"
        case .textWrap: return "Text wrap"
        }
    }
}

/// Fires roughly at display refresh rate; `isPlaying` advances `currentTimeMs`
/// by the elapsed wall-clock delta between ticks, looping back to 0 at
/// `maxDurationMs` so the demo keeps playing without re-pressing Play.
let playbackTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

struct ContentView: View {
    @State private var fixture: Fixture = .editorDemo

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
            } else {
                TextWrapDemoView()
            }

            Spacer()
        }
        .padding(.top)
    }
}
