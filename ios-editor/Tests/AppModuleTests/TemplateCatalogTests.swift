import XCTest
@testable import NeonixEditor

func makeAPITemplate(_ id: String, category: String = "x", uses: Int = 0, owned: Bool? = nil, width: Int? = nil, height: Int? = nil, updated: Date? = nil) throws -> APITemplate {
    let date = updated.map { "\"\(ISO8601DateFormatter().string(from: $0))\"" } ?? "null"
    let version = (width != nil && height != nil)
        ? #"{"version":1,"sizeBytes":1,"formatVersion":2,"minAppVersion":null,"slotCount":3,"width":\#(width!),"height":\#(height!),"durationMs":12000}"#
        : "null"
    return try NeonixAPIClient.decoder.decode(APITemplate.self, from: Data("""
    {"id":"\(id)","title":"T \(id)","description":"","category":"\(category)","creditCost":6,"posterUrl":null,"previewUrl":null,
     "useCount":\(uses),"creator":{"id":"c","name":null,"avatarUrl":null},"owned":\(owned.map(String.init) ?? "null"),"updatedAt":\(date),"version":\(version)}
    """.utf8))
}

@MainActor
final class TemplateCatalogTests: XCTestCase {
    func testCategoriesKeepFirstSeenOrderWithoutDuplicates() throws {
        let catalog = TemplateCatalog()
        catalog.seed([try makeAPITemplate("a", category: "slideshow"), try makeAPITemplate("b", category: "highlights"), try makeAPITemplate("c", category: "slideshow")])
        XCTAssertEqual(catalog.categories, ["slideshow", "highlights"])
        XCTAssertEqual(TemplateCatalog.displayName(forCategory: "slideshow"), "Slideshow")
    }

    func testNewBadgeLastsTwoWeeks() throws {
        let now = Date()
        XCTAssertTrue(TemplateCatalog.isNew(try makeAPITemplate("a", updated: now.addingTimeInterval(-3 * 86_400)), now: now))
        XCTAssertFalse(TemplateCatalog.isNew(try makeAPITemplate("b", updated: now.addingTimeInterval(-15 * 86_400)), now: now))
        XCTAssertFalse(TemplateCatalog.isNew(try makeAPITemplate("c"), now: now))
    }

    func testMasonryPutsEachCardInTheShorterColumn() throws {
        // Each card joins the shorter column: tall (left), wide1 (right), wide2 (right, still shorter than tall+0),
        // wide3 (left, the right column is now taller).
        let tall = try makeAPITemplate("tall", width: 1080, height: 1920)
        let wide1 = try makeAPITemplate("wide1", width: 1920, height: 1080)
        let wide2 = try makeAPITemplate("wide2", width: 1920, height: 1080)
        let wide3 = try makeAPITemplate("wide3", width: 1920, height: 1080)
        let columns = MasonryColumns.split([tall, wide1, wide2, wide3])
        XCTAssertEqual(columns.left.map(\.id), ["tall", "wide3"])
        XCTAssertEqual(columns.right.map(\.id), ["wide1", "wide2"])
        XCTAssertEqual(MasonryColumns.split([]).left.count, 0)
    }

    func testCompactCountAndCaption() throws {
        XCTAssertEqual(compactCount(61_100), "61.1K")
        XCTAssertEqual(compactCount(950), "950")
        XCTAssertEqual(compactCount(2_500_000), "2.5M")
        XCTAssertEqual(templateCaption(try makeAPITemplate("a", width: 1080, height: 1920)), "12s · 3 slots")
    }
}
