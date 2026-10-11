import CryptoKit
import XCTest
@testable import NeonixEditor

/// Answers every request from a closure, so the client is tested without a server.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var request = self.request
        // URLSession moves the body to a stream; read it back so tests can assert on it.
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            stream.close()
            request.httpBody = data
        }
        Self.lastRequest = request
        let (status, body) = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class NeonixAPIClientTests: XCTestCase {
    private func makeClient(auth: NeonixAPIAuth = .devUser("dev-test")) -> NeonixAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return NeonixAPIClient(config: NeonixAPIConfig(baseURL: URL(string: "http://localhost:8080")!, auth: auth), session: URLSession(configuration: configuration))
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        StubURLProtocol.lastRequest = nil
    }

    func testBalanceSendsDevUserHeader() async throws {
        StubURLProtocol.handler = { _ in (200, Data(#"{"balance":14}"#.utf8)) }
        let balance = try await makeClient().balance()
        XCTAssertEqual(balance, 14)
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.path, "/v1/billing/balance")
        XCTAssertEqual(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "X-Dev-User"), "dev-test")
    }

    func testBearerAuthHeader() async throws {
        StubURLProtocol.handler = { _ in (200, Data(#"{"balance":1}"#.utf8)) }
        _ = try await makeClient(auth: .bearer { "tok123" }).balance()
        XCTAssertEqual(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok123")
        XCTAssertNil(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "X-Dev-User"))
    }

    func testDecodesTemplatePageAndPassesCursor() async throws {
        StubURLProtocol.handler = { _ in
            (200, Data("""
            {"items":[{"id":"t1","title":"Photo Slideshow","description":"d","category":"slideshow","creditCost":6,
              "status":"published","posterUrl":"https://cdn.example/p.jpg","previewUrl":null,"useCount":3,
              "creator":{"id":"c1","name":null,"avatarUrl":null},"updatedAt":"2026-10-10T10:00:00.123Z",
              "version":{"version":1,"sizeBytes":2048,"formatVersion":2,"minAppVersion":"1.0","slotCount":5,"width":1080,"height":1920,"durationMs":12000}}],
             "nextCursor":"abc"}
            """.utf8))
        }
        let page = try await makeClient().templates(category: "slideshow", limit: 5, cursor: "prev")
        XCTAssertEqual(page.nextCursor, "abc")
        XCTAssertEqual(page.items.first?.creditCost, 6)
        XCTAssertEqual(page.items.first?.version?.slotCount, 5)
        let query = URLComponents(url: StubURLProtocol.lastRequest!.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "cursor" }?.value, "prev")
        XCTAssertEqual(query.first { $0.name == "limit" }?.value, "5")
    }

    func testCreateExportPostsTheTemplateOnly() async throws {
        StubURLProtocol.handler = { _ in
            (200, Data(#"{"purchaseId":"p1","owned":true,"charged":false,"creditsCharged":0,"balance":14}"#.utf8))
        }
        let result = try await makeClient().createExport(templateId: "t1")
        XCTAssertFalse(result.charged)
        XCTAssertEqual(result.balance, 14)
        XCTAssertEqual(StubURLProtocol.lastRequest?.httpMethod, "POST")
        let body = try JSONSerialization.jsonObject(with: StubURLProtocol.lastRequest!.httpBody!) as? [String: String]
        XCTAssertEqual(body, ["templateId": "t1"])
    }

    func testTemplateCarriesTheOwnedFlag() throws {
        let owned = try makeAPITemplate("a", owned: true)
        let unknown = try makeAPITemplate("b")
        XCTAssertEqual(owned.owned, true)
        XCTAssertNil(unknown.owned)
    }

    func testInsufficientCreditsIsRecognised() async {
        StubURLProtocol.handler = { _ in
            (402, Data(#"{"error":{"message":"Not enough credits","code":"INSUFFICIENT_CREDITS"}}"#.utf8))
        }
        do {
            _ = try await makeClient().createExport(templateId: "t1")
            XCTFail("expected an error")
        } catch let error as APIError {
            XCTAssertTrue(error.isInsufficientCredits)
            XCTAssertEqual(error.errorDescription, "Not enough credits")
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testDownloadRejectsChecksumMismatch() async throws {
        let payload = Data("zip bytes".utf8)
        StubURLProtocol.handler = { _ in (200, payload) }
        let good = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        func info(_ sha: String) -> APIPackageInfo {
            try! NeonixAPIClient.decoder.decode(APIPackageInfo.self, from: Data("""
            {"url":"http://localhost:9000/p.zip","expiresAt":"2026-10-10T10:15:00.000Z","versionId":"v","sha256":"\(sha)","version":1,"sizeBytes":9,"formatVersion":2,"minAppVersion":null}
            """.utf8))
        }
        let data = try await makeClient().downloadPackage(info(good))
        XCTAssertEqual(data, payload)
        do {
            _ = try await makeClient().downloadPackage(info(String(repeating: "0", count: 64)))
            XCTFail("expected checksum mismatch")
        } catch APIError.checksumMismatch {}
    }
}
