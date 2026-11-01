import XCTest
@testable import ExtendDesk

final class BrowserModelTests: XCTestCase {
    func testClosingSelectedTabChoosesNeighborAndNeverLeavesEmptySession() {
        var session = BrowserSession(url: "https://example.com")
        let first = session.selectedID
        let second = session.add(url: "https://example.org")!
        session.close(second)
        XCTAssertEqual(session.selectedID, first)
        session.close(first)
        XCTAssertEqual(session.tabs.count, 1)
        XCTAssertEqual(session.selectedID, session.tabs[0].id)
    }
    func testTabLimitAndSelectionSurvivePersistence() throws {
        var session = BrowserSession()
        for index in 1..<BrowserSession.maximumTabs { XCTAssertNotNil(session.add(url: "https://example.com/\(index)")) }
        XCTAssertNil(session.add(url: "https://overflow.example"))
        let selected = session.selectedID
        let data = try JSONEncoder().encode(session)
        var restored = try JSONDecoder().decode(BrowserSession.self, from: data)
        restored.normalize()
        XCTAssertEqual(restored, session)
        XCTAssertEqual(restored.selectedID, selected)
    }
    func testTransientWebSchemesAreNotPersistedAsReloadTargets() {
        var session = BrowserSession(url: "https://example.com")
        session.update(session.selectedID, title: "Download", url: "blob:https://example.com/some-id")
        XCTAssertEqual(session.selected.url, "https://example.com")
        XCTAssertEqual(session.selected.title, "Download")
    }
    func testDownloadProgressIsBoundedAndUnknownLengthIsIndeterminate() {
        var record = DownloadRecord(id: UUID(), name: "Test")
        XCTAssertNil(record.fraction)
        record.expected = 100; record.received = 150
        XCTAssertEqual(record.fraction, 1)
        record.received = -1
        XCTAssertEqual(record.fraction, 0)
    }
    func testZoomDefaultsForOlderSavedTabsAndStaysBounded() throws {
        let original = BrowserTabRecord(url: "https://example.com", pageZoom: 1.4)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        legacy.removeValue(forKey: "pageZoom")
        let restored = try JSONDecoder().decode(BrowserTabRecord.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(restored.pageZoom, 1)
        var session = BrowserSession(url: "https://example.com")
        session.setZoom(9, for: session.selectedID); XCTAssertEqual(session.selected.pageZoom, 2)
        session.setZoom(0.1, for: session.selectedID); XCTAssertEqual(session.selected.pageZoom, 0.5)
        session.setZoom(.infinity, for: session.selectedID); XCTAssertEqual(session.selected.pageZoom, 1)
        session.setZoom(1.3, for: session.selectedID)
        let saved = try JSONDecoder().decode(BrowserSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(saved.selected.pageZoom, 1.3)
    }
    func testNeighborNavigationWrapsWithoutCreatingTabs() {
        var session = BrowserSession(url: "https://first.example")
        let first = session.selectedID
        let second = session.add(url: "https://second.example")!
        session.selectNeighbor(backwards: false); XCTAssertEqual(session.selectedID, first)
        session.selectNeighbor(backwards: true); XCTAssertEqual(session.selectedID, second)
        XCTAssertEqual(session.tabs.count, 2)
    }
}
