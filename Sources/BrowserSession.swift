import Foundation

struct BrowserTabRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var url: String
    var pageZoom: Double
    init(id: UUID = UUID(), title: String = "New tab", url: String = "https://www.apple.com", pageZoom: Double = 1) {
        self.id = id; self.title = title; self.url = url
        self.pageZoom = Self.boundedZoom(pageZoom)
    }
    private enum CodingKeys: String, CodingKey { case id, title, url, pageZoom }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? "New tab"
        url = try values.decodeIfPresent(String.self, forKey: .url) ?? "https://www.apple.com"
        pageZoom = Self.boundedZoom(try values.decodeIfPresent(Double.self, forKey: .pageZoom) ?? 1)
    }
    static func boundedZoom(_ value: Double) -> Double { value.isFinite ? min(2, max(0.5, value)) : 1 }
}

/// Metadata is cheap; WKWebViews are allocated only when a tab is selected.
struct BrowserSession: Codable, Equatable {
    static let maximumTabs = 24
    private(set) var tabs: [BrowserTabRecord]
    private(set) var selectedID: UUID
    var selected: BrowserTabRecord { tabs.first(where: { $0.id == selectedID }) ?? tabs[0] }

    init(url: String = "https://www.apple.com") {
        let first = BrowserTabRecord(url: url)
        tabs = [first]; selectedID = first.id
    }
    mutating func normalize() {
        if tabs.isEmpty { self = BrowserSession(); return }
        var seen = Set<UUID>()
        tabs = Array(tabs.filter { seen.insert($0.id).inserted }.prefix(Self.maximumTabs))
        if !tabs.contains(where: { $0.id == selectedID }) { selectedID = tabs[0].id }
    }
    @discardableResult mutating func add(url: String) -> UUID? {
        guard tabs.count < Self.maximumTabs else { return nil }
        let tab = BrowserTabRecord(url: url)
        tabs.append(tab); selectedID = tab.id; return tab.id
    }
    mutating func select(_ id: UUID) {
        if tabs.contains(where: { $0.id == id }) { selectedID = id }
    }
    mutating func selectNeighbor(backwards: Bool) {
        guard let index = tabs.firstIndex(where: { $0.id == selectedID }), !tabs.isEmpty else { return }
        selectedID = tabs[(index + (backwards ? tabs.count - 1 : 1)) % tabs.count].id
    }
    mutating func setZoom(_ value: Double, for id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].pageZoom = BrowserTabRecord.boundedZoom(value)
    }
    mutating func close(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if tabs.isEmpty { self = BrowserSession(); return }
        if selectedID == id { selectedID = tabs[min(index, tabs.count - 1)].id }
    }
    mutating func update(_ id: UUID, title: String?, url: String?) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        if let title, !title.isEmpty { tabs[index].title = String(title.prefix(160)) }
        if let url, let scheme = URL(string: url)?.scheme, ["http", "https"].contains(scheme) { tabs[index].url = url }
    }
}
