import Foundation
import Observation
import StoreKit

/// Buying credits: packs from the API, prices from StoreKit 2, and the signed transaction back to the API,
/// which verifies it and adds the credits. A transaction is finished only after the server counted it, so one
/// that fails to reach the server comes back (`Transaction.unfinished` / `updates`) and is retried.
@MainActor @Observable
final class CreditStore {
    struct Pack: Identifiable, Equatable {
        let productId: String
        let credits: Int
        /// nil = StoreKit doesn't know this product (not set up in App Store Connect / the .storekit file).
        let product: Product?
        var id: String { productId }
    }

    enum Failure: Equatable { case loadFailed, purchaseFailed, pending }

    private(set) var packs: [Pack] = []
    private(set) var isLoading = false
    private(set) var buyingId: String?
    var failure: Failure?
    /// Called with the new balance after the server added credits.
    var onBalance: ((Int) -> Void)?

    @ObservationIgnored private let client: NeonixAPIClient
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init(client: NeonixAPIClient = NeonixAPIClient(config: .current)) {
        self.client = client
    }

    func start() async {
        if updatesTask == nil {
            updatesTask = Task { [weak self] in
                for await result in Transaction.updates { await self?.credit(result) }
            }
        }
        for await result in Transaction.unfinished { await credit(result) }
        await loadPacks()
    }

    func loadPacks() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let apiPacks = try await client.packs()
            let products = (try? await Product.products(for: apiPacks.map(\.productId))) ?? []
            packs = apiPacks.map { pack in Pack(productId: pack.productId, credits: pack.credits, product: products.first { $0.id == pack.productId }) }
            if failure == .loadFailed { failure = nil }
        } catch {
            failure = .loadFailed
        }
    }

    func buy(_ pack: Pack) async {
        guard let product = pack.product, buyingId == nil else { return }
        buyingId = pack.id
        failure = nil
        defer { buyingId = nil }
        do {
            switch try await product.purchase() {
            case .success(let result): await credit(result)
            case .pending: failure = .pending
            case .userCancelled: break
            @unknown default: break
            }
        } catch {
            failure = .purchaseFailed
        }
    }

    /// Hands a finished purchase to the server; only a counted one is finished.
    private func credit(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { failure = .purchaseFailed; return }
        do {
            let outcome = try await client.creditPurchase(signedTransaction: result.jwsRepresentation)
            onBalance?(outcome.balance)
            await transaction.finish()
        } catch {
            failure = .purchaseFailed   // not finished: it is offered again next launch
        }
    }
}
