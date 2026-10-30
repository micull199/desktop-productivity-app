import UIKit
import QuartzCore

/// Thread-safe accumulator for raw mouse events.
///
/// GameController delivers mouse input on a background queue at the device's polling rate (a gaming
/// mouse reports 1000 times a second). Handling each report on the main thread meant a full
/// hit-test, hover update and web-view round trip per report, which is what made the cursor feel
/// laggy. Instead the handlers push into this buffer and `InputRouter` drains it once per display
/// frame, coalescing movement so the desktop does one hit-test per frame.
///
/// It also drops duplicates: the same physical mouse can be exposed as two `GCMouse` objects (for
/// example a wireless mouse and its dongle), each reporting every event.
final class RawInputBuffer: @unchecked Sendable {

    enum Event {
        case move(dx: CGFloat, dy: CGFloat)
        case button(PointerButton, pressed: Bool)
        case wheel(dx: CGFloat, dy: CGFloat)
    }

    private let lock = NSLock()
    private var events: [Event] = []
    private var lastMove: (dx: CGFloat, dy: CGFloat, time: TimeInterval, source: ObjectIdentifier)?
    private var lastButton: (button: PointerButton, pressed: Bool, time: TimeInterval, source: ObjectIdentifier)?
    private var activity: TimeInterval = 0
    private var dropped = 0

    func pushMove(dx: CGFloat, dy: CGFloat, from source: ObjectIdentifier) {
        let now = CACurrentMediaTime()
        lock.lock(); defer { lock.unlock() }
        if let last = lastMove, last.source != source, now - last.time < 0.002, last.dx == dx, last.dy == dy {
            dropped += 1
            return
        }
        lastMove = (dx, dy, now, source)
        activity = now
        if case .move(let x, let y)? = events.last {
            events[events.count - 1] = .move(dx: x + dx, dy: y + dy)
        } else {
            events.append(.move(dx: dx, dy: dy))
        }
    }

    func pushButton(_ button: PointerButton, pressed: Bool, from source: ObjectIdentifier) {
        let now = CACurrentMediaTime()
        lock.lock(); defer { lock.unlock() }
        if let last = lastButton, last.source != source, last.button == button, last.pressed == pressed, now - last.time < 0.03 {
            dropped += 1
            return
        }
        lastButton = (button, pressed, now, source)
        activity = now
        events.append(.button(button, pressed: pressed))
    }

    func pushWheel(dx: CGFloat, dy: CGFloat) {
        lock.lock(); defer { lock.unlock() }
        activity = CACurrentMediaTime()
        if case .wheel(let x, let y)? = events.last {
            events[events.count - 1] = .wheel(dx: x + dx, dy: y + dy)
        } else {
            events.append(.wheel(dx: dx, dy: dy))
        }
    }

    /// Returns and clears everything received since the last drain, in order.
    func drain() -> [Event] {
        lock.lock(); defer { lock.unlock() }
        let out = events
        events.removeAll(keepingCapacity: true)
        return out
    }

    /// `CACurrentMediaTime()` of the most recent hardware mouse report.
    var lastActivity: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return activity
    }

    var duplicatesDropped: Int {
        lock.lock(); defer { lock.unlock() }
        return dropped
    }
}

/// Calls a closure on every screen refresh (60–120 Hz) from the main run loop.
final class FrameClock {

    private final class Target: NSObject {
        var onFrame: (() -> Void)?
        @objc func tick(_ link: CADisplayLink) { onFrame?() }
    }

    private let target = Target()
    private var link: CADisplayLink?

    init(onFrame: @escaping () -> Void) {
        target.onFrame = onFrame
        let link = CADisplayLink(target: target, selector: #selector(Target.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func invalidate() {
        link?.invalidate()
        link = nil
    }
}
