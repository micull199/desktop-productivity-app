import UIKit
import SwiftUI

/// Turns the iPhone's touch screen into a trackpad for the desktop:
/// one finger moves the cursor, a tap clicks, two fingers scroll, two-finger tap right-clicks,
/// and a tap-then-drag performs a drag.
final class TrackpadUIView: UIView {

    private let input = InputRouter.shared
    private var lastPoints: [ObjectIdentifier: CGPoint] = [:]
    private var touchStart: TimeInterval = 0
    private var moved = false
    private var maxTouches = 0
    private var lastTapTime: TimeInterval = 0
    private var dragging = false
    private var dragTimer: Timer?
    private var holdTimer: Timer?
    /// Light tick on tap-click and right-click; cursor movement stays silent.
    private let clickFeedback = UIImpactFeedbackGenerator(style: .light)
    /// Fired when a single finger rests without moving for a moment (used to wake the screen).
    var onLongHold: (() -> Void)?
    /// True for a touch sequence that belongs to the system pointer (AssistiveTouch turns mouse
    /// clicks into touches on this screen) rather than a finger; those are ignored because the
    /// hardware mouse already delivered the same click through GameController.
    private var ignoringSequence = false
    private var pendingTap: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .black
    }

    required init?(coder: NSCoder) { fatalError() }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let all = event?.touches(for: self) ?? touches
        if all.count == touches.count {
            ignoringSequence = touches.contains { $0.type == .indirectPointer } || input.hardwareMouseActive
        }
        if ignoringSequence { return }
        if all.count == touches.count {
            clickFeedback.prepare()
            touchStart = Date().timeIntervalSinceReferenceDate
            moved = false
            maxTouches = 0
            // Tap, then touch again quickly and move: drag (like a trackpad's tap-and-a-half).
            if touchStart - lastTapTime < 0.3 {
                dragging = true
                input.trackpadButton(.left, pressed: true)
            }
        }
        maxTouches = max(maxTouches, all.count)
        for t in touches { lastPoints[ObjectIdentifier(t)] = t.location(in: self) }
        dragTimer?.invalidate()
        holdTimer?.invalidate()
        if all.count == 1 {
            holdTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.moved, !self.dragging else { return }
                    self.onLongHold?()
                }
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if ignoringSequence { return }
        let all = event?.touches(for: self) ?? touches
        let sensitivity = Settings.shared.trackpadSensitivity
        if moved { holdTimer?.invalidate() }
        if all.count >= 2 {
            // Two-finger scroll: average delta.
            var dx: CGFloat = 0, dy: CGFloat = 0, n: CGFloat = 0
            for t in all {
                let p = t.location(in: self)
                if let last = lastPoints[ObjectIdentifier(t)] { dx += p.x - last.x; dy += p.y - last.y; n += 1 }
                lastPoints[ObjectIdentifier(t)] = p
            }
            guard n > 0 else { return }
            dx /= n; dy /= n
            if abs(dx) + abs(dy) > 0.5 { moved = true }
            let natural: CGFloat = Settings.shared.naturalScrolling ? -1 : 1
            input.trackpadScroll(dx: dx * natural * 1.5, dy: dy * natural * 1.5)
        } else if let t = all.first {
            let p = t.location(in: self)
            if let last = lastPoints[ObjectIdentifier(t)] {
                let dx = p.x - last.x, dy = p.y - last.y
                if abs(dx) + abs(dy) > 0.3 { moved = true }
                // Light acceleration so small motions are precise and big ones travel far.
                let speed = hypot(dx, dy)
                let gain = sensitivity * (1 + min(speed / 40, 1.4))
                input.trackpadMove(by: CGPoint(x: dx * gain, y: dy * gain))
            }
            lastPoints[ObjectIdentifier(t)] = p
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { lastPoints[ObjectIdentifier(t)] = nil }
        let remaining = (event?.touches(for: self) ?? []).filter { $0.phase != .ended && $0.phase != .cancelled }
        guard remaining.isEmpty else { return }
        if ignoringSequence { ignoringSequence = false; return }
        holdTimer?.invalidate()
        let duration = Date().timeIntervalSinceReferenceDate - touchStart
        if dragging {
            dragging = false
            input.trackpadButton(.left, pressed: false)
            return
        }
        if !moved, duration < 0.3 {
            clickFeedback.impactOccurred()
            // A mouse click and its AssistiveTouch echo can arrive in either order, so wait a
            // moment and skip the tap if the hardware mouse spoke in the meantime.
            let right = maxTouches >= 2
            if !right { lastTapTime = Date().timeIntervalSinceReferenceDate }
            pendingTap?.cancel()
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.input.trackpadClick(right ? .right : .left)
                }
            }
            pendingTap = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastPoints.removeAll()
        ignoringSequence = false
        if dragging { dragging = false; input.trackpadButton(.left, pressed: false) }
    }
}

struct TrackpadView: UIViewRepresentable {
    var onLongHold: () -> Void = {}

    func makeUIView(context: Context) -> TrackpadUIView {
        let v = TrackpadUIView()
        v.onLongHold = onLongHold
        return v
    }

    func updateUIView(_ uiView: TrackpadUIView, context: Context) {
        uiView.onLongHold = onLongHold
    }
}
