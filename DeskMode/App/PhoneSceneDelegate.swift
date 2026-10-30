import UIKit

/// The scene shown on the iPhone's own screen.
final class PhoneSceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = PhoneRootViewController()
        window.makeKeyAndVisible()
        self.window = window
        DesktopSession.shared.phoneSceneDidConnect(windowScene)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        DesktopSession.shared.phoneSceneDidBecomeActive()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        DesktopSession.shared.phoneSceneWillResignActive()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        DesktopSession.shared.phoneSceneDidDisconnect()
    }
}
