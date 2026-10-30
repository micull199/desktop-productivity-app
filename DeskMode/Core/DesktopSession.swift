import UIKit
import Combine

/// App-wide state shared by the phone scene and the external-display scene.
@MainActor
final class DesktopSession: ObservableObject {

    static let shared = DesktopSession()

    enum DisplayState: Equatable {
        case disconnected
        case connected(size: CGSize, scale: CGFloat)

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    @Published private(set) var displayState: DisplayState = .disconnected
    /// True while the iPhone's own screen is dimmed to black because the desktop is in use.
    @Published private(set) var phoneScreenDimmed = false
    /// True while the desktop is being previewed on the phone screen itself (no monitor needed).
    @Published private(set) var previewingOnPhone = false
    @Published private(set) var openWindowCount = 0

    private(set) weak var phoneScene: UIWindowScene?
    private(set) weak var desktop: DesktopViewController?
    private var savedBrightness: CGFloat?
    private var cancellables = Set<AnyCancellable>()

    let settings = Settings.shared
    let input = InputRouter.shared

    private init() {
        settings.$dimPhoneWhenConnected
            .dropFirst()
            .sink { [weak self] dim in
                guard let self, self.displayState.isConnected else { return }
                if dim { self.dimPhoneScreen() } else { self.wakePhoneScreen() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Phone scene

    func phoneSceneDidConnect(_ scene: UIWindowScene) {
        phoneScene = scene
    }

    func phoneSceneDidBecomeActive() {
        if displayState.isConnected, settings.dimPhoneWhenConnected, !previewingOnPhone {
            dimPhoneScreen()
        }
    }

    func phoneSceneWillResignActive() {
        restoreBrightness()
    }

    func phoneSceneDidDisconnect() {
        restoreBrightness()
        phoneScene = nil
    }

    // MARK: - External display

    func externalDisplayDidConnect(_ scene: UIWindowScene, desktop: DesktopViewController) {
        self.desktop = desktop
        let size = scene.coordinateSpace.bounds.size
        displayState = .connected(size: size, scale: scene.screen.scale)
        UIApplication.shared.isIdleTimerDisabled = true
        if settings.dimPhoneWhenConnected { dimPhoneScreen() }
        desktop.onWindowCountChange = { [weak self] count in self?.openWindowCount = count }
    }

    func externalDisplayDidDisconnect() {
        desktop = nil
        displayState = .disconnected
        openWindowCount = 0
        UIApplication.shared.isIdleTimerDisabled = false
        wakePhoneScreen()
    }

    // MARK: - Phone preview (desktop drawn on the iPhone screen for testing)

    func beginPhonePreview() {
        previewingOnPhone = true
        wakePhoneScreen()
    }

    func endPhonePreview() {
        previewingOnPhone = false
    }

    // MARK: - Screen dimming

    /// iOS does not let an app switch the display off, so DeskMode does the next best thing:
    /// black UI + brightness at zero + idle timer disabled so the phone never locks mid-session.
    func dimPhoneScreen() {
        guard let screen = phoneScene?.screen else { return }
        if savedBrightness == nil { savedBrightness = screen.brightness }
        screen.brightness = 0
        phoneScreenDimmed = true
    }

    func wakePhoneScreen() {
        restoreBrightness()
        phoneScreenDimmed = false
    }

    private func restoreBrightness() {
        guard let saved = savedBrightness, let screen = phoneScene?.screen else { return }
        screen.brightness = saved
        savedBrightness = nil
    }

    // MARK: - Convenience for the phone UI

    func openApp(_ app: DeskApp) {
        desktop?.open(app)
    }

    var displayDescription: String {
        switch displayState {
        case .disconnected: return "Not connected"
        case .connected(let size, let scale):
            return "\(Int(size.width * scale)) × \(Int(size.height * scale))"
        }
    }
}
