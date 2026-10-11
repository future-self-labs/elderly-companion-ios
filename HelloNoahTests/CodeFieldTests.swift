import SwiftUI
import XCTest
@testable import HelloNoah

final class DigitsFilterTests: XCTestCase {
    func testKeepsOnlyAsciiDigitsCappedAtLength() {
        XCTAssertEqual(DigitsFilter.apply("940286", length: 6), "940286")
        XCTAssertEqual(DigitsFilter.apply("940 286", length: 6), "940286", "pasted with a space")
        XCTAssertEqual(DigitsFilter.apply("940-286", length: 6), "940286", "pasted with a dash")
        XCTAssertEqual(DigitsFilter.apply("Je code is 940286.", length: 6), "940286", "pasted sentence")
        XCTAssertEqual(DigitsFilter.apply("94028612", length: 6), "940286", "capped")
        XCTAssertEqual(DigitsFilter.apply("٩٤٠", length: 6), "", "non-ASCII digits are dropped")
        XCTAssertEqual(DigitsFilter.apply("", length: 6), "")
    }

    /// Feeds a burst of single-key edits through the same delegate logic the field uses.
    func testBurstOfKeystrokesKeepsEveryDigit() {
        let field = CodeUITextField()
        var bound = ""
        var focused = false
        let representable = DigitsTextField(
            text: Binding(get: { bound }, set: { bound = $0 }),
            length: 6, isOneTimeCode: true, wantsFocus: false,
            isFocused: Binding(get: { focused }, set: { focused = $0 }),
            accessibilityLabel: "Code"
        )
        let coordinator = representable.makeCoordinator()
        for character in "940286" {
            let current = field.text ?? ""
            let range = NSRange(location: current.utf16.count, length: 0)
            if coordinator.textField(field, shouldChangeCharactersIn: range, replacementString: String(character)) {
                field.text = current + String(character)
                coordinator.editingChanged(field)
            }
        }
        XCTAssertEqual(field.text, "940286")
        XCTAssertEqual(bound, "940286")

        // A 7th digit is refused; a paste replaces everything with the cleaned code.
        XCTAssertFalse(coordinator.textField(field, shouldChangeCharactersIn: NSRange(location: 6, length: 0), replacementString: "1"))
        XCTAssertEqual(bound, "940286")
        _ = coordinator.textField(field, shouldChangeCharactersIn: NSRange(location: 0, length: 6), replacementString: "123 456")
        XCTAssertEqual(field.text, "123456")
        XCTAssertEqual(bound, "123456")
    }
}
