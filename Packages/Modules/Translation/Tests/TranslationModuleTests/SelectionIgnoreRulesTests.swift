import Testing
@testable import TranslationModule

@Suite struct SelectionIgnoreRulesTests {
    let safari = FocusedApplication(processID: 42, bundleID: "com.apple.Safari")

    func selection(_ text: String, in application: FocusedApplication? = nil) -> SelectionSource {
        SelectionSource(text: text, application: application ?? safari)
    }

    // MARK: application

    @Test func anOrdinaryAppIsRead() {
        #expect(SelectionIgnoreRules.application(safari, ownProcessID: 1, denyList: []) == nil)
        #expect(SelectionIgnoreRules.application(safari, ownProcessID: 1, denyList: ["com.apple.Notes"]) == nil)
    }

    @Test func myNotchsOwnWindowsAreNeverRead() {
        let mine = FocusedApplication(processID: 99, bundleID: "io.lucasvu.mynotch")
        #expect(SelectionIgnoreRules.application(mine, ownProcessID: 99, denyList: []) == .ownApplication)
    }

    @Test func anAppOnTheDenyListIsNeverRead() {
        #expect(SelectionIgnoreRules.application(safari, ownProcessID: 1, denyList: ["com.apple.Notes", "com.apple.Safari"]) == .deniedApplication)
    }

    @Test func theDenyListIsMatchedWithoutRegardToCase() {
        #expect(SelectionIgnoreRules.application(safari, ownProcessID: 1, denyList: ["COM.APPLE.SAFARI"]) == .deniedApplication)
    }

    @Test(arguments: [
        "com.1password.1password", "com.agilebits.onepassword7", "com.agilebits.onepassword-osx", "com.bitwarden.desktop",
        "com.apple.keychainaccess", "com.apple.Passwords", "org.keepassxc.keepassxc", "COM.APPLE.PASSWORDS",
    ])
    func aPasswordManagerIsNeverReadWithoutAnyoneAskingForThat(bundleID: String) {
        let manager = FocusedApplication(processID: 8, bundleID: bundleID)
        #expect(SelectionIgnoreRules.application(manager, ownProcessID: 1, denyList: []) == .deniedApplication)
    }

    @Test func anAppWithNoBundleIDCannotBeDenied() {
        let unnamed = FocusedApplication(processID: 7, bundleID: nil)
        #expect(SelectionIgnoreRules.application(unnamed, ownProcessID: 1, denyList: ["", "com.apple.Safari"]) == nil)
    }

    // MARK: length, known before the text is fetched

    @Test func aKnownEmptyRangeIsEmptyAndAKnownLongOneIsTooLong() {
        #expect(SelectionIgnoreRules.length(0) == .empty)
        #expect(SelectionIgnoreRules.length(1) == nil)
        #expect(SelectionIgnoreRules.length(2_000) == nil)
        #expect(SelectionIgnoreRules.length(2_001) == .tooLong)
        #expect(SelectionIgnoreRules.length(50_000_000) == .tooLong)
    }

    @Test func anUnknownLengthIsLeftToTheText() {
        #expect(SelectionIgnoreRules.length(nil) == nil)
    }

    // MARK: text

    @Test func blankTextIsEmpty() {
        #expect(SelectionIgnoreRules.text(selection(""), lastHandled: nil) == .empty)
        #expect(SelectionIgnoreRules.text(selection(" \n\t "), lastHandled: nil) == .empty)
    }

    @Test func twoThousandCharactersAreFineAndOneMoreIsTooLong() {
        #expect(SelectionIgnoreRules.text(selection(String(repeating: "a", count: 2_000)), lastHandled: nil) == nil)
        #expect(SelectionIgnoreRules.text(selection(String(repeating: "a", count: 2_001)), lastHandled: nil) == .tooLong)
    }

    @Test func theSelectionAlreadyHandledIsUnchanged() {
        let shown = selection("Hello world")
        #expect(SelectionIgnoreRules.text(selection("Hello world"), lastHandled: shown) == .unchanged)
        #expect(SelectionIgnoreRules.text(selection("Hello world!"), lastHandled: shown) == nil)
        // The same words in another app are another selection.
        let notes = FocusedApplication(processID: 43, bundleID: "com.apple.Notes")
        #expect(SelectionIgnoreRules.text(selection("Hello world", in: notes), lastHandled: shown) == nil)
        #expect(SelectionIgnoreRules.text(selection("Hello world"), lastHandled: nil) == nil)
    }

    // MARK: password fields

    @Test func aPasswordFieldIsRecognisedByRoleOrSubrole() {
        #expect(SecureTextField.matches(role: "AXTextField", subrole: "AXSecureTextField"))
        #expect(SecureTextField.matches(role: "AXSecureTextField", subrole: nil))
        #expect(SecureTextField.matches(role: "AXSecureTextField", subrole: "AXSecureTextField"))
        #expect(!SecureTextField.matches(role: "AXTextField", subrole: nil))
        #expect(!SecureTextField.matches(role: "AXTextArea", subrole: "AXSearchField"))
        #expect(!SecureTextField.matches(role: nil, subrole: nil))
    }
}
