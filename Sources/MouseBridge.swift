import GameController
import UIKit

final class MouseBridge {
    static let shared = MouseBridge()
    private var observers: [NSObjectProtocol] = []
    func start() {
        guard observers.isEmpty else { return }
        observers.append(NotificationCenter.default.addObserver(forName: .GCMouseDidConnect, object: nil, queue: .main) { [weak self] notification in
            if let mouse = notification.object as? GCMouse { self?.connect(mouse) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .GCMouseDidDisconnect, object: nil, queue: .main) { _ in Workspace.shared.activeDesktop?.pointerUp() })
        GCMouse.mice().forEach(connect)
    }
    private func connect(_ mouse: GCMouse) {
        guard let input = mouse.mouseInput else { return }
        input.mouseMovedHandler = { _, x, y in DispatchQueue.main.async {
            guard Workspace.shared.externalDesktop != nil else { return }
            Workspace.shared.activeDesktop?.movePointer(CGPoint(x: Double(x) * Workspace.shared.pointerSpeed, y: -Double(y) * Workspace.shared.pointerSpeed))
        } }
        input.leftButton.pressedChangedHandler = { _, _, pressed in DispatchQueue.main.async {
            guard Workspace.shared.externalDesktop != nil else { return }
            if pressed { Workspace.shared.activeDesktop?.pointerDown() }
            else if Workspace.shared.activeDesktop?.pointerUp() == true { Workspace.shared.activeDesktop?.click() }
        } }
        input.rightButton?.pressedChangedHandler = { _, _, pressed in
            if pressed { DispatchQueue.main.async { if Workspace.shared.externalDesktop != nil { Workspace.shared.activeDesktop?.click(secondary: true) } } }
        }
        input.scroll.valueChangedHandler = { _, x, y in DispatchQueue.main.async {
            guard Workspace.shared.externalDesktop != nil else { return }
            Workspace.shared.activeDesktop?.scroll(CGPoint(x: Double(x) * 30, y: -Double(y) * 30))
        } }
    }
}
