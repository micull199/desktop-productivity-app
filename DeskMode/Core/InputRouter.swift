import UIKit
import GameController

/// Receives pointer and keyboard input for the desktop.
@MainActor
protocol InputSink: AnyObject {
    func handlePointer(_ event: PointerEvent)
    func handleKey(_ event: KeyEvent)
}

/// Collects raw input from every source (Bluetooth/USB mouse via GameController, hardware
/// keyboard via UIKit presses, the iPhone's touch screen acting as a trackpad, the software
/// keyboard bridge) and turns it into a single stream of desktop events.
///
/// Because the external display is non-interactive, no touches ever reach it. The router keeps
/// the authoritative cursor position and the desktop draws it.
@MainActor
final class InputRouter: ObservableObject {

    static let shared = InputRouter()

    @Published private(set) var cursor = CGPoint(x: 200, y: 200)
    @Published private(set) var mouseConnected = false
    @Published private(set) var keyboardConnected = false
    @Published private(set) var modifiers: UIKeyModifierFlags = []

    /// Bounds in which the cursor may move (the external window's bounds).
    var desktopBounds = CGRect(x: 0, y: 0, width: 1920, height: 1080) {
        didSet { cursor = clamp(cursor) }
    }

    weak var sink: InputSink?

    private var started = false
    private var observedMice: [ObjectIdentifier: GCMouse] = [:]

    // Click-count detection.
    private var lastClickTime: TimeInterval = 0
    private var lastClickPoint = CGPoint.zero
    private var lastClickButton: PointerButton?
    private var clickCount = 1

    // Key repeat.
    private var repeatTimer: Timer?
    private var repeatingEvent: KeyEvent?

    private var settings: Settings { Settings.shared }

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(mouseDidConnect(_:)), name: .GCMouseDidConnect, object: nil)
        nc.addObserver(self, selector: #selector(mouseDidDisconnect(_:)), name: .GCMouseDidDisconnect, object: nil)
        nc.addObserver(self, selector: #selector(keyboardDidConnect(_:)), name: .GCKeyboardDidConnect, object: nil)
        nc.addObserver(self, selector: #selector(keyboardDidDisconnect(_:)), name: .GCKeyboardDidDisconnect, object: nil)

        for mouse in GCMouse.mice() { attach(mouse) }
        keyboardConnected = GCKeyboard.coalesced != nil
    }

    // MARK: - Mouse (GameController)

    @objc private func mouseDidConnect(_ note: Notification) {
        guard let mouse = note.object as? GCMouse else { return }
        attach(mouse)
    }

    @objc private func mouseDidDisconnect(_ note: Notification) {
        guard let mouse = note.object as? GCMouse else { return }
        observedMice[ObjectIdentifier(mouse)] = nil
        mouseConnected = !observedMice.isEmpty
    }

    @objc private func keyboardDidConnect(_ note: Notification) { keyboardConnected = true }
    @objc private func keyboardDidDisconnect(_ note: Notification) { keyboardConnected = GCKeyboard.coalesced != nil }

    private func attach(_ mouse: GCMouse) {
        observedMice[ObjectIdentifier(mouse)] = mouse
        mouseConnected = true
        mouse.handlerQueue = .main
        guard let input = mouse.mouseInput else { return }

        input.mouseMovedHandler = { [weak self] _, dx, dy in
            MainActor.assumeIsolated {
                self?.mouseMoved(dx: CGFloat(dx), dy: CGFloat(dy))
            }
        }
        input.leftButton.pressedChangedHandler = { [weak self] _, _, pressed in
            MainActor.assumeIsolated { self?.button(.left, pressed: pressed) }
        }
        input.rightButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            MainActor.assumeIsolated { self?.button(.right, pressed: pressed) }
        }
        input.middleButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            MainActor.assumeIsolated { self?.button(.middle, pressed: pressed) }
        }
        input.scroll.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated { self?.wheel(dx: CGFloat(x), dy: CGFloat(y)) }
        }
    }

    private func mouseMoved(dx: CGFloat, dy: CGFloat) {
        // GameController reports a positive deltaY for upward motion; screen space grows downward.
        let direction: CGFloat = settings.invertMouseY ? 1 : -1
        moveCursor(by: CGPoint(x: dx * settings.cursorSpeed, y: dy * direction * settings.cursorSpeed))
    }

    private func wheel(dx: CGFloat, dy: CGFloat) {
        // One wheel notch ≈ 1.0; convert to points. Natural scrolling flips the direction.
        let scale: CGFloat = 36
        let natural: CGFloat = settings.naturalScrolling ? 1 : -1
        scroll(dx: -dx * scale * natural, dy: -dy * scale * natural)
    }

    // MARK: - Public input entry points (also used by the touch trackpad)

    func moveCursor(by delta: CGPoint) {
        let next = clamp(CGPoint(x: cursor.x + delta.x, y: cursor.y + delta.y))
        guard next != cursor else { return }
        cursor = next
        emit(.move)
    }

    func moveCursor(to point: CGPoint) {
        cursor = clamp(point)
        emit(.move)
    }

    func button(_ button: PointerButton, pressed: Bool) {
        if pressed {
            let now = Date().timeIntervalSinceReferenceDate
            let near = hypot(cursor.x - lastClickPoint.x, cursor.y - lastClickPoint.y) < 6
            if lastClickButton == button, now - lastClickTime < 0.4, near {
                clickCount = min(clickCount + 1, 3)
            } else {
                clickCount = 1
            }
            lastClickTime = now
            lastClickPoint = cursor
            lastClickButton = button
            emit(.down(button))
        } else {
            emit(.up(button))
        }
    }

    func click(_ button: PointerButton = .left) {
        self.button(button, pressed: true)
        self.button(button, pressed: false)
    }

    func scroll(dx: CGFloat, dy: CGFloat) {
        guard dx != 0 || dy != 0 else { return }
        emit(.scroll(dx: dx, dy: dy))
    }

    private func emit(_ kind: PointerEventKind) {
        let event = PointerEvent(kind: kind,
                                 location: cursor,
                                 modifiers: modifiers,
                                 clickCount: clickCount,
                                 timestamp: Date().timeIntervalSinceReferenceDate)
        sink?.handlePointer(event)
    }

    private func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, desktopBounds.minX), desktopBounds.maxX - 1),
                y: min(max(p.y, desktopBounds.minY), desktopBounds.maxY - 1))
    }

    // MARK: - Keyboard (UIKit presses forwarded by the phone scene)

    func pressesBegan(_ presses: Set<UIPress>) {
        for press in presses {
            guard let key = press.key else { continue }
            keyboardConnected = true
            modifiers = key.modifierFlags
            let event = KeyEvent(phase: .down,
                                 characters: key.characters,
                                 charactersIgnoringModifiers: key.charactersIgnoringModifiers,
                                 keyCode: key.keyCode,
                                 modifiers: key.modifierFlags,
                                 isRepeat: false)
            sink?.handleKey(event)
            if !event.isModifierKey { startRepeat(event) }
        }
    }

    func pressesEnded(_ presses: Set<UIPress>) {
        for press in presses {
            guard let key = press.key else { continue }
            modifiers = key.modifierFlags
            if let r = repeatingEvent, r.keyCode == key.keyCode { stopRepeat() }
            let event = KeyEvent(phase: .up,
                                 characters: key.characters,
                                 charactersIgnoringModifiers: key.charactersIgnoringModifiers,
                                 keyCode: key.keyCode,
                                 modifiers: key.modifierFlags,
                                 isRepeat: false)
            sink?.handleKey(event)
            if event.isModifierKey { modifiers.remove(modifierFlag(for: key.keyCode)) }
        }
    }

    func pressesCancelled(_ presses: Set<UIPress>) {
        stopRepeat()
        modifiers = []
    }

    /// Text typed on the software keyboard (no hardware keyboard attached).
    func insertSoftText(_ text: String) {
        for ch in text {
            let s = String(ch)
            let code: UIKeyboardHIDUsage = (s == "\n") ? .keyboardReturnOrEnter : .keyboardA
            let event = KeyEvent(phase: .down, characters: s == "\n" ? "\r" : s,
                                 charactersIgnoringModifiers: s == "\n" ? "\r" : s,
                                 keyCode: code, modifiers: [], isRepeat: false)
            sink?.handleKey(event)
            sink?.handleKey(KeyEvent(phase: .up, characters: event.characters,
                                     charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                                     keyCode: code, modifiers: [], isRepeat: false))
        }
    }

    func softBackspace() {
        let down = KeyEvent(phase: .down, characters: "\u{8}", charactersIgnoringModifiers: "\u{8}",
                            keyCode: .keyboardDeleteOrBackspace, modifiers: [], isRepeat: false)
        sink?.handleKey(down)
        sink?.handleKey(KeyEvent(phase: .up, characters: "\u{8}", charactersIgnoringModifiers: "\u{8}",
                                 keyCode: .keyboardDeleteOrBackspace, modifiers: [], isRepeat: false))
    }

    private func modifierFlag(for code: UIKeyboardHIDUsage) -> UIKeyModifierFlags {
        switch code {
        case .keyboardLeftShift, .keyboardRightShift: return .shift
        case .keyboardLeftControl, .keyboardRightControl: return .control
        case .keyboardLeftAlt, .keyboardRightAlt: return .alternate
        case .keyboardLeftGUI, .keyboardRightGUI: return .command
        case .keyboardCapsLock: return .alphaShift
        default: return []
        }
    }

    private func startRepeat(_ event: KeyEvent) {
        stopRepeat()
        repeatingEvent = event
        let repeated = KeyEvent(phase: .down, characters: event.characters,
                                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                                keyCode: event.keyCode, modifiers: event.modifiers, isRepeat: true)
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.repeatingEvent != nil else { return }
                self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.045, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sink?.handleKey(repeated) }
                }
            }
        }
    }

    private func stopRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        repeatingEvent = nil
    }
}
