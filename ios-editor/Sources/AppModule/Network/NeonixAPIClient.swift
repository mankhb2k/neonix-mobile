import CryptoKit
import Foundation

enum NeonixAPIAuth {
    /// Debug only: the server runs with DEV_AUTH_BYPASS=true and treats the id as the signed-in user.
    case devUser(String)
    case bearer(() -> String?)
}

struct NeonixAPIConfig {
    var baseURL: URL
    var auth: NeonixAPIAuth

    /// Debug defaults to production so an app launched from Xcode can exercise the deployed API.
    /// Set `NEONIX_API_URL` or the `apiBaseURL` preference to use a local development server.
    static var current: NeonixAPIConfig {
        #if DEBUG
        let raw = ProcessInfo.processInfo.environment["NEONIX_API_URL"]
            ?? UserDefaults.standard.string(forKey: "apiBaseURL")
            ?? "https://api.neonix.video"
        let user = UserDefaults.standard.string(forKey: "devUserId") ?? "dev-ios"
        let baseURL = URL(string: raw) ?? URL(string: "https://api.neonix.video")!
        let isLocalDevelopmentServer = baseURL.host == "localhost" || baseURL.host == "127.0.0.1"
        let auth: NeonixAPIAuth
        if AuthTokenStore.token != nil {
            auth = .bearer { AuthTokenStore.token }
        } else if isLocalDevelopmentServer {
            auth = .devUser(user)
        } else {
            auth = .bearer { AuthTokenStore.token }
        }
        return NeonixAPIConfig(baseURL: baseURL, auth: auth)
        #else
        return NeonixAPIConfig(baseURL: URL(string: "https://api.neonix.video")!, auth: .bearer { AuthTokenStore.token })
        #endif
    }
}

/// Thin client for neonix-api: balance, template catalogue, package download, export (credit spend).
struct NeonixAPIClient {
    var config: NeonixAPIConfig
    var session: URLSession = .shared

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = withFraction.date(from: raw) ?? plain.date(from: raw) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(raw)"))
        }
        return decoder
    }()

    // MARK: Endpoints

    /// Exchanges Google's native ID token for the API's Better Auth bearer session.
    func signInWithGoogle(idToken: String, accessToken: String?) async throws -> String {
        var request = URLRequest(url: config.baseURL.appendingPathComponent("api/auth/sign-in/social"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var payload: [String: Any] = ["provider": "google", "idToken": ["token": idToken]]
        if let accessToken { payload["idToken"] = ["token": idToken, "accessToken": accessToken] }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw Self.error(status: http.statusCode, data: data) }
        guard let token = http.value(forHTTPHeaderField: "set-auth-token"), !token.isEmpty else {
            throw APIError.invalidResponse
        }
        return token
    }

    func accountProfile() async throws -> APIAccountProfile {
        try await send("GET", "v1/me", as: APIAccountProfile.self)
    }

    func signOut() async throws {
        struct Empty: Decodable {}
        _ = try await send("POST", "api/auth/sign-out", as: Empty.self)
    }

    func balance() async throws -> Int {
        try await send("GET", "v1/billing/balance", as: APIBalance.self).balance
    }

    func packs() async throws -> [APIPack] {
        try await send("GET", "v1/billing/packs", as: APIPackList.self).items
    }

    /// Safe to retry: the server counts one StoreKit transaction once.
    func creditPurchase(signedTransaction: String) async throws -> APIPurchaseResult {
        try await send("POST", "v1/billing/purchases", body: ["signedTransaction": signedTransaction], as: APIPurchaseResult.self)
    }

    func ledger(limit: Int = 30, cursor: String? = nil) async throws -> APILedgerPage {
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await send("GET", "v1/billing/ledger", query: items, as: APILedgerPage.self)
    }

    func templates(category: String? = nil, query: String? = nil, limit: Int = 20, cursor: String? = nil) async throws -> APITemplatePage {
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let category { items.append(URLQueryItem(name: "category", value: category)) }
        if let query { items.append(URLQueryItem(name: "q", value: query)) }
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await send("GET", "v1/templates", query: items, as: APITemplatePage.self)
    }

    func stickers() async throws -> APIStickerCatalogue {
        try await send("GET", "v1/stickers", as: APIStickerCatalogue.self)
    }

    func sounds() async throws -> APISoundCatalogue {
        try await send("GET", "v1/sounds", as: APISoundCatalogue.self)
    }

    /// Free: credits are spent at export, not at download.
    func packageInfo(templateId: String, versionId: String? = nil) async throws -> APIPackageInfo {
        let items = versionId.map { [URLQueryItem(name: "versionId", value: $0)] } ?? []
        return try await send("GET", "v1/templates/\(templateId)/package", query: items, as: APIPackageInfo.self)
    }

    /// Call right before rendering. The first export of a template buys it (credits are spent); after that every
    /// export of that template is free.
    func createExport(templateId: String, versionId: String? = nil) async throws -> APIExportResult {
        var body: [String: String] = ["templateId": templateId]
        if let versionId { body["versionId"] = versionId }
        return try await send("POST", "v1/exports", body: body, as: APIExportResult.self)
    }

    #if DEBUG
    /// Needs the server's DEV_AUTH_BYPASS.
    func grantTestCredits(_ amount: Int) async throws -> Int {
        try await send("POST", "v1/dev/credits", body: ["amount": amount], as: APICreditGrant.self).balance
    }
    #endif

    /// Downloads the zip from its presigned URL and checks the sha256 the server recorded.
    func downloadPackage(_ info: APIPackageInfo) async throws -> Data {
        let (fileURL, response) = try await session.download(from: info.url)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw APIError.invalidResponse }
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        if let expected = info.sha256?.lowercased() {
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actual == expected else { throw APIError.checksumMismatch }
        }
        return data
    }

    // MARK: Transport

    private func send<T: Decodable>(_ method: String, _ path: String, query: [URLQueryItem] = [], body: [String: Any]? = nil, as type: T.Type) async throws -> T {
        var components = URLComponents(url: config.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch config.auth {
        case .devUser(let id): request.setValue(id, forHTTPHeaderField: "X-Dev-User")
        case .bearer(let token): if let token = token() { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw Self.error(status: http.statusCode, data: data) }
        return try Self.decoder.decode(T.self, from: data)
    }

    private static func error(status: Int, data: Data) -> APIError {
        struct Body: Decodable { struct Inner: Decodable { let code: String?; let message: String }; let error: Inner }
        if let body = try? JSONDecoder().decode(Body.self, from: data) {
            return .http(status: status, code: body.error.code, message: body.error.message)
        }
        return .http(status: status, code: nil, message: "Server error (\(status))")
    }
}
