import SwiftUI

/// Label above + styled box around any input.
struct NoahField<Content: View>: View {
    let label: LocalizedStringKey
    var footnote: LocalizedStringKey?
    var error: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.xs) {
            Text(label)
                .font(NoahFont.semibold(15, relativeTo: .subheadline))
                .foregroundColor(NoahColor.textSoft)
            content()
            if let error {
                Label {
                    Text(verbatim: error)
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                }
                .font(NoahFont.footnote)
                .foregroundColor(NoahColor.dangerText)
            } else if let footnote {
                Text(footnote)
                    .font(NoahFont.footnote)
                    .foregroundColor(NoahColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Visual style of a text input box.
struct NoahInputBox: ViewModifier {
    var isFocused = false
    var hasError = false

    func body(content: Content) -> some View {
        content
            .font(NoahFont.bodyText)
            .foregroundColor(NoahColor.text)
            .padding(.horizontal, NoahSpacing.m)
            .padding(.vertical, NoahSpacing.s)
            .frame(minHeight: NoahSize.button)
            .background(RoundedRectangle(cornerRadius: NoahRadius.medium, style: .continuous).fill(NoahColor.surface))
            .overlay(
                RoundedRectangle(cornerRadius: NoahRadius.medium, style: .continuous)
                    .strokeBorder(hasError ? NoahColor.dangerText : (isFocused ? NoahColor.accent : NoahColor.border), lineWidth: isFocused || hasError ? 2 : 1)
            )
    }
}

extension View {
    func noahInputBox(isFocused: Bool = false, hasError: Bool = false) -> some View {
        modifier(NoahInputBox(isFocused: isFocused, hasError: hasError))
    }
}

/// Capitalisation for `NoahTextField`.
enum NoahCapitalization {
    case sentences, words, characters, never

    var uiKit: UITextAutocapitalizationType {
        switch self {
        case .sentences: return .sentences
        case .words: return .words
        case .characters: return .allCharacters
        case .never: return .none
        }
    }

    var swiftUI: TextInputAutocapitalization {
        switch self {
        case .sentences: return .sentences
        case .words: return .words
        case .characters: return .characters
        case .never: return .never
        }
    }
}

struct NoahTextField: View {
    let label: LocalizedStringKey
    @Binding var text: String
    var prompt: LocalizedStringKey?
    var footnote: LocalizedStringKey?
    var error: String?
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType?
    var autocapitalization: NoahCapitalization = .sentences
    var multiline = false

    @FocusState private var multilineFocused: Bool
    @State private var singleLineFocused = false

    private var noAutocorrect: Bool {
        keyboard == .phonePad || keyboard == .numberPad || contentType == .telephoneNumber
    }

    var body: some View {
        NoahField(label: label, footnote: footnote, error: error) {
            if multiline {
                TextField(label, text: $text, prompt: prompt.map { Text($0) }, axis: .vertical)
                    .lineLimit(3...10)
                    .keyboardType(keyboard)
                    .textContentType(contentType)
                    .textInputAutocapitalization(autocapitalization.swiftUI)
                    .autocorrectionDisabled(noAutocorrect)
                    .focused($multilineFocused)
                    .noahInputBox(isFocused: multilineFocused, hasError: error != nil)
                    .accessibilityHint(footnote.map { Text($0) } ?? Text(""))
            } else {
                // UIKit-backed: the text field owns its text, so fast typing, key bursts and
                // autofill never lose characters when the surrounding SwiftUI view re-renders.
                NoahSingleLineField(
                    text: $text,
                    isFocused: $singleLineFocused,
                    keyboard: keyboard,
                    contentType: contentType,
                    autocapitalization: autocapitalization.uiKit,
                    autocorrection: noAutocorrect ? .no : .default
                )
                .overlay(alignment: .leading) {
                    if text.isEmpty, let prompt {
                        Text(prompt)
                            .font(NoahFont.bodyText)
                            .foregroundColor(NoahColor.textSecondary.opacity(0.75))
                            .lineLimit(1)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .noahInputBox(isFocused: singleLineFocused, hasError: error != nil)
                .accessibilityLabel(Text(label))
                .accessibilityHint(footnote.map { Text($0) } ?? Text(""))
            }
        }
    }
}

/// Single-line UITextField styled with the design tokens (Lexend, Dynamic Type).
struct NoahSingleLineField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var keyboard: UIKeyboardType
    var contentType: UITextContentType?
    var autocapitalization: UITextAutocapitalizationType
    var autocorrection: UITextAutocorrectionType

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        let base = UIFont(name: NoahFontFamily.body, size: 17) ?? .preferredFont(forTextStyle: .body)
        field.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
        field.adjustsFontForContentSizeCategory = true
        field.textColor = UIColor(NoahColor.text)
        field.tintColor = UIColor(NoahColor.accent)
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.returnKeyType = .done
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.text = text
        configure(field)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        configure(field)
    }

    private func configure(_ field: UITextField) {
        if field.keyboardType != keyboard { field.keyboardType = keyboard }
        if field.textContentType != contentType { field.textContentType = contentType }
        if field.autocapitalizationType != autocapitalization { field.autocapitalizationType = autocapitalization }
        if field.autocorrectionType != autocorrection { field.autocorrectionType = autocorrection }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NoahSingleLineField
        init(_ parent: NoahSingleLineField) { self.parent = parent }

        @objc func editingChanged(_ field: UITextField) {
            let value = field.text ?? ""
            if parent.text != value { parent.text = value }
        }

        func textFieldDidBeginEditing(_ textField: UITextField) { parent.isFocused = true }
        func textFieldDidEndEditing(_ textField: UITextField) { parent.isFocused = false }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

/// Edits a list of short strings (likes, topics, people's names) as removable chips.
struct NoahTagEditor: View {
    let label: LocalizedStringKey
    @Binding var tags: [String]
    var prompt: LocalizedStringKey = "Typ en tik op Toevoegen"
    var footnote: LocalizedStringKey?

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        NoahField(label: label, footnote: footnote) {
            VStack(alignment: .leading, spacing: NoahSpacing.s) {
                if !tags.isEmpty {
                    FlowLayout {
                        ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                            Button {
                                tags.remove(at: index)
                            } label: {
                                HStack(spacing: NoahSpacing.xxs) {
                                    Text(verbatim: tag)
                                    Image(systemName: "xmark")
                                        .font(NoahFont.caption)
                                }
                                .font(NoahFont.subheadline)
                                .foregroundColor(NoahColor.text)
                                .padding(.horizontal, NoahSpacing.s)
                                .frame(minHeight: NoahSize.minTap)
                                .background(Capsule().fill(NoahColor.surfaceDeep))
                                .overlay(Capsule().strokeBorder(NoahColor.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("\(tag), verwijderen"))
                        }
                    }
                }
                HStack(spacing: NoahSpacing.xs) {
                    TextField(label, text: $draft, prompt: Text(prompt))
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(add)
                        .noahInputBox(isFocused: focused)
                    Button(action: add) {
                        Text("Toevoegen")
                    }
                    .buttonStyle(.noah(.secondary, size: .compact, fullWidth: false))
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func add() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if !tags.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
            tags.append(value)
        }
        draft = ""
    }
}

/// A large option card for single choice (e.g. "u" / "jij"), at least 44 pt tall.
struct NoahOptionCard: View {
    let title: String
    var subtitle: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: NoahSpacing.s) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(NoahFont.title3)
                    .foregroundColor(isSelected ? NoahColor.accent : NoahColor.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: NoahSpacing.xxs) {
                    Text(verbatim: title)
                        .font(NoahFont.bodyStrong)
                        .foregroundColor(NoahColor.text)
                    if let subtitle {
                        Text(verbatim: subtitle)
                            .font(NoahFont.subheadline)
                            .foregroundColor(NoahColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(NoahSpacing.m)
            .frame(minHeight: NoahSize.button)
            .background(RoundedRectangle(cornerRadius: NoahRadius.medium, style: .continuous).fill(isSelected ? NoahColor.accentGlow : NoahColor.surface))
            .overlay(RoundedRectangle(cornerRadius: NoahRadius.medium, style: .continuous).strokeBorder(isSelected ? NoahColor.accent : NoahColor.border, lineWidth: isSelected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
