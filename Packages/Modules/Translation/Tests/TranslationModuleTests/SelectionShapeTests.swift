import Foundation
import Testing
@testable import TranslationModule

/// What is never offered a translation however confident the recognizer is: links, paths, code, logs, identifiers, names,
/// and a user's own language typed without accents. The samples are the ones the recognizer called English with
/// confidence of 0.6 to 1.0 and a chip would have followed.
@Suite struct SelectionShapeTests {
    let candidates: [Locale.Language] = [.vi, .en, .ja, Locale.Language(identifier: "it"), Locale.Language(identifier: "ro")]

    nonisolated static let notProse = [
        // links, addresses, paths
        "https://github.com/apple/swift-evolution/pull/2345",
        "https://example.com/blog/2026/10/why-we-moved-to-swift-concurrency",
        "john.smith@example.com",
        "/Users/ryantruong/Project/MyNotch/Packages",
        "~/Library/Application Support/Claude",
        "./scripts/verify.sh --all",
        "C:\\Users\\ryan\\Documents\\notes.txt",
        "www.example.com/pricing",
        // code
        "for item in items where item.isEnabled",
        "if (user.isAdmin && !user.isBanned) { return }",
        "const result = await fetch(url).then(res => res.json())",
        "SELECT name, email FROM users WHERE active = true",
        "npm install --save-dev typescript",
        "snake_case_variable_name another_one",
        "let value = compute(input)",
        "return value;",
        "{\"name\": \"John\", \"age\": 30}",
        "<div class=\"card\">Hello there</div>",
        "func hello() -> String",
        "print `this` now",
        "std::vector items here",
        "userName and passwordHash",
        // logs
        "2026-10-15 09:12:44 INFO Server started on port 8080",
        "09:12:44 request handled in time",
        "[WARN] cache is nearly full today",
        "ERROR connection refused by the host",
        // hex and ids
        "0x7ffee4b2a9c8 0x7ffee4b2a9d0",
        "deadbeefcafebabe 3f2a9c1e77b0d4a1",
        // names
        "John Smith", "Tim Cook", "Apple Park", "Google Chrome", "New York City",
    ]

    @Test(arguments: notProse)
    func isNotProse(text: String) {
        #expect(!SelectionShape.isProse(text) || !SelectionLanguage.hasEnoughToTranslate(text), "\(text)")
        #expect(SelectionLanguage.source(of: text, target: .vi, candidates: candidates) == nil, "\(text)")
    }

    nonisolated static let prose = [
        "The quick brown fox jumps over the lazy dog",
        "I think we should meet tomorrow morning, if that works for you.",
        "Error: Cannot find module 'express'",
        "Please see https://example.com for the details of this offer",
        "Contact john@example.com if the invoice is wrong",
        "She bought 3 apples, 2 pears and a lemon.",
        "It's a long way to the top if you wanna rock",
        "Where can I buy and/or sell this old guitar?",
        "I love my iPhone and my iPad",
        "Meet me at the U.S. embassy on Monday",
        "Bonjour tout le monde, comment allez-vous aujourd'hui",
        "Guten Morgen, ich hoffe es geht dir gut",
    ]

    @Test(arguments: prose)
    func isProse(text: String) {
        #expect(SelectionShape.isProse(text), "\(text)")
    }

    @Test func aSentenceWithALinkInItStaysProseButTwoThirdsOfItMustBeWords() {
        #expect(SelectionShape.isProse("Please see https://example.com for the details"))
        #expect(!SelectionShape.isProse("https://a.example.com https://b.example.com https://c.example.com see"))
    }

    @Test func punctuationAndDigitsMayNotBeMoreThanAQuarter() {
        #expect(SelectionShape.isProse("Hello, world! How are you?"))
        #expect(!SelectionShape.isProse("ok ?? !! ## -- ** 12 34 hello there"))
    }

    @Test func aNameIsUpToThreeCapitalisedWordsAndNothingElse() {
        #expect(!SelectionShape.isProse("Tim Cook"))
        #expect(SelectionShape.isProse("Tim Cook is the chief executive"))
        #expect(SelectionShape.isProse("Good morning to everyone here"))
    }

    // MARK: Vietnamese without accents

    nonisolated static let unaccentedVietnamese = [
        "toi dang di hoc o truong dai hoc",
        "cam on ban rat nhieu",
        "khong biet nua nhung toi se thu",
        "hom nay troi dep qua, chung ta di choi nhe",
        "minh o day cho ban den nay gio",
    ]

    @Test(arguments: unaccentedVietnamese)
    func vietnameseWithoutAccentsIsRecognisedAsSuch(text: String) {
        #expect(SelectionShape.looksLikeUnaccentedVietnamese(text), "\(text)")
    }

    @Test(arguments: unaccentedVietnamese)
    func vietnameseWithoutAccentsIsNeverPreviewedForAVietnameseUser(text: String) {
        #expect(SelectionLanguage.source(of: text, target: .vi, candidates: candidates) == nil, "\(text)")
    }

    @Test(arguments: [
        "The quick brown fox jumps over the lazy dog",
        "I want to ban rat poison from the den",
        "Questa e la casa di mia madre, ma non e grande",
        "Buongiorno a tutti, oggi andiamo al mare insieme",
        "Het is een mooi huis met een grote tuin",
    ])
    func otherLanguagesWithoutAccentsAreNotMistakenForVietnamese(text: String) {
        #expect(!SelectionShape.looksLikeUnaccentedVietnamese(text), "\(text)")
    }

    @Test func oneStrongWordAloneIsNotEnough() {
        #expect(!SelectionShape.looksLikeUnaccentedVietnamese("Dang it, I forgot my keys again today"))
        #expect(SelectionShape.looksLikeUnaccentedVietnamese("Dang it, khong the nao"))
    }

    @Test func aGuessAboutTextWithNoAccentsForAVietnameseUserNeedsMoreThanUsual() {
        // The usual bar is 0.6; with no accents any guess needs 0.9 and three words.
        #expect(SelectionLanguage.trustsGuessOnUnaccentedText(confidence: 0.9, wordCount: 3))
        #expect(!SelectionLanguage.trustsGuessOnUnaccentedText(confidence: 0.89, wordCount: 5))
        #expect(!SelectionLanguage.trustsGuessOnUnaccentedText(confidence: 0.99, wordCount: 2))
        #expect(!SelectionLanguage.trustsGuessOnUnaccentedText(confidence: 0.67, wordCount: 5))
    }

    @Test func severalVietnameseWordsHoldAGuessBackHoweverSureItIs() {
        // The recognizer took this for Italian with 0.85; a surer guess about the same words must not get it through.
        let text = "toi dang di hoc o truong dai hoc"
        #expect(!SelectionLanguage.passesUnaccentedRules(text: text, target: .vi, confidence: 0.99))
        #expect(SelectionLanguage.passesUnaccentedRules(text: "Buongiorno a tutti, oggi andiamo al mare insieme", target: .vi, confidence: 0.99))
        #expect(!SelectionLanguage.passesUnaccentedRules(text: "Buongiorno a tutti, oggi andiamo al mare insieme", target: .vi, confidence: 0.89))
        // Not for anyone else, and not for text with accents.
        #expect(SelectionLanguage.passesUnaccentedRules(text: text, target: .en, confidence: 0.7))
        #expect(SelectionLanguage.passesUnaccentedRules(text: "Tôi đang đi học ở trường đại học", target: .vi, confidence: 0.7))
    }

    @Test func italianWithoutAccentsStillGetsAPreview() {
        let text = "Buongiorno a tutti, oggi andiamo al mare insieme"
        #expect(SelectionLanguage.source(of: text, target: .vi, candidates: candidates) == Locale.Language(identifier: "it"))
    }

    @Test func theUnaccentedRulesApplyToVietnameseUsersAndTextWithNoAccents() {
        #expect(SelectionLanguage.appliesUnaccentedRules(target: .vi, text: "cam on ban"))
        #expect(SelectionLanguage.appliesUnaccentedRules(target: Locale.Language(identifier: "vi-VN"), text: "cam on ban"))
        // For anyone else the same words are plainly foreign, and the Vietnamese word list has no say.
        #expect(!SelectionLanguage.appliesUnaccentedRules(target: .en, text: "cam on ban"))
        // Accents prove it is not an English or Italian guess of unaccented text.
        #expect(!SelectionLanguage.appliesUnaccentedRules(target: .vi, text: "cảm ơn bạn"))
    }

    @Test func vietnameseWithAccentsIsTheTargetLanguageAndShowsNothing() {
        #expect(SelectionLanguage.source(of: "Tôi đang đi học ở trường đại học", target: .vi, candidates: candidates) == nil)
    }
}
