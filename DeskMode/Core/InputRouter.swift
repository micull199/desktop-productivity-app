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

    /// Not published on purpose: it changes up to 120 times a second and nothing in SwiftUI needs it.
    private(set) var cursor = CGPoint(x: 200, y: 200)
    @Published private(set) var mouseConnected = false
    /// True once a hardware mouse has actually moved the cursor. On iPhone iOS only forwards
    /// mouse movement to apps while AssistiveTouch is enabled, so a connected-but-silent mouse
    /// almost always means that setting is off.
    @Published private(set) var mouseMovementSeen = false
    private var silentMouseTimer: Timer?
    @Published private(set) var keyboardConnected = false
    @Published private(set) var modifiers: UIKeyModifierFlags = []

    /// Bounds in which the cursor may move (the external window's bounds).
    var desktopBounds = CGRect(x: 0, y: 0, width: 1920, height: 1080) {
        didSet { cursor = clamp(cursor) }
    }

    weak var sink: InputSink?

    private var started = false
    private var observedMice: [ObjectIdentifier: GCMouse] = [:]
    /// Raw mouse reports land here from GameController's queue and are drained once per frame.
    private let rawInput = RawInputBuffer()
    private static let inputQueue = DispatchQueue(label: "com.micull.DeskMode.input", qos: .userInteractive)
    private var frameClock: FrameClock?
    private var loggedDuplicates = false
    private var observedKeyboards: [ObjectIdentifier: GCKeyboard] = [:]
    /// True once GameController has delivered a key: UIKit presses are then ignored to avoid doubles.
    private(set) var gameControllerKeyboardActive = false
    private var gcModifiers: UIKeyModifierFlags = []
    /// When the hardware mouse last moved the cursor via GameController (for the hover fallback).
    private(set) var lastHardwareMouseMove: TimeInterval = 0
    private var loggedFirstPress = false
    private var loggedFirstGCKey = false
    private var loggedFirstMouseMove = false
    private var log: (String) -> Void { { DesktopSession.shared.log($0) } }

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

        frameClock = FrameClock { [weak self] in
            MainActor.assumeIsolated { self?.drainRawInput() }
        }
        for mouse in GCMouse.mice() { attach(mouse) }
        if let kb = GCKeyboard.coalesced { attach(kb) }
        keyboardConnected = GCKeyboard.coalesced != nil
        log("Input started · mice \(GCMouse.mice().count) · keyboard \(GCKeyboard.coalesced != nil)")
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
        log("Mouse disconnected (GameController)")
    }

    @objc private func keyboardDidConnect(_ note: Notification) {
        keyboardConnected = true
        if let kb = note.object as? GCKeyboard { attach(kb) }
        log("Keyboard connected (GameController)")
    }

    @objc private func keyboardDidDisconnect(_ note: Notification) {
        if let kb = note.object as? GCKeyboard { observedKeyboards[ObjectIdentifier(kb)] = nil }
        keyboardConnected = GCKeyboard.coalesced != nil
        if observedKeyboards.isEmpty { gameControllerKeyboardActive = false; gcModifiers = [] }
        log("Keyboard disconnected (GameController)")
    }

    // MARK: - Keyboard (GameController)

    /// GameController reports every key regardless of which view is first responder, so it is
    /// the primary source; the UIKit presses below remain as a fallback.
    private func attach(_ keyboard: GCKeyboard) {
        guard observedKeyboards[ObjectIdentifier(keyboard)] == nil else { return }
        observedKeyboards[ObjectIdentifier(keyboard)] = keyboard
        keyboard.handlerQueue = .main
        keyboard.keyboardInput?.keyChangedHandler = { [weak self] _, _, keyCode, pressed in
            MainActor.assumeIsolated { self?.gameControllerKey(keyCode, pressed: pressed) }
        }
    }

    private func gameControllerKey(_ gcCode: GCKeyCode, pressed: Bool) {
        guard let code = UIKeyboardHIDUsage(rawValue: gcCode.rawValue) else { return }
        if !loggedFirstGCKey { loggedFirstGCKey = true; log("Key events arriving via GameController") }
        gameControllerKeyboardActive = true
        keyboardConnected = true
        let flag = modifierFlag(for: code)
        if code == .keyboardCapsLock {
            if pressed { gcModifiers.formSymmetricDifference(.alphaShift) }
        } else if !flag.isEmpty {
            if pressed { gcModifiers.insert(flag) } else { gcModifiers.remove(flag) }
        }
        modifiers = gcModifiers
        let text = KeyCharacterMap.text(for: code, modifiers: gcModifiers)
        let event = KeyEvent(phase: pressed ? .down : .up,
                             characters: text.characters,
                             charactersIgnoringModifiers: text.ignoringModifiers,
                             keyCode: code,
                             modifiers: gcModifiers,
                             isRepeat: false)
        if pressed {
            sink?.handleKey(event)
            if !event.isModifierKey { startRepeat(event) }
        } else {
            if let r = repeatingEvent, r.keyCode == code { stopRepeat() }
            sink?.handleKey(event)
        }
    }

    private func attach(_ mouse: GCMouse) {
        guard observedMice[ObjectIdentifier(mouse)] == nil else { return }
        let name = mouse.vendorName ?? "unnamed"
        observedMice[ObjectIdentifier(mouse)] = mouse
        mouseConnected = true
        log("Mouse connected (GameController): \(name) · buttons L\(mouse.mouseInput?.rightButton != nil ? "+R" : "")")
        if !mouseMovementSeen, silentMouseTimer == nil {
            silentMouseTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.silentMouseTimer = nil
                    if self.mouseConnected, !self.mouseMovementSeen {
                        self.log("Mouse connected but no movement for 10 s · AssistiveTouch is probably off")
                    }
                }
            }
        }
        // Reports arrive on a background queue and are buffered; the frame clock drains them on
        // the main thread once per screen refresh.
        mouse.handlerQueue = Self.inputQueue
        guard let input = mouse.mouseInput else { return }
        let buffer = rawInput
        let source = ObjectIdentifier(mouse)
        input.mouseMovedHandler = { _, dx, dy in
            buffer.pushMove(dx: CGFloat(dx), dy: CGFloat(dy), from: source)
        }
        input.leftButton.pressedChangedHandler = { _, _, pressed in
            buffer.pushButton(.left, pressed: pressed, from: source)
        }
        input.rightButton?.pressedChangedHandler = { _, _, pressed in
            buffer.pushButton(.right, pressed: pressed, from: source)
        }
        input.middleButton?.pressedChangedHandler = { _, _, pressed in
            buffer.pushButton(.middle, pressed: pressed, from: source)
        }
        input.scroll.valueChangedHandler = { _, x, y in
            buffer.pushWheel(dx: CGFloat(x), dy: CGFloat(y))
        }
    }

    /// Runs once per display frame: applies everything the mouse reported since the last frame.
    private func drainRawInput() {
        let events = rawInput.drain()
        guard !events.isEmpty else { return }
        for event in events {
            switch event {
            case .move(let dx, let dy): mouseMoved(dx: dx, dy: dy)
            case .button(let b, let pressed): button(b, pressed: pressed)
            case .wheel(let dx, let dy): wheel(dx: dx, dy: dy)
            }
        }
        if !loggedDuplicates, rawInput.duplicatesDropped > 0 {
            loggedDuplicates = true
            log("Dropping duplicate reports: the mouse is exposed as more than one device")
        }
    }

    /// True while a hardware mouse has reported anything in the last second. Used to ignore the
    /// touches AssistiveTouch synthesises on the phone screen for the same clicks and drags.
    var hardwareMouseActive: Bool { CACurrentMediaTime() - rawInput.lastActivity < 1.0 }

    // MARK: - Trackpad (iPhone screen) entry points

    func trackpadMove(by delta: CGPoint) {
        guard !hardwareMouseActive else { return }
        moveCursor(by: delta)
    }

    func trackpadButton(_ b: PointerButton, pressed: Bool) {
        guard !hardwareMouseActive else { return }
        button(b, pressed: pressed)
    }

    func trackpadClick(_ b: PointerButton) {
        guard !hardwareMouseActive else { return }
        click(b)
    }

    func trackpadScroll(dx: CGFloat, dy: CGFloat) {
        guard !hardwareMouseActive else { return }
        scroll(dx: dx, dy: dy)
    }

    private func mouseMoved(dx: CGFloat, dy: CGFloat) {
        lastHardwareMouseMove = Date().timeIntervalSinceReferenceDate
        if !mouseMovementSeen { mouseMovementSeen = true }
        if !loggedFirstMouseMove { loggedFirstMouseMove = true; log("Mouse movement arriving via GameController") }
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

    /// Pointer movement seen on the phone screen (system pointer hovering). Used only while
    /// GameController is not already delivering raw deltas.
    func pointerHovered(delta: CGPoint) {
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastHardwareMouseMove > 0.3 else { return }
        let gain = settings.cursorSpeed * 3
        moveCursor(by: CGPoint(x: delta.x * gain, y: delta.y * gain))
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
        if !loggedFirstPress { loggedFirstPress = true; log("Key events arriving via UIKit presses") }
        guard !gameControllerKeyboardActive else { return }
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
        guard !gameControllerKeyboardActive else { return }
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
