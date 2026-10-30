import UIKit
import SwiftUI
import Combine

/// Hosts the SwiftUI phone UI and, crucially, is the first responder that receives hardware
/// keyboard presses. Those are forwarded to the desktop through `InputRouter`.
final class PhoneRootViewController: UIViewController {

    private let session = DesktopSession.shared
    private var hosting: UIHostingController<PhoneRootView>!
    private var previewDesktop: DesktopViewController?
    /// iOS 27 scene-accessory registration for the external display. Must stay alive.
    private var sceneAccessoryRegistration: Any?
    private var cancellables = Set<AnyCancellable>()

    override var canBecomeFirstResponder: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { session.displayState.isConnected || session.previewingOnPhone }
    override var prefersStatusBarHidden: Bool { session.displayState.isConnected || session.previewingOnPhone }
    /// While the desktop is on the monitor, lock the pointer so mouse deltas arrive raw through
    /// GameController instead of moving a system pointer around the dark phone screen.
    override var prefersPointerLocked: Bool { session.displayState.isConnected && !session.previewingOnPhone }

    private var lastHoverPoint: CGPoint?
    private var lastScrollTranslation = CGPoint.zero
    private var loggedHover = false
    private var loggedScroll = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        hosting = UIHostingController(rootView: PhoneRootView())
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.pin(to: view)
        hosting.view.backgroundColor = .black
        hosting.didMove(toParent: self)

        session.$previewingOnPhone
            .removeDuplicates()
            .sink { [weak self] previewing in
                DispatchQueue.main.async { self?.setPreview(previewing) }
            }
            .store(in: &cancellables)
        session.$displayState
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.setNeedsStatusBarAppearanceUpdate()
                    self?.setNeedsUpdateOfHomeIndicatorAutoHidden()
                    self?.setNeedsUpdateOfPrefersPointerLocked()
                }
            }
            .store(in: &cancellables)

        // Fallback pointer input: the system pointer hovering / scrolling over the phone screen
        // (e.g. a mouse driven through AssistiveTouch when pointer lock is not granted).
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(pointerHover(_:)))
        view.addGestureRecognizer(hover)
        let scroll = UIPanGestureRecognizer(target: self, action: #selector(pointerScroll(_:)))
        scroll.allowedScrollTypesMask = .all
        scroll.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        scroll.cancelsTouchesInView = false
        scroll.delaysTouchesBegan = false
        scroll.delaysTouchesEnded = false
        view.addGestureRecognizer(scroll)

        NotificationCenter.default.addObserver(self, selector: #selector(pointerLockChanged), name: UIPointerLockState.didChangeNotification, object: nil)
    }

    @objc private func pointerLockChanged() {
        let locked = view.window?.windowScene?.pointerLockState?.isLocked ?? false
        session.log("Pointer lock \(locked ? "granted" : "released")")
    }

    @objc private func pointerHover(_ g: UIHoverGestureRecognizer) {
        let p = g.location(in: view)
        switch g.state {
        case .began:
            lastHoverPoint = p
        case .changed:
            if !loggedHover { loggedHover = true; session.log("Pointer hover events arriving on the phone screen") }
            if let last = lastHoverPoint, session.displayState.isConnected {
                InputRouter.shared.pointerHovered(delta: CGPoint(x: p.x - last.x, y: p.y - last.y))
            }
            lastHoverPoint = p
        default:
            lastHoverPoint = nil
        }
    }

    @objc private func pointerScroll(_ g: UIPanGestureRecognizer) {
        guard g.numberOfTouches == 0 else { return } // scroll wheel only, never finger drags
        let t = g.translation(in: view)
        switch g.state {
        case .began:
            lastScrollTranslation = t
        case .changed:
            if !loggedScroll { loggedScroll = true; session.log("Scroll events arriving on the phone screen") }
            let dx = t.x - lastScrollTranslation.x, dy = t.y - lastScrollTranslation.y
            lastScrollTranslation = t
            // UIKit has already applied the system scrolling direction preference.
            if session.displayState.isConnected { InputRouter.shared.scroll(dx: -dx, dy: -dy) }
        default:
            lastScrollTranslation = .zero
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
        registerExternalDisplayAccessory()
    }

    // MARK: - External display (iOS 27+)

    /// Up to iOS 26 the system connected the external-display scene automatically because
    /// Info.plist declares it. From iOS 27 the app only receives that scene after a view
    /// controller on screen registers a scene accessory for it; until then iOS just mirrors.
    private func registerExternalDisplayAccessory() {
        guard sceneAccessoryRegistration == nil else { return }
        if #available(iOS 27.0, *) {
            let config = UISceneConfiguration(name: "Desktop", sessionRole: .windowExternalDisplayNonInteractive)
            config.delegateClass = ExternalSceneDelegate.self
            let accessory = UISceneAccessory.externalNonInteractive(sceneConfiguration: config)
            let registration = registerSceneAccessory(accessory)
            sceneAccessoryRegistration = registration
            ExternalDisplayMonitor.shared.accessoryStatus = { [weak registration] in
                guard let registration else { return "released" }
                return registration.isAvailable ? "available" : "not available"
            }
            session.log("Scene accessory registered for external display · available: \(registration.isAvailable)")
        } else {
            session.log("iOS 26 or earlier: external-display scene connects automatically")
        }
    }

    // MARK: - Hardware keyboard

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let keyPresses = presses.filter { $0.key != nil }
        if keyPresses.isEmpty { super.pressesBegan(presses, with: event); return }
        InputRouter.shared.pressesBegan(keyPresses)
    }

    override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {}

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let keyPresses = presses.filter { $0.key != nil }
        if keyPresses.isEmpty { super.pressesEnded(presses, with: event); return }
        InputRouter.shared.pressesEnded(keyPresses)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        InputRouter.shared.pressesCancelled(presses)
    }

    // Keep the system from treating ⌘ shortcuts as app key commands.
    override var keyCommands: [UIKeyCommand]? { [] }

    // MARK: - Desktop preview on the phone

    private func setPreview(_ on: Bool) {
        if on, previewDesktop == nil {
            let desktop = DesktopViewController()
            desktop.allowsTouchInput = true
            addChild(desktop)
            view.addSubview(desktop.view)
            desktop.view.pin(to: view)
            desktop.didMove(toParent: self)
            previewDesktop = desktop
            let exit = DeskButton(title: "Exit Preview", symbol: "xmark", style: .pill)
            // Top-right, clear of the window traffic lights that sit at the top-left of the desktop.
            exit.frame = CGRect(x: desktop.view.bounds.width - 142, y: 36, width: 130, height: 26)
            exit.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
            exit.isUserInteractionEnabled = true
            let tap = UITapGestureRecognizer(target: self, action: #selector(exitPreview))
            exit.addGestureRecognizer(tap)
            desktop.view.addSubview(exit)
        } else if !on, let desktop = previewDesktop {
            desktop.desktopWillDisconnect()
            desktop.willMove(toParent: nil)
            desktop.view.removeFromSuperview()
            desktop.removeFromParent()
            previewDesktop = nil
            if let real = session.desktop { InputRouter.shared.sink = real }
        }
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        becomeFirstResponder()
    }

    @objc private func exitPreview() {
        session.endPhonePreview()
    }
}
