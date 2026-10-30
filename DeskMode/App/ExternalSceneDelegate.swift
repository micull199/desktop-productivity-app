import UIKit

/// The scene that appears on the external monitor. It hosts the whole desktop.
final class ExternalSceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var desktop: DesktopViewController?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        // Use every pixel the display offers. Overscan compensation would shrink the desktop.
        windowScene.screen.overscanCompensation = .none

        let desktop = DesktopViewController()
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = desktop
        window.backgroundColor = .black
        // Do not make this window *key*: hardware keyboard presses must keep flowing to the
        // phone scene, which forwards them through `InputRouter`.
        window.isHidden = false
        self.window = window
        self.desktop = desktop

        DesktopSession.shared.externalDisplayDidConnect(windowScene, desktop: desktop)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        desktop?.desktopWillDisconnect()
        desktop = nil
        window = nil
        DesktopSession.shared.externalDisplayDidDisconnect()
    }
}
