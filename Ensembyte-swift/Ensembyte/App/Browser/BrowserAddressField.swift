import AppKit
import SwiftUI

/// The address bar's keyboard: the text field's own focus and its selection.
///
/// The field is an AppKit one, so a focus request can move the keyboard into it and
/// select what is in it, the way a browser's address bar does when it is told to
/// focus. The panel asks for it through the page's `focusAddress()`.
@MainActor
final class BrowserAddressController {
    /// The field showing this tab's address, once it is in a window.
    private weak var field: NSTextField?

    func attach(_ field: NSTextField) {
        self.field = field
    }

    /// Takes the keyboard and selects the address, so the next keystroke replaces it.
    func focus() {
        guard let field else { return }
        guard let window = field.window else {
            // The panel has only just opened and the field is not in a window yet; the
            // next turn of the run loop finds it there. Bounded, so a field that never
            // arrives stops asking.
            guard !isWaitingForWindow else { return }
            isWaitingForWindow = true
            DispatchQueue.main.async { [weak self] in
                self?.isWaitingForWindow = false
                self?.focus()
            }
            return
        }
        window.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    private var isWaitingForWindow = false
}

/// The address field: an AppKit text field bound to the tab's own text, with Return
/// submitting and Escape putting the loaded address back.
struct BrowserAddressField: NSViewRepresentable {
    let page: BrowserPageModel
    let placeholder: String
    let onSubmit: () -> Void
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(page: page, onSubmit: onSubmit, onEscape: onEscape)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12.5)
        field.lineBreakMode = .byTruncatingMiddle
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor(Chrome.secondaryText),
                .font: NSFont.systemFont(ofSize: 12.5),
            ]
        )
        field.stringValue = page.addressText
        page.addressField.attach(field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.page = page
        // The page owns the text (a load rewrites it), so the field follows it — but
        // not while the user is typing in it, which the page has already heard about.
        if field.currentEditor() == nil && field.stringValue != page.addressText {
            field.stringValue = page.addressText
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var page: BrowserPageModel
        let onSubmit: () -> Void
        let onEscape: () -> Void

        init(page: BrowserPageModel, onSubmit: @escaping () -> Void, onEscape: @escaping () -> Void) {
            self.page = page
            self.onSubmit = onSubmit
            self.onEscape = onEscape
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            page.addressText = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                onEscape()
                return true
            default:
                return false
            }
        }
    }
}
