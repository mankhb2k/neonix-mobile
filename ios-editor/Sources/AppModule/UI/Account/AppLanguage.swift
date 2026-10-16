import SwiftUI

/// The app's language. `system` follows the device; the others override it at runtime (no restart).
/// Strings live in `Resources/Localizable.xcstrings` (English is the key). Only the Account tab is translated so far.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english, vietnamese

    static let storageKey = "appLanguage"

    var id: String { rawValue }

    /// Language code of the override, `nil` = follow the device.
    var code: String? {
        switch self {
        case .system: return nil
        case .english: return "en"
        case .vietnamese: return "vi"
        }
    }

    /// Put in the environment at the root: `Text("literal")` then looks the string up in this language.
    var locale: Locale { code.map(Locale.init(identifier:)) ?? .autoupdatingCurrent }

    /// Each language is named in itself, so it can be found whatever language the app is in.
    var nativeName: String? {
        switch self {
        case .system: return nil
        case .english: return "English"
        case .vietnamese: return "Tiếng Việt"
        }
    }

    /// For text that is a `String` (not a `Text` literal), which SwiftUI would show untranslated.
    func string(_ key: String) -> String {
        guard let code else { return NSLocalizedString(key, comment: "") }   // follow the device
        // English is the key itself (there is no en.lproj), so a forced English must not fall back to the device's language.
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"), let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

struct LanguageView: View {
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system

    var body: some View {
        List {
            Section {
                ForEach(AppLanguage.allCases) { option in
                    Button {
                        language = option
                    } label: {
                        HStack {
                            if let name = option.nativeName {
                                Text(verbatim: name).foregroundColor(.primary)
                            } else {
                                Text("System").foregroundColor(.primary)
                            }
                            Spacer()
                            if language == option { Image(systemName: "checkmark").foregroundColor(.accentColor) }
                        }
                    }
                    .accessibilityIdentifier("language-\(option.rawValue)")
                }
            } footer: {
                Text("Some screens are not translated yet and stay in English.")
            }
        }
        .navigationTitle(language.string("Language"))   // a literal title wouldn't change while this screen is open
        .navigationBarTitleDisplayMode(.inline)
    }
}
