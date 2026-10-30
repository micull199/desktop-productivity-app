import UIKit
import SwiftUI

/// An invisible text input that lets the iPhone's software keyboard type into the desktop when
/// no hardware keyboard is attached.
final class SoftKeyboardUIView: UIView, UIKeyInput, UITextInputTraits {

    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var keyboardAppearance: UIKeyboardAppearance = .dark
    var returnKeyType: UIReturnKeyType = .default
    var enablesReturnKeyAutomatically = false

    override var canBecomeFirstResponder: Bool { true }

    // Text is never stored locally: `hasText` must be true so the delete key is delivered.
    var hasText: Bool { true }

    func insertText(_ text: String) {
        InputRouter.shared.insertSoftText(text)
    }

    func deleteBackward() {
        InputRouter.shared.softBackspace()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let keyPresses = presses.filter { $0.key != nil }
        if keyPresses.isEmpty { super.pressesBegan(presses, with: event); return }
        InputRouter.shared.pressesBegan(keyPresses)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let keyPresses = presses.filter { $0.key != nil }
        if keyPresses.isEmpty { super.pressesEnded(presses, with: event); return }
        InputRouter.shared.pressesEnded(keyPresses)
    }
}

struct SoftKeyboardBridge: UIViewRepresentable {
    @Binding var isActive: Bool

    func makeUIView(context: Context) -> SoftKeyboardUIView {
        let v = SoftKeyboardUIView()
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: SoftKeyboardUIView, context: Context) {
        DispatchQueue.main.async {
            if isActive, !uiView.isFirstResponder { uiView.becomeFirstResponder() }
            if !isActive, uiView.isFirstResponder {
                uiView.resignFirstResponder()
                // Hand key presses back to the root controller.
                uiView.window?.rootViewController?.becomeFirstResponder()
            }
        }
    }
}
