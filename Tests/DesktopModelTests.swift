import XCTest
@testable import ExtendDesk

final class DesktopModelTests: XCTestCase {
    func testTiledWindowsDoNotOverlapAndStayInsideCanvas() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let current = CGRect(x: 80, y: 70, width: 800, height: 540)
        let left = WindowPlacement.left.frame(in: bounds, current: current), right = WindowPlacement.right.frame(in: bounds, current: current)
        XCTAssertFalse(left.intersects(right)); XCTAssertTrue(bounds.contains(left)); XCTAssertTrue(bounds.contains(right))
        let quarters = [WindowPlacement.topLeft, .topRight, .bottomLeft, .bottomRight].map { $0.frame(in: bounds, current: current) }
        for i in quarters.indices { XCTAssertTrue(bounds.contains(quarters[i])); for j in quarters.indices where i < j { XCTAssertFalse(quarters[i].intersects(quarters[j])) } }
    }
    func testLegacyWindowSessionWithoutRestoreFrameStillLoads() throws {
        let record = WindowRecord(kind: .browser, title: "Old session", url: "https://example.com")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        json.removeValue(forKey: "restoreFrame")
        let restored = try JSONDecoder().decode(WindowRecord.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.restoreFrame); XCTAssertEqual(restored.id, record.id)
    }
    func testGeometryFitsSmallAndResizedDisplays() {
        let bounds = CGRect(x: 0, y: 0, width: 280, height: 180)
        let rect = WindowGeometry.constrain(CGRect(x: 800, y: -80, width: 1200, height: 900), to: bounds)
        XCTAssertEqual(rect, bounds)
        let normal = WindowGeometry.constrain(CGRect(x: 950, y: 680, width: 480, height: 320), to: CGRect(x: 0, y: 0, width: 1024, height: 768))
        XCTAssertEqual(normal.maxX, 1024); XCTAssertEqual(normal.maxY, 768)
    }
    func testFocusMinimizeRestoreAndSessionFlush() throws {
        let suite = "ExtendDeskTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspace = Workspace(defaults: defaults)
        let first = workspace.open(.notes), second = workspace.open(.files)
        workspace.focus(first); workspace.focus(first)
        XCTAssertEqual(workspace.windows.map(\.id), [second, first])
        workspace.update(first) { $0.minimized = true }
        XCTAssertEqual(workspace.focusedID, second)
        workspace.activate(.notes)
        XCTAssertEqual(workspace.windows.count, 2)
        XCTAssertFalse(workspace.windows.first(where: { $0.id == first })!.minimized)
        workspace.save()
        let restored = Workspace(defaults: defaults)
        XCTAssertEqual(restored.windows, workspace.windows)
        restored.close(first)
        XCTAssertEqual(restored.focusedID, second)
    }
}
