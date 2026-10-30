import UIKit
import SwiftUI
import Combine

/// Hosts the SwiftUI phone UI and, crucially, is the first responder that receives hardware
/// keyboard presses. Those are forwarded to the desktop through `InputRouter`.
final class PhoneRootViewController: UIViewController {

    private let session = DesktopSession.shared
    private var hosting: UIHostingController<PhoneRootView>!
    private var previewDesktop: DesktopViewController?
    private var cancellables = Set<AnyCancellable>()

    override var canBecomeFirstResponder: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { session.displayState.isConnected || session.previewingOnPhone }
    override var prefersStatusBarHidden: Bool { session.displayState.isConnected || session.previewingOnPhone }

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
                }
            }
            .store(in: &cancellables)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
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
            exit.frame = CGRect(x: 12, y: 36, width: 130, height: 26)
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
