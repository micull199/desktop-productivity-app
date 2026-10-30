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
        // Run the monitor at its native mode; a 4K display gets a 2× desktop drawn at full pixel density.
        _ = UIView.installDesktopContentScaleHook
        let size = windowScene.coordinateSpace.bounds.size
        DesktopSession.shared.log("Display native \(Int(size.width))×\(Int(size.height)) · desktop scale \(Int(ScaledHostViewController.scale(for: size)))×")

        let desktop = DesktopViewController()
        let host = ScaledHostViewController(child: desktop)
        let window = DesktopWindow(windowScene: windowScene)
        window.contentScale = ScaledHostViewController.scale(for: size)
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
        (window as? DesktopWindow)?.contentScale = ScaledHostViewController.scale(for: size)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        desktop?.desktopWillDisconnect()
        desktop = nil
        host = nil
        window = nil
        DesktopSession.shared.externalDisplayDidDisconnect()
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
        (view.window as? DesktopWindow)?.contentScale = s
        let logical = CGSize(width: (b.width / s).rounded(.down), height: (b.height / s).rounded(.down))
        child.view.transform = .identity
        child.view.bounds = CGRect(origin: .zero, size: logical)
        child.view.center = CGPoint(x: b.midX, y: b.midY)
        child.view.transform = CGAffineTransform(scaleX: s, y: s)
    }
}
