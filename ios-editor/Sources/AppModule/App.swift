import SwiftUI
import GoogleSignIn

@main
struct NeonixEditorApp: App {
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.system
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(appearance.colorScheme)
                .environment(\.locale, language.locale)
                .onOpenURL { url in
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
                #if DEBUG
                .task { await FilterThumbnailBench.runIfRequested() }   // env FILTER_BENCH=1; see FilterThumbnailBench
                .task { await CropFrameBench.runIfRequested() }   // env CROP_BENCH=1; see CropFrameBench
                .task { await RemoveBackgroundBench.runIfRequested() }   // env REMOVEBG_BENCH=1; see RemoveBackgroundBench
                .task { await SeekTimeBench.runIfRequested() }   // env SEEK_BENCH=1; see SeekTimeBench
                .task { await SpeedBench.runIfRequested() }   // env SPEED_BENCH=1; see SpeedBench
                #endif
        }
    }
}
