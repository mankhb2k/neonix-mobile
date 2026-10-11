import Foundation
import Observation

/// What the Home screen shows: published templates from neonix-api, paged, searchable, filterable by category.
@MainActor
@Observable
final class TemplateCatalog {
    enum State { case idle, loading, loaded, failed(String) }

    private(set) var state: State = .idle
    private(set) var templates: [APITemplate] = []
    /// Every category seen so far, first-seen order. Kept across filtered loads so the chips do not vanish.
    private(set) var categories: [String] = []
    private(set) var hasMore = false

    private var nextCursor: String?
    private var query = ""
    private var category: String?
    private var generation = 0
    private let client: NeonixAPIClient

    init(client: NeonixAPIClient = NeonixAPIClient(config: .current)) {
        self.client = client
    }

    var isLoading: Bool { if case .loading = state { return true } else { return false } }

    /// Starts over with a new search/category (page 1).
    func reload(query: String = "", category: String? = nil) async {
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.category = category
        nextCursor = nil
        generation += 1
        await fetch(replacing: true)
    }

    /// Next page; call when the last card appears.
    func loadMore() async {
        guard hasMore, !isLoading else { return }
        await fetch(replacing: false)
    }

    private func fetch(replacing: Bool) async {
        let ticket = generation
        state = .loading
        do {
            let page = try await client.templates(category: category, query: query.isEmpty ? nil : query, limit: 20, cursor: replacing ? nil : nextCursor)
            guard ticket == generation else { return }   // a newer search superseded this one
            templates = replacing ? page.items : templates + page.items
            nextCursor = page.nextCursor
            hasMore = page.nextCursor != nil
            for item in page.items where !categories.contains(item.category) { categories.append(item.category) }
            state = .loaded
        } catch {
            guard ticket == generation else { return }
            state = .failed(error.localizedDescription)
        }
    }

    /// For tests: sets the list without a server.
    func seed(_ templates: [APITemplate]) {
        self.templates = templates
        for item in templates where !categories.contains(item.category) { categories.append(item.category) }
        state = .loaded
    }

    static func displayName(forCategory category: String) -> String {
        category.prefix(1).uppercased() + category.dropFirst()
    }

    /// Shows the "New" badge for two weeks after the last update.
    static func isNew(_ template: APITemplate, now: Date = Date()) -> Bool {
        guard let updated = template.updatedAt else { return false }
        return now.timeIntervalSince(updated) < 14 * 24 * 3600
    }
}

/// Splits cards into two columns for the waterfall layout: each card goes to the shorter column.
enum MasonryColumns {
    /// Height of a card for a column of unit width: the poster's aspect (clamped, default 9:16) plus the caption.
    static func cardHeight(_ template: APITemplate, captionHeight: Double = 0.45) -> Double {
        let aspect: Double
        if let w = template.version?.width, let h = template.version?.height, w > 0 { aspect = Double(h) / Double(w) } else { aspect = 16.0 / 9.0 }
        return min(max(aspect, 0.8), 2.0) + captionHeight
    }

    static func split(_ templates: [APITemplate]) -> (left: [APITemplate], right: [APITemplate]) {
        var left: [APITemplate] = [], right: [APITemplate] = []
        var leftHeight = 0.0, rightHeight = 0.0
        for template in templates {
            if leftHeight <= rightHeight { left.append(template); leftHeight += cardHeight(template) }
            else { right.append(template); rightHeight += cardHeight(template) }
        }
        return (left, right)
    }
}
