import Foundation
import Testing
@testable import TranslationModule

@Suite struct QuantityRecognizerTests {
    func kinds(_ text: String, currency: Bool = true) -> (kinds: [String], isPure: Bool) {
        let recognition = QuantityRecognizer.recognize(text, currency: currency)
        return (recognition.items.map { item in
            switch item.quantity {
            case .unit: "unit"
            case .time: "time"
            case .math: "math"
            case .money: "money"
            }
        }, recognition.isPure)
    }

    func sources(_ text: String, currency: Bool = true) -> [String] {
        QuantityRecognizer.recognize(text, currency: currency).items.map(\.source)
    }

    @Test(arguments: [
        ("5 ft 11 in", "unit"), ("72 °F", "unit"), ("72°F.", "unit"), ("2 lb", "unit"), ("100 km/h", "unit"), ("1,5 kg", "unit"), ("500 MB", "unit"),
        ("3pm PST", "time"), ("15:00 UTC+9", "time"), ("9h sáng giờ Tokyo", "time"), ("3pm", "time"), ("9h30", "time"),
        ("2+2*3", "math"), ("(1+2)*3", "math"), ("3+4?", "math"), ("What is 3+4?", ""), ("15 % 4", "math"), ("100 + 10%", "math"), ("2 ^ 10", "math"),
        ("1,5 × 2,5", "math"), ("1 000 000 ÷ 4", ""), ("10 / 4", "math"), ("3/4", "math"),
        ("$12", "money"), ("12 USD", "money"), ("€5", "money"), ("100.000đ", "money"), ("5 triệu đồng", "money"), ("£3.50", "money"),
    ])
    func aTextThatIsOneQuantityIsPure(text: String, kind: String) {
        let result = kinds(text)
        #expect(kind.isEmpty ? result.kinds.isEmpty : result.kinds == [kind] && result.isPure, "\(text) -> \(result)")
    }

    @Test func quantitiesInASentenceAreFoundButTheTextIsNotPure() {
        #expect(kinds("The table is 5 kg and 2 m long") == (["unit"], false))
        #expect(kinds("I paid 12 USD for 3 kg of rice") == (["money", "unit"], false))
        #expect(sources("I paid 12 USD for 3 kg of rice") == ["12 USD", "3 kg"])
        #expect(sources("a $5 coffee and a €3 tea") == ["$5", "€3"])
        #expect(sources("Meet at 3pm PST tomorrow") == ["3pm PST"])
        #expect(sources("Họp lúc 9h sáng giờ Tokyo nhé") == ["9h sáng giờ Tokyo"])
        #expect(sources("It was 30°C yesterday") == ["30°C"])
        #expect(sources("Giá 100.000đ một ký, mua 2 ký") == ["100.000đ", "2 ký"])
        #expect(sources("He is 5'11\" tall") == ["5'11\""])
        #expect(sources("He is 5 ft 11 in tall") == ["5 ft 11 in"])
        // A lone "m" could be a million, so only the kilograms count here.
        #expect(sources("Chiều cao 1,75 m, nặng 70 kg") == ["70 kg"])
        #expect(sources("Chiều cao 175 cm, nặng 70 kg") == ["175 cm", "70 kg"])
    }

    @Test func aTextMadeOfNothingButQuantitiesIsPure() {
        #expect(kinds("5 km, 3 mi") == (["unit", "unit"], true))
        #expect(kinds("5 km - 3 mi") == (["unit", "unit"], true))
        #expect(kinds("72 °F / 30 °C") == (["unit", "unit"], true))
        #expect(kinds("$5 or 12 USD") == (["money", "money"], false))
        #expect(kinds("$5, €3") == (["money", "money"], true))
    }

    @Test func ambiguousReadingsAreLeftAloneInSentences() {
        // Single letters, quotes and "in" can be anything in prose.
        #expect(kinds("I need 5 m of cable").kinds.isEmpty)
        #expect(kinds("He said \"3\" twice").kinds.isEmpty)
        #expect(kinds("Come back in 2 in a row").kinds.isEmpty)
        #expect(kinds("Use vitamin B12 daily").kinds.isEmpty)
        #expect(kinds("Take 2 c of sugar").kinds.isEmpty)
        #expect(kinds("Call me at 3pm").kinds.isEmpty)
        #expect(kinds("I woke up at 7 am").kinds.isEmpty)
        #expect(kinds("7h sáng mai dậy").kinds.isEmpty)
        // But on their own they are quantities.
        #expect(kinds("5 m") == (["unit"], true))
        #expect(kinds("5 in") == (["unit"], true))
        #expect(kinds("72 F") == (["unit"], true))
    }

    @Test func numbersInsideWordsAndOtherNumbersAreNotQuantities() {
        #expect(kinds("The H2O formula").kinds.isEmpty)
        #expect(kinds("Version v1.5 kg").kinds.isEmpty)
        #expect(kinds("Call 090 123 4567 now").kinds.isEmpty)
        #expect(kinds("Order #12345 shipped").kinds.isEmpty)
        #expect(kinds("In 2024 we grew 5 percent").kinds.isEmpty)
        #expect(kinds("ID: 123abc km").kinds.isEmpty)
        #expect(kinds("x1.500.000 kg").kinds.isEmpty)
        // "$5m" is five million dollars, not five metres.
        #expect(kinds("raised $5m last year").kinds.isEmpty)
    }

    @Test(arguments: ["2024-10-15", "15/10/2024", "090-123-4567", "1-2-3", "12/25/2024", "2025-01-01"])
    func datesAndCodesAreNotCalculations(text: String) {
        #expect(kinds(text).kinds.isEmpty, "\(text)")
    }

    @Test func spacedSignsAreStillCalculations() {
        #expect(kinds("2024 - 10 - 15") == (["math"], true))
        #expect(kinds("12 / 4 / 3") == (["math"], true))
        #expect(kinds("10-3") == (["math"], true))
    }

    @Test func moneyIsOnlyReadWhenCurrencyIsOn() {
        #expect(kinds("$12", currency: false).kinds.isEmpty)
        #expect(kinds("12 USD", currency: false).kinds.isEmpty)
        #expect(kinds("100.000đ", currency: false).kinds.isEmpty)
        #expect(kinds("I paid 12 USD for 3 kg", currency: false) == (["unit"], false))
        #expect(kinds("5 kg", currency: false) == (["unit"], true))
    }

    @Test func plainTextHasNoQuantities() {
        for text in ["", "   ", "Hello, how are you today?", "Xin chào các bạn", "12", "1,5", "abc 123", "100%", "(5)", "-5", "1.000",
                     "Chapter 12", "page 3 of 10", "5 apples", "3 people", "2 + apples"] {
            #expect(kinds(text).kinds.isEmpty, "\(text) -> \(kinds(text))")
        }
    }

    @Test func listsAtMostThreeQuantitiesAndIsNotPureBeyondThat() {
        let result = QuantityRecognizer.recognize("1 kg 2 kg 3 kg 4 kg", currency: true)
        #expect(result.items.count == 3 || result.items.count == 1)
        let many = QuantityRecognizer.recognize("1 kg, 2 kg, 3 kg, 4 kg, 5 kg", currency: true)
        #expect(many.items.count == QuantityRecognizer.maxItems)
        #expect(!many.isPure)
        let same = QuantityRecognizer.recognize("5 kg, 5 kg, 5 kg", currency: true)
        #expect(same.items.count == 1)
    }

    @Test func veryLongTextIsNotScanned() {
        let long = String(repeating: "word 5 kg ", count: 400)
        #expect(QuantityRecognizer.recognize(long, currency: true).items.isEmpty)
        let shorter = String(repeating: "word ", count: 100) + "5 kg"
        #expect(QuantityRecognizer.recognize(shorter, currency: true).items.map(\.source) == ["5 kg"])
    }

    @Test func aListOfNumbersHasNoQuantities() {
        #expect(kinds("1 2 3 4 5 6 7 8 9").kinds.isEmpty)
        #expect(kinds("12, 34, 56 and 78").kinds.isEmpty)
        #expect(kinds("Total 1.000 2.000 3.000").kinds.isEmpty)
    }

    @Test func aQuantityInRunningTextIsOnOneLine() {
        #expect(sources("Height 5 ft\n11 in") == ["5 ft"])
        #expect(sources("a 5 kg bag\nand a 3 lb bag") == ["5 kg", "3 lb"])
    }

    @Test func givesUpOnATextThatWouldKeepItBusy() {
        // Hundreds of numbers each followed by a letter: every one is tried at many lengths.
        let filler = String(repeating: "5 a ", count: 450)
        let early = QuantityRecognizer.recognize("7 kg " + filler, currency: true)
        #expect(early.items.map(\.source) == ["7 kg"])
        #expect(!early.isPure)
        let late = QuantityRecognizer.recognize(filler + "7 kg", currency: true)
        #expect(late.items.isEmpty)
        #expect(!late.isPure)
    }

    @Test func readsThePieceTheQuantityMeans() throws {
        let unit = try #require(QuantityRecognizer.recognize("5 ft 11 in", currency: true).items.first)
        #expect(unit.source == "5 ft 11 in")
        guard case .unit(let quantity) = unit.quantity else {
            Issue.record("not a unit")
            return
        }
        #expect(quantity.unit.id == "length.ft")
        // The full stop or question mark of the sentence is not part of it.
        let math = try #require(QuantityRecognizer.recognize("3+4?", currency: true).items.first)
        #expect(math.source == "3+4")
        #expect(math.quantity == .math(MathResult(value: 7, usesOperator: true)))
    }
}
