import Foundation
import Testing
@testable import TranslationModule

/// Dictionary Services answers with one flat paragraph: `headword | pronunciation | part of speech 1 sense: example
/// 2 sense ... ORIGIN ...`. These are shaped like the New Oxford American Dictionary's, which is what a Mac has.
nonisolated enum DictionarySamples {
    static let hello = """
    hello | həˈlō, heˈlō | (also hallo, hullo) exclamation 1 used as a greeting or to begin a phone conversation: \
    hello there, Katie! 2 used to attract someone's attention: hello, is anyone in? 3 used to express surprise: \
    hello, what's this? noun (pl. hellos) an utterance of "hello"; a greeting: she was getting on my nerves. \
    verb ( hellos, helloing, helloed) [ no object ] say or shout "hello": I pressed the phone button and helloed. \
    ORIGIN alteration of earlier hollo.
    """

    static let run = """
    run | rən | verb (runs, running, ran | ran | ; past participle run) 1 [ no object, with adverbial of direction ] \
    move at a speed faster than a walk, never having both or all the feet on the ground at the same time: he ran \
    across the road. • [ with object ] cover (a specified distance) at such a speed: she ran the mile. 2 [ with \
    object ] pursue (a thing) so as to catch it. 3 (of a machine) operate. 4 flow or spread. 5 manage. noun an act \
    of running. PHRASES on the run. ORIGIN Old English rinnan.
    """

    static let goodMorning = "good morning | ˌɡʊd ˈmôrniNG | exclamation used to express friendly greetings when meeting in the morning."

    /// Pronunciation glued to its bars and the paragraphs on separate lines.
    static let onLines = "hello |həˈləʊ|\nexclamation\n1 used as a greeting: hello there!\n2 used to attract attention\nnoun a greeting\nORIGIN x"

    static let lead = """
    lead | lēd | verb (past and past participle led | led |) 1 cause (a person or animal) to go with one. 2 be in \
    charge of. lead | led | noun a soft, heavy, bluish-gray metal.
    """

    static let walk = """
    walk | wôk | verb 1 move at a regular pace by lifting and setting down each foot in turn. 2 accompany on foot. \
    noun a journey on foot.
    """

    static let singleSenseWithInflection = "hello | həˈlō | noun (pl. hellos) a greeting: she gave a hello."
}

@Suite struct DictionaryParserTests {
    func entry(_ definition: String, for term: String) throws -> DictionaryEntry {
        try #require(DictionaryParser.entry(from: definition, for: term))
    }

    @Test func readsTheHeadwordThePartOfSpeechAndTheFirstThreeSenses() throws {
        let entry = try entry(DictionarySamples.hello, for: "hello")
        #expect(entry.headword == "hello")
        #expect(entry.partOfSpeech == "exclamation")
        #expect(entry.senses == [
            "Used as a greeting or to begin a phone conversation",
            "Used to attract someone's attention",
            "Used to express surprise",
        ])
        #expect(entry.term == "hello")
    }

    @Test func leavesOutExamplesPronunciationOriginAndTheOtherPartsOfSpeech() throws {
        let text = try entry(DictionarySamples.hello, for: "hello").senses.joined(separator: " ")
        for leftOut in ["həˈlō", "ORIGIN", "hollo", "Katie", "utterance", "helloed", "(also", "|"] {
            #expect(!text.contains(leftOut), "\(leftOut)")
        }
    }

    @Test func keepsOnlyThreeSensesAndTrimsTheLongOnes() throws {
        let entry = try entry(DictionarySamples.run, for: "run")
        #expect(entry.headword == "run")
        #expect(entry.partOfSpeech == "verb")
        #expect(entry.senses.count == 3)
        #expect(entry.senses[0].hasPrefix("Move at a speed faster than a walk"))
        #expect(entry.senses[0].hasSuffix("…"))
        #expect(entry.senses[0].count <= DictionaryParser.maxSenseLength + 1)
        #expect(entry.senses[1] == "Pursue (a thing) so as to catch it")
        #expect(entry.senses[2] == "(of a machine) operate")
        // The grammar notes in square brackets and the sub-senses after a bullet are not what a glance needs.
        #expect(!entry.senses.joined().contains("["))
        #expect(!entry.senses.joined().contains("•"))
    }

    @Test func aPhraseHasOneSenseAndNoNumber() throws {
        let entry = try entry(DictionarySamples.goodMorning, for: "good morning")
        #expect(entry.headword == "good morning")
        #expect(entry.partOfSpeech == "exclamation")
        #expect(entry.senses == ["Used to express friendly greetings when meeting in the morning"])
    }

    @Test func aSingleSenseDropsItsInflectionNote() throws {
        let entry = try entry(DictionarySamples.singleSenseWithInflection, for: "hello")
        #expect(entry.partOfSpeech == "noun")
        #expect(entry.senses == ["A greeting"])
    }

    @Test func linesAndGluedBarsReadTheSameAsOneParagraph() throws {
        let entry = try entry(DictionarySamples.onLines, for: "hello")
        #expect(entry.headword == "hello")
        #expect(entry.partOfSpeech == "exclamation")
        #expect(entry.senses == ["Used as a greeting", "Used to attract attention"])
    }

    @Test func stopsAtTheNextEntryOfTheSameSpelling() throws {
        let entry = try entry(DictionarySamples.lead, for: "lead")
        #expect(entry.senses == ["Cause (a person or animal) to go with one", "Be in charge of"])
        #expect(!entry.senses.joined().contains("heavy"))
    }

    @Test func stopsAtTheNextPartOfSpeech() throws {
        let entry = try entry(DictionarySamples.walk, for: "walk")
        #expect(entry.partOfSpeech == "verb")
        #expect(entry.senses == [
            "Move at a regular pace by lifting and setting down each foot in turn",
            "Accompany on foot",
        ])
    }

    @Test func aNumberInsideASenseIsNotTakenForTheNextOne() throws {
        let entry = try entry("era | ˈirə | noun 1 a period starting in 1990 and lasting 20 years. 2 a long time.", for: "era")
        #expect(entry.senses == ["A period starting in 1990 and lasting 20 years", "A long time"])
    }

    @Test func anAnswerInAnotherShapeIsShownUnderTheLookedUpWord() throws {
        let entry = try entry("Lời chào hỏi thông thường khi gặp nhau.", for: "xin chào")
        #expect(entry.headword == "xin chào")
        #expect(entry.partOfSpeech == nil)
        #expect(entry.senses == ["Lời chào hỏi thông thường khi gặp nhau"])
    }

    @Test func aLongAnswerInAnotherShapeIsTrimmed() throws {
        let entry = try entry(String(repeating: "chữ ", count: 200), for: "chữ")
        #expect(entry.senses.count == 1)
        #expect(entry.senses[0].count <= DictionaryParser.maxSenseLength + 1)
        #expect(entry.senses[0].hasSuffix("…"))
    }

    @Test(arguments: ["", "   ", "\n", "hello |", "hello | həˈlō |"])
    func nothingToShowIsNoEntry(_ definition: String) {
        #expect(DictionaryParser.entry(from: definition, for: "hello") == nil)
    }

    @Test func trimmingCutsAtAWordAndNeverExceedsTheLimit() {
        #expect(DictionaryParser.trimmed("short", to: 20) == "short")
        #expect(DictionaryParser.trimmed("exactly twenty chars", to: 20) == "exactly twenty chars")
        #expect(DictionaryParser.trimmed("one two three four five", to: 14) == "one two three…")
        #expect(DictionaryParser.trimmed("unbrokenwordthatistoolong", to: 10) == "unbrokenwo…")
    }
}

@Suite struct DictionaryQueryTests {
    @Test(arguments: [
        ("hello", "hello"),
        ("  Hello,  ", "Hello"),
        ("good morning", "good morning"),
        ("one two three", "one two three"),
        ("\u{201C}quoted\u{201D}", "quoted"),
        ("don't", "don't"),
        ("state-of-the-art", "state-of-the-art"),
        ("(maybe)", "maybe"),
        ("Hello.", "Hello"),
        ("good   morning", "good morning"),
    ])
    func aWordOrAShortPhraseIsLookedUp(_ text: String, _ term: String) {
        #expect(DictionaryQuery.term(in: text) == term)
    }

    @Test(arguments: [
        "", "   ", "one two three four", "line one\nline two", "12345", "3 + 4", String(repeating: "a", count: 60), "...",
    ])
    func everythingElseIsNot(_ text: String) {
        #expect(DictionaryQuery.term(in: text) == nil)
    }

    @Test func theDictionaryOpensAtTheWord() {
        func url(_ term: String) -> URL? {
            DictionaryEntry(term: term, headword: term, partOfSpeech: nil, senses: ["x"]).dictionaryURL
        }
        #expect(url("hello") == URL(string: "dict://hello"))
        #expect(url("good morning") == URL(string: "dict://good%20morning"))
        #expect(url("café") == URL(string: "dict://caf%C3%A9"))
        #expect(url("Tom & Jerry")?.absoluteString == "dict://Tom%20%26%20Jerry")
    }
}

@Suite struct DictionaryFinderTests {
    let source = FakeDictionary()

    func finder() -> DictionaryFinder { DictionaryFinder(source) }

    @Test func looksTheWordUpAndParsesTheAnswer() async {
        source.definitions["hello"] = DictionarySamples.hello
        let entry = await finder().entry(for: "hello")
        #expect(entry?.headword == "hello")
        #expect(source.requests == ["hello"])
    }

    @Test func asksWithTheTermNotTheSelection() async {
        source.definitions["Hello"] = DictionarySamples.hello
        _ = await finder().entry(for: "  Hello,  ")
        #expect(source.requests == ["Hello"])
    }

    @Test func aPhraseTheDictionaryKnowsIsShown() async {
        source.definitions["good morning"] = DictionarySamples.goodMorning
        let entry = await finder().entry(for: "good morning")
        #expect(entry?.headword == "good morning")
    }

    /// Dictionary Services looks a phrase up from its first word when the phrase itself is no entry; a card about
    /// "good" over a translation of "good morning my friend" would mislead.
    @Test func aCardForOnlyTheFirstWordOfAPhraseIsNotShown() async {
        source.definitions["good morning friend"] = "good | ɡʊd | adjective 1 to be desired or approved of."
        #expect(await finder().entry(for: "good morning friend") == nil)
    }

    @Test func aSingleWordMayComeBackAsItsBaseForm() async {
        source.definitions["ran"] = DictionarySamples.run
        let entry = await finder().entry(for: "ran")
        #expect(entry?.headword == "run")
        #expect(entry?.term == "ran")
    }

    @Test func textThatIsNotAWordOrShortPhraseIsNeverAsked() async {
        source.definitions["one two three four"] = DictionarySamples.hello
        for text in ["", "one two three four", "line\nbreak", "12345"] {
            #expect(await finder().entry(for: text) == nil)
        }
        #expect(source.requests.isEmpty)
    }

    @Test func noDefinitionIsNoCard() async {
        #expect(await finder().entry(for: "zzyzx") == nil)
        #expect(source.requests == ["zzyzx"])
    }
}
