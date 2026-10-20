import SwiftUI

/// Account landing screen for people who have not signed in yet.
struct GuestAccountView: View {
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.system
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system
    let onSignIn: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Button(action: onSignIn) {
                    HStack(spacing: 15) {
                        NeonixBrandMark(size: 58)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Your Neonix account")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("Sign in to manage credits and export")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(18)
                    .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("account-sign-in-entry")

                workspaceCard

                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("Preferences")
                    VStack(spacing: 0) {
                        NavigationLink {
                            StorageView()
                        } label: {
                            accountRow("Storage", detail: nil, icon: "externaldrive")
                        }
                        .accessibilityIdentifier("row-storage")
                        divider
                        NavigationLink {
                            AppearanceView()
                        } label: {
                            accountRow("Appearance", detail: appearance.rawValue.capitalized, icon: "circle.lefthalf.filled")
                        }
                        divider
                        NavigationLink {
                            LanguageView()
                        } label: {
                            accountRow("Language", detail: language.nativeName ?? "System", icon: "globe")
                        }
                        divider
                        NavigationLink {
                            PrivacyTermsView()
                        } label: {
                            accountRow("Privacy & Terms", detail: nil, icon: "hand.raised")
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("Support")
                    VStack(spacing: 0) {
                        NavigationLink {
                            HelpCenterView()
                        } label: {
                            accountRow("Help Center", detail: nil, icon: "questionmark.circle")
                        }
                        divider
                        NavigationLink {
                            FeedbackView()
                        } label: {
                            accountRow("Send feedback", detail: nil, icon: "envelope")
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                #if DEBUG
                NavigationLink {
                    DesignLabView()
                } label: {
                    HStack(spacing: 12) {
                        AccountGradientIcon(systemName: "slider.horizontal.3", size: 38)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Design Lab")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("Developer tools")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("DEV")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(0.7)
                            .foregroundStyle(Color(red: 0.34, green: 0.35, blue: 0.86))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color(red: 0.34, green: 0.35, blue: 0.86).opacity(0.10), in: Capsule())
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("developer-design-lab")
                .padding(.bottom, 20)
                #endif
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.large)
    }

    private var workspaceCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("NEONIX STUDIO", systemImage: "sparkles")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.82))
                Spacer()
                Image(systemName: "waveform")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.88))
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Your ideas,\nin motion.")
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .lineSpacing(-2)
                    .foregroundStyle(.white)
                Text("One Google sign-in for credits and exports.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.84))
            }
            Button(action: onSignIn) {
                HStack(spacing: 8) {
                    Text("Continue to your account")
                    Image(systemName: "arrow.up.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(red: 0.16, green: 0.13, blue: 0.36))
                .padding(.horizontal, 16)
                .frame(height: 42)
                .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("account-sign-in-cta")
        }
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.12, green: 0.68, blue: 0.94), Color(red: 0.34, green: 0.35, blue: 0.91), Color(red: 0.58, green: 0.26, blue: 0.83)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(.white.opacity(0.10))
                        .frame(width: 150, height: 150)
                        .blur(radius: 1)
                        .offset(x: 35, y: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                }
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1).padding(.leading, 42)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }

    private func accountRow(_ title: String, detail: String?, icon: String) -> some View {
        HStack(spacing: 12) {
            AccountGradientIcon(systemName: icon, size: 34)
            Text(title).font(.body).foregroundStyle(.primary)
            Spacer()
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }
}

struct NeonixBrandMark: View {
    var size: CGFloat = 58

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
            .fill(LinearGradient(colors: [Color.cyan, Color.blue, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "viewfinder")
                    .font(.system(size: size * 0.47, weight: .semibold))
                    .foregroundStyle(.white)
                    .overlay {
                        Text("N")
                            .font(.system(size: size * 0.25, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
            }
            .shadow(color: .blue.opacity(0.22), radius: 12, x: 0, y: 6)
    }
}
