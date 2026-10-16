import StoreKitTest
import XCTest
@testable import NeonixEditor

/// End to end against a local API (`pnpm dev` with DEV_AUTH_BYPASS and `pnpm db:seed`) and the real
/// `Credits.storekit`, driven by `SKTestSession`. Skipped when the API isn't running.
@MainActor
final class CreditStoreTests: XCTestCase {
    private var session: SKTestSession!
    private let client = NeonixAPIClient(config: NeonixAPIConfig(baseURL: URL(string: "http://localhost:8080")!, auth: .devUser("dev-ios")))

    override func setUp() async throws {
        try await super.setUp()
        do { _ = try await client.balance() } catch { throw XCTSkip("local API not running: \(error)") }
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("StoreKit/Credits.storekit")
        session = try SKTestSession(contentsOf: file)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
    }

    func testPacksComeWithStoreKitPrices() async throws {
        let store = CreditStore(client: client)
        await store.loadPacks()

        let pack = try XCTUnwrap(store.packs.first { $0.credits == 50 })
        XCTAssertEqual(pack.productId, "com.neonix.editor.credits.50")
        XCTAssertEqual(pack.product?.displayPrice, "$0.99")
        XCTAssertNil(store.failure)
    }

    func testBuyingAPackAddsItsCreditsOnTheServer() async throws {
        let before = try await client.balance()
        let store = CreditStore(client: client)
        await store.loadPacks()
        let pack = try XCTUnwrap(store.packs.first { $0.credits == 50 })

        var reported: Int?
        store.onBalance = { reported = $0 }
        await store.buy(pack)

        XCTAssertNil(store.failure)
        XCTAssertEqual(reported, before + 50)
        let after = try await client.balance()
        XCTAssertEqual(after, before + 50)
        XCTAssertTrue(session.allTransactions().allSatisfy { $0.state == .purchased })
    }

    func testTheSameTransactionIsNotCreditedTwice() async throws {
        let store = CreditStore(client: client)
        await store.loadPacks()
        let pack = try XCTUnwrap(store.packs.first { $0.credits == 50 })
        let before = try await client.balance()

        await store.buy(pack)
        let afterBuy = try await client.balance()
        // The same signed transaction sent again (an app that died before finish()).
        let result = try await pack.product!.latestTransaction
        let signed = try XCTUnwrap(result).jwsRepresentation
        let retry = try await client.creditPurchase(signedTransaction: signed)

        XCTAssertEqual(afterBuy, before + 50)
        XCTAssertFalse(retry.credited)
        let afterRetry = try await client.balance()
        XCTAssertEqual(afterRetry, afterBuy)
    }
}
