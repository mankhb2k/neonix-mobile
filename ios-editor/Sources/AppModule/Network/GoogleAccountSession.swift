import Combine
import Foundation
import GoogleSignIn
import AuthenticationServices

@MainActor
final class GoogleAccountSession: ObservableObject {
    @Published private(set) var profile: APIAccountProfile?
    @Published private(set) var email: String?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    var isSignedIn: Bool { profile != nil && AuthTokenStore.token != nil }

    private let api = NeonixAPIClient(config: .current)

    func restore() async {
        guard AuthTokenStore.token != nil else { return }
        do {
            _ = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            email = GIDSignIn.sharedInstance.currentUser?.profile?.email
        } catch {
            // The backend bearer token is the source of truth for API access. Google restoration only
            // provides the email for the account card and is allowed to expire independently.
        }
        do {
            profile = try await api.accountProfile()
        } catch {
            if (error as? APIError)?.isUnauthenticated == true {
                AuthTokenStore.token = nil
                email = nil
            }
            profile = nil
        }
    }

    func signIn(presenting viewController: UIViewController) async {
        guard let iosClientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              let webClientID = Bundle.main.object(forInfoDictionaryKey: "GIDServerClientID") as? String,
              !iosClientID.contains("REPLACE_WITH"), !webClientID.contains("REPLACE_WITH") else {
            errorMessage = "Google Sign-In needs the iOS and Web OAuth client IDs in the app build settings."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let previousToken = AuthTokenStore.token
        let previousProfile = profile
        let previousEmail = email
        do {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: iosClientID, serverClientID: webClientID)
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)
            guard let idToken = result.user.idToken?.tokenString else {
                throw GoogleSignInError.missingIDToken
            }
            AuthTokenStore.token = try await api.signInWithGoogle(
                idToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            email = result.user.profile?.email
            profile = try await api.accountProfile()
        } catch {
            AuthTokenStore.token = previousToken
            profile = previousProfile
            email = previousEmail
            errorMessage = error.localizedDescription
        }
    }

    func signInWithApple(credential: ASAuthorizationAppleIDCredential, nonce: String) async {
        guard let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            errorMessage = "Apple did not return an identity token. Please try again."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let previousToken = AuthTokenStore.token
        let previousProfile = profile
        let previousEmail = email
        do {
            AuthTokenStore.token = try await api.signInWithApple(
                idToken: idToken,
                nonce: nonce,
                email: credential.email,
                firstName: credential.fullName?.givenName,
                lastName: credential.fullName?.familyName
            )
            email = credential.email ?? previousEmail
            profile = try await api.accountProfile()
        } catch {
            AuthTokenStore.token = previousToken
            profile = previousProfile
            email = previousEmail
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        isLoading = true
        defer { isLoading = false }
        do { try await api.signOut() } catch { /* Clear local credentials even if the network is unavailable. */ }
        clearLocalAccount()
    }

    func deleteAccount() async throws {
        isLoading = true
        defer { isLoading = false }
        try await api.deleteAccount()
        clearLocalAccount()
    }

    private func clearLocalAccount() {
        AuthTokenStore.token = nil
        profile = nil
        email = nil
        errorMessage = nil
        GIDSignIn.sharedInstance.signOut()
    }
}

private enum GoogleSignInError: LocalizedError {
    case missingIDToken
    var errorDescription: String? { "Google did not return an ID token. Please try again." }
}
