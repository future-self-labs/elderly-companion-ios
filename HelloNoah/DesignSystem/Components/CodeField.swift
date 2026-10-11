import SwiftUI
import UIKit

/// Six digit boxes (pairing code, SMS code) backed by one hidden UIKit text field.
///
/// The UITextField owns the text, so fast typing, key bursts, paste ("940 286", "940-286") and iOS
/// one-time-code autofill never lose characters: input is filtered to ASCII digits and capped at
/// `length` in the delegate, and SwiftUI only mirrors the result. `onComplete` fires once each
/// time the code becomes complete.
struct NoahCodeField: View {
    @Binding var code: String
    var length = 6
    var large = false
    /// Lets iOS suggest a code from Messages (SMS sign-in code, or a pairing code the caregiver
    /// texted with "Stuur de code").
    var isOneTimeCode = true
    var onComplete: (() -> Void)?

    @State private var isFocused = false
    @State private var wantsFocus = false

    var body: some View {
        HStack(spacing: large ? NoahSpacing.s : NoahSpacing.xs) {
            ForEach(0..<length, id: \.self) { index in
                box(index)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .overlay {
            // Covers the boxes: a tap anywhere focuses it; VoiceOver reads it as one field.
            DigitsTextField(
                text: $code,
                length: length,
                isOneTimeCode: isOneTimeCode,
                wantsFocus: wantsFocus,
                isFocused: $isFocused,
                accessibilityLabel: "Code van \(length) cijfers"
            )
            .accessibilityIdentifier("code.field")
        }
        .onChange(of: code) { newValue in
            if newValue.count == length { onComplete?() }
        }
        .onAppear {
            // Focus after the push animation; becoming first responder mid-transition makes
            // NavigationStack transitions stutter.
            afterFirstLayout { wantsFocus = true }
        }
    }

    private func box(_ index: Int) -> some View {
        let digits = Array(code)
        let character = index < digits.count ? String(digits[index]) : ""
        let isCurrent = isFocused && index == min(code.count, length - 1)
        return Text(verbatim: character)
            .font(large ? NoahFont.display(40, relativeTo: .largeTitle) : NoahFont.display(30, relativeTo: .title))
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .foregroundColor(NoahColor.text)
            .frame(maxWidth: .infinity, minHeight: large ? 76 : 60)
            .background(RoundedRectangle(cornerRadius: NoahRadius.medium, style: .continuous).fill(NoahColor.surface))
            .overlay(
                RoundedRectangle(cornerRadius: NoahRadius.medium, style: .continuous)
                    .strokeBorder(isCurrent ? NoahColor.accent : NoahColor.border, lineWidth: isCurrent ? 2 : 1)
            )
    }
}

/// Keeps only ASCII digits, at most `length` of them.
enum DigitsFilter {
    static func apply(_ text: String, length: Int) -> String {
        String(text.filter { $0.isASCII && $0.isNumber }.prefix(length))
    }
}

/// Invisible UITextField for digit codes.
struct DigitsTextField: UIViewRepresentable {
    @Binding var text: String
    let length: Int
    var isOneTimeCode: Bool
    var wantsFocus: Bool
    @Binding var isFocused: Bool
    var accessibilityLabel: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> CodeUITextField {
        let field = CodeUITextField()
        field.keyboardType = .numberPad
        field.textContentType = isOneTimeCode ? .oneTimeCode : nil
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartInsertDeleteType = .no
        field.smartDashesType = .no
        field.smartQuotesType = .no
        field.textColor = .clear
        field.tintColor = .clear
        field.backgroundColor = .clear
        field.borderStyle = .none
        field.accessibilityLabel = accessibilityLabel
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.text = DigitsFilter.apply(text, length: length)
        return field
    }

    func updateUIView(_ field: CodeUITextField, context: Context) {
        context.coordinator.parent = self
        // Only push changes made from outside (e.g. cleared after a wrong code).
        if field.text != text { field.text = DigitsFilter.apply(text, length: length) }
        if wantsFocus, !context.coordinator.didFocus, field.window != nil {
            context.coordinator.didFocus = true
            DispatchQueue.main.async { field.becomeFirstResponder() }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: DigitsTextField
        var didFocus = false

        init(_ parent: DigitsTextField) { self.parent = parent }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let current = textField.text ?? ""
            guard let swiftRange = Range(range, in: current) else { return false }
            let proposed = current.replacingCharacters(in: swiftRange, with: string)
            let filtered = DigitsFilter.apply(proposed, length: parent.length)
            if filtered == proposed { return true } // UIKit applies it; editingChanged follows.
            // Paste/autofill with spaces or dashes, or too many digits: apply the cleaned value.
            textField.text = filtered
            publish(filtered)
            return false
        }

        @objc func editingChanged(_ textField: UITextField) {
            let filtered = DigitsFilter.apply(textField.text ?? "", length: parent.length)
            if textField.text != filtered { textField.text = filtered }
            publish(filtered)
        }

        func textFieldDidBeginEditing(_ textField: UITextField) { parent.isFocused = true }
        func textFieldDidEndEditing(_ textField: UITextField) { parent.isFocused = false }

        private func publish(_ value: String) {
            if parent.text != value { parent.text = value }
        }
    }
}

/// A text field whose caret always sits at the end and whose only menu action is paste.
final class CodeUITextField: UITextField {
    override func caretRect(for position: UITextPosition) -> CGRect { .zero }

    override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] { [] }

    override func closestPosition(to point: CGPoint) -> UITextPosition? { endOfDocument }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        action == #selector(paste(_:))
    }
}
