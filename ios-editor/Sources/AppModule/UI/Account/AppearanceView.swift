import SwiftUI

/// App-wide light/dark choice; `system` follows the device. Stored in `@AppStorage(AppearanceMode.storageKey)`.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearanceMode"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// `nil` = follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct AppearanceView: View {
    @AppStorage(AppearanceMode.storageKey) private var mode = AppearanceMode.system

    var body: some View {
        List {
            Section {
                ForEach(AppearanceMode.allCases) { option in
                    Button {
                        mode = option
                    } label: {
                        HStack {
                            Text(option.title).foregroundColor(.primary)
                            Spacer()
                            if mode == option { Image(systemName: "checkmark").foregroundColor(.accentColor) }
                        }
                    }
                    .accessibilityIdentifier("appearance-\(option.rawValue)")
                }
            } footer: {
                Text("System follows your device's light or dark setting.")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}
