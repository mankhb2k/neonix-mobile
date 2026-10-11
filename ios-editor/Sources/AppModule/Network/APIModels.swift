import Foundation

// Wire models for neonix-api (see api/README.md). Hand-written like the Protocol
// Codable types; only the fields the app reads.

struct APIBalance: Decodable { let balance: Int }

struct APITemplateVersionInfo: Decodable {
    let version: Int
    let sizeBytes: Int?
    let formatVersion: Int
    let minAppVersion: String?
    let slotCount: Int?
    let width: Int?
    let height: Int?
    let durationMs: Int?
}

struct APITemplateCreator: Decodable {
    let id: String
    let name: String?
    let avatarUrl: URL?
}

struct APITemplate: Decodable, Identifiable {
    let id: String
    let title: String
    let description: String
    let category: String
    /// Credits the first export of this template costs. Paid once: after that the template is the user's and
    /// every export is free.
    let creditCost: Int
    /// Still image: shown on cards and as the viewer's first frame.
    let posterUrl: URL?
    /// Short looping video (or an image), played while the card is on screen. May be nil.
    let previewUrl: URL?
    let useCount: Int
    let creator: APITemplateCreator
    /// true = this user already bought it (exports are free). nil when the server did not say.
    let owned: Bool?
    let updatedAt: Date?
    let version: APITemplateVersionInfo?
}

struct APITemplatePage: Decodable {
    let items: [APITemplate]
    /// Pass back as `cursor` for the next page; nil on the last page.
    let nextCursor: String?
}

struct APIPackageInfo: Decodable {
    let url: URL
    let expiresAt: Date
    let versionId: String
    let sha256: String?
    let version: Int
    let sizeBytes: Int?
    let formatVersion: Int
    let minAppVersion: String?
}

struct APIExportResult: Decodable {
    let purchaseId: String
    /// true = this call bought the template (credits were spent); false = already owned, free.
    let charged: Bool
    let creditsCharged: Int
    let balance: Int
}

struct APICreditGrant: Decodable { let balance: Int }

enum APIError: LocalizedError {
    case http(status: Int, code: String?, message: String)
    case invalidResponse
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .http(_, _, let message): return message
        case .invalidResponse: return "Invalid server response"
        case .checksumMismatch: return "Downloaded file is corrupted"
        }
    }

    /// 402 from POST /v1/exports.
    var isInsufficientCredits: Bool {
        if case .http(_, let code, _) = self { return code == "INSUFFICIENT_CREDITS" }
        return false
    }
}
