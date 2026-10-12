import SwiftUI

@main
struct NeonixEditorApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
                #if DEBUG
                .task { await FilterThumbnailBench.runIfRequested() }   // env FILTER_BENCH=1; see FilterThumbnailBench
                #endif
        }
    }
}
