import UIKit

/// Watches for external screens independently of UIKit's automatic scene creation.
///
/// The intended path is that iOS hands the app a `UIWindowSceneSessionRoleExternalDisplayNonInteractive`
/// scene as soon as a monitor is attached (see `ExternalSceneDelegate`). This monitor exists for the
/// cases where that does not happen: it records what iOS actually reported so the phone UI can show
/// it, and if a screen is present but no desktop scene has appeared after a short grace period it
/// falls back to the classic `UIScreen` API and puts a desktop window on the screen itself.
@MainActor
final class ExternalDisplayMonitor {

    static let shared = ExternalDisplayMonitor()

    private let session = DesktopSession.shared
    private var fallbackWindow: UIWindow?
    private var fallbackDesktop: DesktopViewController?
    private var pendingFallback: DispatchWorkItem?
    private var started = false

    /// How long to give UIKit to deliver the external-display scene before taking over.
    private let gracePeriod: TimeInterval = 2.5

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        let nc = NotificationCenter.default
        // Deprecated since iOS 16 in favour of scenes, but still posted and the only way to see a
        // screen that UIKit did not turn into a scene.
        nc.addObserver(self, selector: #selector(screenDidConnect(_:)), name: UIScreen.didConnectNotification, object: nil)
        nc.addObserver(self, selector: #selector(screenDidDisconnect(_:)), name: UIScreen.didDisconnectNotification, object: nil)
        nc.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        session.log("Monitor started · screens: \(describeScreens())")
        recheck(reason: "launch")
    }

    /// Called by `DesktopSession` when the real external-display scene connects, so any fallback
    /// window gets out of the way without emitting a disconnect.
    func sceneTookOver() {
        pendingFallback?.cancel()
        pendingFallback = nil
        guard fallbackWindow != nil else { return }
        session.log("Desktop scene arrived · removing legacy window")
        fallbackDesktop?.desktopWillDisconnect()
        fallbackWindow?.isHidden = true
        fallbackWindow = nil
        fallbackDesktop = nil
    }

    // MARK: - Notifications

    @objc private func screenDidConnect(_ note: Notification) {
        guard let screen = note.object as? UIScreen else { return }
        session.log("Screen connected: \(describe(screen)) · app \(appState)")
        scheduleFallback(for: screen)
    }

    @objc private func screenDidDisconnect(_ note: Notification) {
        let screen = note.object as? UIScreen
        session.log("Screen disconnected: \(screen.map(describe) ?? "?")")
        pendingFallback?.cancel()
        pendingFallback = nil
        if let fallbackWindow, let screen, fallbackWindow.screen === screen {
            tearDownFallback()
        }
    }

    @objc private func appDidBecomeActive() {
        recheck(reason: "became active")
    }

    /// Looks at the screens iOS currently reports and arranges a fallback if one of them is an
    /// external display that has no desktop on it.
    func recheck(reason: String) {
        let externals = externalScreens()
        guard let screen = externals.first else { return }
        if session.displayState.isConnected {
            return
        }
        session.log("External screen present at \(reason): \(describe(screen)) · no desktop yet")
        scheduleFallback(for: screen)
    }

    // MARK: - Fallback window

    private func scheduleFallback(for screen: UIScreen) {
        pendingFallback?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.fallbackIfNeeded(for: screen) }
        }
        pendingFallback = work
        DispatchQueue.main.asyncAfter(deadline: .now() + gracePeriod, execute: work)
    }

    private func fallbackIfNeeded(for screen: UIScreen) {
        pendingFallback = nil
        if session.displayState.isConnected {
            session.log("Desktop scene is up · no fallback needed")
            return
        }
        guard fallbackWindow == nil else { return }
        guard externalScreens().contains(where: { $0 === screen }) else {
            session.log("Screen went away before fallback")
            return
        }
        let externalSessions = UIApplication.shared.openSessions.filter {
            $0.role == .windowExternalDisplayNonInteractive || $0.role == .windowExternalDisplay
        }
        session.log("No desktop scene after \(Int(gracePeriod)) s (external scene sessions: \(externalSessions.count)) · trying legacy window")

        let desktop = DesktopViewController()
        let window = UIWindow(frame: screen.bounds)
        window.screen = screen
        guard window.screen === screen else {
            session.log("iOS refused to attach a window to the external screen")
            return
        }
        window.rootViewController = desktop
        window.backgroundColor = .black
        window.windowLevel = .normal
        window.isHidden = false
        fallbackWindow = window
        fallbackDesktop = desktop
        session.log("Legacy window attached to \(describe(screen))")
        session.externalDisplayDidConnect(size: screen.bounds.size, scale: screen.scale, desktop: desktop)
    }

    private func tearDownFallback() {
        fallbackDesktop?.desktopWillDisconnect()
        fallbackWindow?.isHidden = true
        fallbackWindow = nil
        fallbackDesktop = nil
        session.externalDisplayDidDisconnect()
    }

    // MARK: - Helpers

    private func externalScreens() -> [UIScreen] {
        let phoneScreen = session.phoneScene?.screen ?? UIScreen.main
        return UIScreen.screens.filter { $0 !== phoneScreen }
    }

    private func describe(_ screen: UIScreen) -> String {
        let b = screen.bounds
        return "\(Int(b.width * screen.scale))×\(Int(b.height * screen.scale)) @\(Int(screen.scale))x"
    }

    private func describeScreens() -> String {
        UIScreen.screens.map(describe).joined(separator: ", ")
    }

    private var appState: String {
        switch UIApplication.shared.applicationState {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }
}
