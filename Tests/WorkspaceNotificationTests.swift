import XCTest
@testable import ExtendDesk

@MainActor
final class WorkspaceNotificationTests: XCTestCase {
    func testFocusingCurrentWindowDoesNotPublishAnotherRender() async {
        let suite = "ExtendDeskTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspace = Workspace(defaults: defaults)
        let created = expectation(description: "Window creation published")
        let first = NotificationCenter.default.addObserver(forName: .workspaceChanged, object: workspace, queue: .main) { _ in created.fulfill() }
        let id = workspace.open(.notes)
        await fulfillment(of: [created], timeout: 1)
        NotificationCenter.default.removeObserver(first)
        let redundant = expectation(description: "No redundant render for current focus")
        redundant.isInverted = true
        let second = NotificationCenter.default.addObserver(forName: .workspaceChanged, object: workspace, queue: .main) { _ in redundant.fulfill() }
        workspace.focus(id)
        await fulfillment(of: [redundant], timeout: 0.2)
        NotificationCenter.default.removeObserver(second)
        workspace.save()
    }
}
