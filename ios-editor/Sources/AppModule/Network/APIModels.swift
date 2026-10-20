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

/// One row of `GET /v1/billing/ledger` (newest first). `delta` is signed: purchases add, exports subtract.
struct APILedgerEntry: Decodable, Identifiable, Equatable {
    let id: String
    let delta: Int
    let balanceAfter: Int
    /// purchase, export, export_refund, iap_refund, grant, template_purchase
    let reason: String
    let createdAt: Date
}

/// `GET /v1/billing/packs`: credit packs on sale. The price text comes from StoreKit by `productId`.
struct APIPack: Decodable, Identifiable, Equatable {
    let productId: String
    let credits: Int
    var id: String { productId }
}

struct APIPackList: Decodable { let items: [APIPack] }

/// `POST /v1/billing/purchases`. `credited` is false when the same transaction was already counted (a retry).
struct APIPurchaseResult: Decodable {
    let credited: Bool
    let credits: Int
    let balance: Int
}

struct APILedgerPage: Decodable {
    let items: [APILedgerEntry]
    let nextCursor: String?
}

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

    var isUnauthenticated: Bool {
        if case .http(let status, _, _) = self { return status == 401 || status == 403 }
        return false
    }
}

struct APIAccountProfile: Decodable {
    let id: String
    let displayName: String?
    let avatarUrl: URL?
    let role: String?
    let balance: Int
}

/// `GET /v1/sounds`: the built-in sound-effect library (files live in R2; `url` is public or presigned). `peaks` is the
/// loudness per slice (0...1) the picker draws as a mini waveform before the file is downloaded.
struct APISoundCatalogue: Codable, Equatable {
    struct Category: Codable, Equatable, Identifiable { let id: String; let title: String }
    struct Sound: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        let category: String
        let url: URL
        let durationMs: Double
        let mimeType: String
        let peaks: [Double]
    }
    let categories: [Category]
    let sounds: [Sound]
}

/// `GET /v1/stickers`: the built-in sticker library (images live in R2; `url` is public or presigned).
struct APIStickerCatalogue: Decodable, Equatable {
    struct License: Decodable, Equatable { let name: String; let holder: String; let source: String; let file: String }
    struct Category: Decodable, Equatable, Identifiable { let id: String; let title: String }
    struct Sticker: Decodable, Equatable, Identifiable {
        let id: String
        let name: String
        let category: String
        let url: URL
        let width: Double
        let height: Double
    }
    let license: License
    let categories: [Category]
    let stickers: [Sticker]
}
