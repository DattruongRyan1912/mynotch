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
        ("3pm PST", "time"), ("15:00 UTC+9", "time"), ("9h sáng giờ Tokyo", "time"), ("9h30 ICT", "time"), ("5 giờ chiều giờ Hà Nội", "time"),
        ("2+2*3", "math"), ("(1+2)*3", "math"), ("3+4?", "math"), ("What is 3+4?", ""), ("100 + 10%", "math"), ("2 ^ 10", "math"),
        ("1,5 × 2,5", "math"), ("1 000 000 ÷ 4", "math"), ("10 / 4", "math"), ("=3-4", "math"), ("3 - 4", "math"),
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
        // "ký" is also "to sign": only the price counts here.
        #expect(sources("Giá 100.000đ một ký, mua 2 ký") == ["100.000đ"])
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

    @Test func spacedSignsAreCalculations() {
        #expect(kinds("2024 - 10 - 15") == (["math"], true))
        #expect(kinds("12 / 4 / 3") == (["math"], true))
        #expect(kinds("3 − 4") == (["math"], true))
    }

    /// A calculation is offered for something that is clearly one: a `+ * × ÷ ^`, a leading "=", or a "-" or "/" with a
    /// space on each side. A bare "3-4" or "1/2" is a range, a score, a fraction, a date, an ID.
    @Test(arguments: ["3-4", "12/10", "1/2", "3/4", "10-3", "(3-4)", "3 -4", "3- 4", "5-3", "15 % 4", "7%2", "2024-10-15", "15/10/2024", "1-800", "3−4", "(1/2)", "10 % 3"])
    func aBareSignIsNotACalculation(text: String) {
        #expect(kinds(text).kinds.isEmpty, "\(text) -> \(kinds(text))")
    }

    @Test(arguments: [
        ("=3-4", "-1"), ("= 3 - 4", "-1"), ("3 - 4", "-1"), ("12 / 10", "1.2"), ("2*3", "6"), ("2×3", "6"), ("6÷3", "2"), ("2^3", "8"), ("3+4", "7"),
        ("2+2=", "4"), ("3-4=", "-1"), ("(3-4)*2", "-2"), ("10 % 3 * 2", "2"), ("=1/2", "0.5"), ("1 / 2", "0.5"), ("=10-3", "7"), ("12 / 10 =", "1.2"),
        ("3\u{00A0}-\u{00A0}4", "-1"), ("3\t-\t4", "-1"),
    ])
    func anExplicitExpressionIsCalculated(text: String, expected: String) throws {
        let recognition = QuantityRecognizer.recognize(text, currency: true)
        let item = try #require(recognition.items.first, "\(text)")
        #expect(recognition.isPure)
        #expect(item.quantity == .math(MathResult(value: Decimal(string: expected, locale: Locale(identifier: "en_US_POSIX"))!, usesOperator: true)), "\(text)")
    }

    @Test(arguments: ["=", "= 5", "=(5)", "=SUM(1,2)", "=a+b", "= -5", "="])
    func anEqualsSignAloneIsNotACalculation(text: String) {
        #expect(kinds(text).kinds.isEmpty, "\(text)")
    }

    /// Times are offered only with a zone attached: a capital abbreviation or offset, "giờ <nơi>" or "<place> time".
    @Test(arguments: [
        "10:30", "5h", "3pm", "3 PM", "9h30", "5 giờ chiều", "9:00 am", "hẹn 9h Nga nhé", "Chiều 5h anh qua đón em nhé", "lúc 8h y tá đến",
        "Mình gặp lúc 3pm ý bạn sao", "at 5pm west of the river", "meet at 5pm in Tokyo", "3pm Tokyo", "hẹn 9h Hà Nội nhé", "gặp 5h chiều ở Seoul",
        "see you at 3pm pst", "Họp 9h sáng", "call at 10:30 tomorrow", "5h chạy bộ",
    ])
    func aTimeWithoutAnExplicitZoneIsLeftToTheTranslation(text: String) {
        #expect(kinds(text).kinds.isEmpty, "\(text) -> \(kinds(text))")
    }

    @Test func aTimeWithAnExplicitZoneIsFoundInProse() {
        #expect(sources("Meet at 3pm PST tomorrow") == ["3pm PST"])
        #expect(sources("Họp lúc 9h sáng giờ Tokyo nhé") == ["9h sáng giờ Tokyo"])
        #expect(sources("hẹn 9h giờ Nga nhé") == ["9h giờ Nga"])
        #expect(sources("Chiều 5h theo giờ Hà Nội anh qua") == ["5h theo giờ Hà Nội"])
        #expect(sources("The call is at 5pm Russia time sharp") == ["5pm Russia time"])
        #expect(sources("Stand-up 9:30 UTC+7 daily") == ["9:30 UTC+7"])
        #expect(sources("Release at 18:00 GMT-5, see notes") == ["18:00 GMT-5"])
        #expect(kinds("hẹn 9h giờ Nga nhé") == (["time"], false))
    }

    /// "1 500" is fifteen hundred. A leading group is never dropped so that a quantity reads as 500.
    @Test func spaceGroupedThousandsAreOneNumber() throws {
        for separator in [" ", "\u{00A0}", "\u{202F}", "\u{2009}"] {
            let text = "1\(separator)500 kg"
            let item = try #require(QuantityRecognizer.recognize(text, currency: true).items.first, "\(text)")
            guard case .unit(let quantity) = item.quantity else {
                Issue.record("\(text) is not a unit")
                continue
            }
            #expect(quantity.value == 1500, "\(text)")
            let sentence = try #require(QuantityRecognizer.recognize("cân nặng \(text) nhé", currency: true).items.first)
            guard case .unit(let inSentence) = sentence.quantity else {
                Issue.record("not a unit in the sentence")
                continue
            }
            #expect(inSentence.value == 1500)
            #expect(sentence.source == text)
        }
        #expect(kinds("1 000 000 ÷ 4") == (["math"], true))
        #expect(kinds("100 000 đ") == (["money"], true))
        #expect(kinds("12 345 678 kg") == (["unit"], true))
        #expect(kinds("1 500,5 kg") == (["unit"], true))
    }

    /// If the digits cannot be read as one number, nothing is converted: never the tail of a number alone.
    @Test(arguments: [
        "1 5000 kg", "1 50 kg", "12 5 kg", "1  500 kg", "01 500 kg", "1 500.000 kg", "1 500,500 kg", "2024 500 kg", "cân nặng 1 5000 kg nhé",
        "tôi có 12 5 kg", "1,000 500 kg", "1.000 500 kg", "1\u{00A0}\u{00A0}500 kg",
    ])
    func neverConvertsThePartOfANumberThatItCouldNotRead(text: String) {
        #expect(kinds(text).kinds.isEmpty, "\(text) -> \(sources(text))")
    }

    /// Both ends of a range, or nothing: never only the upper one.
    @Test func aRangeIsConvertedAtBothEnds() throws {
        for text in ["5-10 kg", "5 - 10 kg", "5–10 kg", "5 to 10 kg", "5 đến 10 kg", "từ 5 đến 10 kg", "weight 5-10 kg only"] {
            let recognition = QuantityRecognizer.recognize(text, currency: true)
            let item = try #require(recognition.items.first, "\(text)")
            guard case .unit(let quantity) = item.quantity else {
                Issue.record("\(text) is not a unit")
                continue
            }
            #expect(quantity.value == 5 && quantity.upper == 10, "\(text)")
            #expect(recognition.items.count == 1, "\(text)")
        }
        #expect(kinds("5-10 kg") == (["unit"], true))
        #expect(kinds("từ -5 đến 10 °C") == (["unit"], false))
        let negative = try #require(QuantityRecognizer.recognize("từ -5 đến 10 °C", currency: true).items.first)
        #expect(negative.source == "-5 đến 10 °C")
    }

    @Test(arguments: ["5-10 apples", "5-10", "5 - 10 USD", "5-10 $", "item 5 - 10 foo", "10-20 xx km", "5-10-15 kg", "5 - 10 EUR", "5-10 triệu đồng"])
    func aRangeItCannotReadGivesNothingNotItsUpperEnd(text: String) {
        #expect(kinds(text).kinds.isEmpty, "\(text) -> \(sources(text))")
    }

    @Test func twoUnitsAroundADashAreNotARange() {
        #expect(kinds("5 kg - 10 lb") == (["unit", "unit"], true))
        #expect(sources("5 kg - 10 lb") == ["5 kg", "10 lb"])
    }

    @Test(arguments: ["5k", "50k", "5 k", "10k", "5K", "300K", "ăn 50k", "chạy 5k hôm nay", "5k run"])
    func aLowerCaseKIsThousandsNeverKelvin(text: String) {
        #expect(kinds(text).kinds.isEmpty, "\(text) -> \(kinds(text))")
    }

    @Test func kelvinNeedsACapitalKWithASpaceOrADegree() {
        #expect(kinds("300 K") == (["unit"], true))
        #expect(kinds("300°K") == (["unit"], true))
        #expect(kinds("300 kelvin") == (["unit"], true))
        // In a sentence a lone K is not safe, but a degree and the word are.
        #expect(kinds("It was 300 K outside").kinds.isEmpty)
        #expect(sources("It was 300 kelvin outside") == ["300 kelvin"])
    }

    @Test(arguments: [".5 kg", "about .5 kg", ",5 kg", "x.5 kg", "..5 kg"])
    func aLeadingPointIsNotDropped(text: String) {
        #expect(kinds(text).kinds.isEmpty, "\(text) -> \(sources(text))")
    }

    @Test(arguments: ["Use 12 pt font", "5 ký tên vào đây", "5 kí hiệu", "2 gigs tonight"])
    func wordsThatAreAlsoUnitsAreOnlyUnitsOnTheirOwn(text: String) {
        #expect(kinds(text).kinds.isEmpty, "\(text) -> \(sources(text))")
    }

    @Test func thoseWordsAreUnitsOnTheirOwn() {
        #expect(kinds("12 pt") == (["unit"], true))
        #expect(kinds("5 ký") == (["unit"], true))
        #expect(kinds("2 gigs") == (["unit"], true))
        #expect(kinds("33 cl") == (["unit"], true))
        #expect(sources("a 33 cl bottle") == ["33 cl"])
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

    /// Only short selections are looked at: a longer one is prose, and is just translated.
    @Test func aSelectionOfMoreThan200CharactersIsNotLookedAt() {
        let padding = String(repeating: "word ", count: 40)
        #expect(padding.count == 200)
        #expect(QuantityRecognizer.recognize(padding + "5 kg", currency: true).items.isEmpty)
        #expect(QuantityRecognizer.recognize("5 kg " + padding, currency: true).items.isEmpty)
        let fits = String(repeating: "word ", count: 38) + "5 kg"
        #expect(fits.count <= QuantityRecognizer.maxSelectionLength)
        #expect(QuantityRecognizer.recognize(fits, currency: true).items.map(\.source) == ["5 kg"])
        let exactly = String(repeating: "x", count: QuantityRecognizer.maxSelectionLength - 5) + " 5 kg"
        #expect(exactly.count == QuantityRecognizer.maxSelectionLength)
        #expect(QuantityRecognizer.recognize(exactly, currency: true).items.map(\.source) == ["5 kg"])
        #expect(QuantityRecognizer.recognize(exactly + "x", currency: true).items.isEmpty)
        // An expression too long is not worked out either, instead of being refused by the parser.
        let long = String(repeating: "1+", count: 100) + "1"
        #expect(QuantityRecognizer.recognize(long, currency: true).items.isEmpty)
    }

    @Test func aCancelledScanStopsWithNothing() async {
        let text = String(repeating: "5 a ", count: 40)
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return QuantityRecognizer.recognize("5 kg and " + text, currency: true)
        }
        task.cancel()
        #expect(await task.value.items.isEmpty)
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
