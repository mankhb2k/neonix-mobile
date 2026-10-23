import SwiftUI
import AuthenticationServices
import CryptoKit
import Security

/// Dedicated second step of the guest-account flow.
struct GoogleLoginView: View {
    @ObservedObject var account: GoogleAccountSession
    let onSignedIn: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var appleNonce: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .background(.thinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Back")

                    Spacer()

                    NavigationLink {
                        HelpCenterView()
                            .toolbar(.visible, for: .navigationBar)
                    } label: {
                        Text("Help")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer(minLength: 30)

                VStack(spacing: 18) {
                    NeonixBrandMark(size: 88)
                    VStack(spacing: 8) {
                        Text("Your ideas, in motion.")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .tracking(-0.7)
                            .multilineTextAlignment(.center)
                        Text("Sign in to Neonix")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 30)

                VStack(spacing: 14) {
                    Button {
                        beginGoogleSignIn()
                    } label: {
                        HStack(spacing: 12) {
                            Spacer(minLength: 0)
                            if let googleLogo = Self.googleLogo {
                                Image(uiImage: googleLogo)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 22, height: 22)
                            }
                            Text("Sign in with Google")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 18)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color(uiColor: .separator).opacity(0.45), lineWidth: 1)
                                .allowsHitTesting(false)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .disabled(account.isLoading)
                    .accessibilityIdentifier("google-sign-in-button")

                    SignInWithAppleButton(.signIn) { request in
                        let nonce = Self.randomNonce() ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
                        appleNonce = nonce
                        request.requestedScopes = [.email, .fullName]
                        request.nonce = Self.sha256(nonce)
                    } onCompletion: { result in
                        handleAppleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .disabled(account.isLoading)
                    .accessibilityIdentifier("apple-sign-in-button")

                    if account.isLoading {
                        ProgressView("Connecting to Neonix…")
                            .font(.caption)
                            .tint(.secondary)
                            .padding(.top, 2)
                    }

                    if let message = account.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .accessibilityIdentifier("google-sign-in-error")
                    }
                }

                Spacer(minLength: 30)

                VStack(spacing: 8) {
                    Text("By continuing, you agree to Neonix's")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Link("Terms of Use", destination: PrivacyTermsView.termsURL)
                        Text("·").foregroundStyle(.tertiary)
                        Link("Privacy Policy", destination: PrivacyTermsView.privacyURL)
                    }
                    .font(.caption.weight(.semibold))
                    .tint(Color(red: 0.31, green: 0.39, blue: 0.91))
                }
                .multilineTextAlignment(.center)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                VStack {
                    Ellipse()
                        .fill(LinearGradient(colors: [.cyan.opacity(0.13), .purple.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(height: 310)
                        .blur(radius: 38)
                        .offset(y: -150)
                    Spacer()
                }
                .ignoresSafeArea()
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(Color(red: 0.31, green: 0.39, blue: 0.91))
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var controller = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }

    private static let googleLogo: UIImage? = {
        guard let url = Bundle.main.url(forResource: "google-signin", withExtension: "png") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }()

    private func beginGoogleSignIn() {
        Task {
            guard let presenter = Self.topViewController() else {
                account.errorMessage = "Could not open Google Sign-In. Please try again."
                return
            }
            await account.signIn(presenting: presenter)
            if account.isSignedIn { await onSignedIn() }
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = appleNonce else {
                account.errorMessage = "Could not complete Apple Sign-In. Please try again."
                return
            }
            appleNonce = nil
            Task {
                await account.signInWithApple(credential: credential, nonce: nonce)
                if account.isSignedIn { await onSignedIn() }
            }
        case .failure(let error):
            appleNonce = nil
            if (error as? ASAuthorizationError)?.code != .canceled {
                account.errorMessage = error.localizedDescription
            }
        }
    }

    private static func randomNonce() -> String? {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
