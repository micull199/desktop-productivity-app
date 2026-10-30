import UIKit

/// Pure UIKit lifecycle. The app runs two kinds of scene at once:
///
/// * the iPhone screen (`PhoneSceneDelegate`) – setup, status and the touch trackpad fallback
/// * the external monitor (`ExternalSceneDelegate`) – the desktop environment itself
///
/// iOS creates the external-display scene automatically when a monitor is attached over USB-C
/// (DisplayPort Alt Mode or an HDMI adapter) while the app is in the foreground.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UIDevice.current.isBatteryMonitoringEnabled = true
        InputRouter.shared.start()
        return true
    }

    // MARK: - Scenes

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        switch connectingSceneSession.role {
        case .windowExternalDisplayNonInteractive:
            let config = UISceneConfiguration(name: "Desktop", sessionRole: connectingSceneSession.role)
            config.delegateClass = ExternalSceneDelegate.self
            return config
        default:
            let config = UISceneConfiguration(name: "Phone", sessionRole: connectingSceneSession.role)
            config.delegateClass = PhoneSceneDelegate.self
            return config
        }
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {}
}
