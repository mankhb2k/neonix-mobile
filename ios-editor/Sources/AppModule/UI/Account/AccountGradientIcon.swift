import SwiftUI

/// Compact account/settings icon tile with a distinct Neonix gradient per action.
struct AccountGradientIcon: View {
    let systemName: String
    var size: CGFloat = 34

    private var colors: [Color] {
        switch systemName {
        case "person.crop.circle", "person.crop.circle.fill":
            return [Color(red: 0.13, green: 0.70, blue: 0.98), Color(red: 0.31, green: 0.39, blue: 0.95)]
        case "bitcoinsign.circle", "bitcoinsign.circle.fill", "sparkle":
            return [Color(red: 1.00, green: 0.73, blue: 0.24), Color(red: 0.98, green: 0.48, blue: 0.18)]
        case "externaldrive", "externaldrive.fill":
            return [Color(red: 0.20, green: 0.79, blue: 0.90), Color(red: 0.12, green: 0.53, blue: 0.91)]
        case "bell", "bell.fill":
            return [Color(red: 1.00, green: 0.43, blue: 0.42), Color(red: 0.91, green: 0.23, blue: 0.42)]
        case "paintbrush", "paintbrush.pointed.fill", "circle.lefthalf.filled":
            return [Color(red: 0.47, green: 0.54, blue: 0.98), Color(red: 0.65, green: 0.32, blue: 0.90)]
        case "globe", "globe.americas.fill":
            return [Color(red: 0.72, green: 0.36, blue: 0.94), Color(red: 0.43, green: 0.38, blue: 0.96)]
        case "lock", "lock.fill", "hand.raised":
            return [Color(red: 0.61, green: 0.66, blue: 0.73), Color(red: 0.39, green: 0.45, blue: 0.55)]
        case "questionmark.circle", "questionmark.circle.fill":
            return [Color(red: 0.22, green: 0.75, blue: 0.96), Color(red: 0.16, green: 0.48, blue: 0.91)]
        case "envelope", "envelope.fill":
            return [Color(red: 0.20, green: 0.79, blue: 0.81), Color(red: 0.11, green: 0.57, blue: 0.73)]
        default:
            return [Color(red: 0.16, green: 0.68, blue: 0.97), Color(red: 0.56, green: 0.31, blue: 0.91)]
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.10), radius: 1, y: 1)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
