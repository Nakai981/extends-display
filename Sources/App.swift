import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let external = session.role == .windowExternalDisplayNonInteractive
        let config = UISceneConfiguration(name: external ? "External" : "Device", sessionRole: session.role)
        config.delegateClass = external ? ExternalSceneDelegate.self : DeviceSceneDelegate.self
        return config
    }
}

final class DeviceSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        if Workspace.shared.localDesktop?.viewIfLoaded?.window != nil {
            // All custom desktop windows belong to one controlling device scene.
            // A second system window must not reparent the same content pool.
            let controller = UIViewController(); controller.view.backgroundColor = .systemBackground
            let message = UILabel(); message.text = "ExtendDesk is open in another window.\nUse that window to control your desktop."; message.numberOfLines = 0; message.textAlignment = .center
            message.frame = controller.view.bounds.insetBy(dx: 24, dy: 24); message.autoresizingMask = [.flexibleWidth, .flexibleHeight]; controller.view.addSubview(message)
            window.rootViewController = controller
        } else { window.rootViewController = DeviceController() }
        self.window = window
        window.makeKeyAndVisible()
    }
    func sceneDidEnterBackground(_ scene: UIScene) {
        guard window?.rootViewController is DeviceController else { return }
        Workspace.shared.save(); Workspace.shared.activeDesktop?.pointerUp(); DesktopSharing.shared.stop()
    }
    func sceneDidDisconnect(_ scene: UIScene) {
        guard let controller = window?.rootViewController as? DeviceController else { window = nil; return }
        if Workspace.shared.localDesktop?.parent === controller {
            Workspace.shared.localDesktop?.suspend(); Workspace.shared.localDesktop = nil
        }
        window = nil
    }
}

final class ExternalSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        let desktop = DesktopController(external: true)
        Workspace.shared.localDesktop?.suspend()
        Workspace.shared.externalDesktop = desktop
        window.rootViewController = desktop
        self.window = window
        window.isHidden = false
        NotificationCenter.default.post(name: .displayChanged, object: nil)
    }
    func sceneDidDisconnect(_ scene: UIScene) {
        if Workspace.shared.externalDesktop === window?.rootViewController {
            Workspace.shared.externalDesktop?.suspend()
            Workspace.shared.externalDesktop = nil
        }
        window = nil
        NotificationCenter.default.post(name: .displayChanged, object: nil)
    }
}

extension Notification.Name {
    static let workspaceChanged = Notification.Name("workspaceChanged")
    static let displayChanged = Notification.Name("displayChanged")
    static let filesChanged = Notification.Name("filesChanged")
}
