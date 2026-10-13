import SwiftUI

@main
struct NeonixEditorApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
                #if DEBUG
                .task { await FilterThumbnailBench.runIfRequested() }   // env FILTER_BENCH=1; see FilterThumbnailBench
                .task { await SeekTimeBench.runIfRequested() }   // env SEEK_BENCH=1; see SeekTimeBench
                #endif
        }
    }
}
