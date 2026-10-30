import UIKit

/// The scene that appears on the external monitor. It hosts the whole desktop.
final class ExternalSceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var desktop: DesktopViewController?
    private var host: ScaledHostViewController?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        // Use every pixel the display offers. Overscan compensation would shrink the desktop.
        windowScene.screen.overscanCompensation = .none
        Self.applyPreferredMode(to: windowScene.screen)

        let desktop = DesktopViewController()
        let host = ScaledHostViewController(child: desktop)
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = host
        window.backgroundColor = .black
        // Do not make this window *key*: hardware keyboard presses must keep flowing to the
        // phone scene, which forwards them through `InputRouter`.
        window.isHidden = false
        self.window = window
        self.desktop = desktop
        self.host = host

        DesktopSession.shared.externalDisplayDidConnect(windowScene, desktop: desktop)
    }

    func windowScene(_ windowScene: UIWindowScene, didUpdate previousCoordinateSpace: UICoordinateSpace,
                     interfaceOrientation previousInterfaceOrientation: UIInterfaceOrientation,
                     traitCollection previousTraitCollection: UITraitCollection) {
        let size = windowScene.coordinateSpace.bounds.size
        guard size != previousCoordinateSpace.bounds.size else { return }
        DesktopSession.shared.externalDisplayDidResize(size: size, scale: windowScene.screen.scale)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        desktop?.desktopWillDisconnect()
        desktop = nil
        host = nil
        window = nil
        DesktopSession.shared.externalDisplayDidDisconnect()
    }

    // MARK: - Display mode

    /// A 4K monitor at 1× makes the desktop microscopic. Ask the screen for a 1080p-class mode;
    /// if it refuses, `ScaledHostViewController` enlarges the desktop instead.
    static func applyPreferredMode(to screen: UIScreen) {
        let session = DesktopSession.shared
        let modes = screen.availableModes
        let current = screen.currentMode.map { "\(Int($0.size.width))×\(Int($0.size.height))" } ?? "?"
        session.log("Display modes: " + modes.map { "\(Int($0.size.width))×\(Int($0.size.height))" }.joined(separator: " ") + " · current \(current)")
        guard let currentMode = screen.currentMode, currentMode.size.width > 2048 else { return }
        // 1080p-class: on a 4K monitor the desktop then looks like a normal 1080p screen.
        let candidates = modes.filter { $0.size.width >= 1280 && $0.size.width <= 2048 }
        guard let chosen = candidates.max(by: { $0.size.width < $1.size.width }) else {
            session.log("No 1080p-class mode offered · will scale the desktop instead")
            return
        }
        screen.currentMode = chosen
        let after = screen.currentMode.map { "\(Int($0.size.width))×\(Int($0.size.height))" } ?? "?"
        session.log("Requested mode \(Int(chosen.size.width))×\(Int(chosen.size.height)) · now \(after)")
    }
}

/// Hosts the desktop and, when the window is very large (4K at 1×), draws it at 2× so the UI is
/// the size it would be on a 1080p monitor. The desktop itself sees only the logical size.
final class ScaledHostViewController: UIViewController {

    let child: UIViewController

    init(child: UIViewController) {
        self.child = child
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addChild(child)
        view.addSubview(child.view)
        child.didMove(toParent: self)
        layoutChild()
    }

    static func scale(for size: CGSize) -> CGFloat {
        size.width >= 3000 || size.height >= 3000 ? 2 : 1
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutChild()
    }

    private func layoutChild() {
        let b = view.bounds
        guard b.width > 0, b.height > 0 else { return }
        let s = Self.scale(for: b.size)
        let logical = CGSize(width: (b.width / s).rounded(.down), height: (b.height / s).rounded(.down))
        child.view.transform = .identity
        child.view.bounds = CGRect(origin: .zero, size: logical)
        child.view.center = CGPoint(x: b.midX, y: b.midY)
        child.view.transform = CGAffineTransform(scaleX: s, y: s)
    }
}
