import UIKit

/// A view that reacts to the desktop's virtual mouse cursor.
///
/// The external display never receives touches, so the desktop performs its own hit-testing
/// and delivers `PointerEvent`s to the nearest `PointerTarget` ancestor of the hit view.
@MainActor
protocol PointerTarget: AnyObject {
    /// `local` is the event location converted into the target view's coordinate space.
    func pointer(_ event: PointerEvent, local: CGPoint)
    func pointerEntered()
    func pointerExited()
    func cursorStyle(at local: CGPoint) -> CursorStyle
}

extension PointerTarget {
    func pointerEntered() {}
    func pointerExited() {}
    func cursorStyle(at local: CGPoint) -> CursorStyle { .arrow }
}

/// Something that can receive keyboard events.
@MainActor
protocol KeyTarget: AnyObject {
    /// Return `true` when the event was consumed.
    func key(_ event: KeyEvent) -> Bool
}

/// A keyboard-focusable control (text fields, editors, lists).
@MainActor
protocol Focusable: KeyTarget {
    func setFocused(_ focused: Bool)
}

/// Tracks which control inside a window currently has keyboard focus.
@MainActor
final class FocusGroup {
    private(set) weak var current: (UIView & Focusable)?

    func focus(_ target: (UIView & Focusable)?) {
        guard current !== target else { return }
        current?.setFocused(false)
        current = target
        target?.setFocused(true)
    }

    func blur() { focus(nil) }

    @discardableResult
    func key(_ event: KeyEvent) -> Bool {
        current?.key(event) ?? false
    }
}
