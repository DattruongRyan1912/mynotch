import Foundation
import Testing
@testable import TranslationModule

@Suite struct UnitQuantityTests {
    typealias U = UnitCatalog

    func parsed(_ text: String) -> (Double, String)? {
        UnitQuantityParser.parse(text).map { ($0.value, $0.unit.id) }
    }

    func matches(_ text: String, _ value: Double, _ id: String, accuracy: Double = 1e-9) -> Bool {
        guard let result = parsed(text) else { return false }
        return abs(result.0 - value) <= accuracy && result.1 == id
    }

    @Test(arguments: [
        "5 ft 11 in", "5ft 11in", "5ft11in", "5'11\"", "5′11″", "5'11", "5 ft 11", "5 feet 11 inches", "5 foot 11", "5 Ft 11 In",
        "  5 ft  11 in  ", "5 ft. 11 in.", "5 feet, 11 inches".replacing(",", with: ""),
    ])
    func readsFeetAndInches(text: String) {
        #expect(matches(text, 5 + 11.0 / 12, "length.ft"), "\(text) -> \(String(describing: parsed(text)))")
    }

    @Test(arguments: [
        ("72 °F", 72.0, "temperature.f"), ("72°F", 72.0, "temperature.f"), ("72 F", 72.0, "temperature.f"), ("72F", 72.0, "temperature.f"),
        ("72 độ F", 72.0, "temperature.f"), ("72 degrees Fahrenheit", 72.0, "temperature.f"), ("72 ℉", 72.0, "temperature.f"),
        ("72ºF", 72.0, "temperature.f"), ("72 ° F", 72.0, "temperature.f"), ("72 độ Ép", 72.0, "temperature.f"),
        ("-5 °C", -5.0, "temperature.c"), ("−5°C", -5.0, "temperature.c"), ("37,5 °C", 37.5, "temperature.c"),
        ("37.5 độ C", 37.5, "temperature.c"), ("+20 độ xê", 20.0, "temperature.c"), ("0 K", 0.0, "temperature.k"),
        ("300 kelvin", 300.0, "temperature.k"),
    ])
    func readsTemperatures(text: String, value: Double, id: String) {
        #expect(matches(text, value, id))
    }

    @Test(arguments: [
        ("2 lb", 2.0, "mass.lb"), ("2 lbs", 2.0, "mass.lb"), ("2 pounds", 2.0, "mass.lb"), ("8 oz", 8.0, "mass.oz"),
        ("1 kg", 1.0, "mass.kg"), ("1,5 kg", 1.5, "mass.kg"), ("500g", 500.0, "mass.g"), ("500 gam", 500.0, "mass.g"),
        ("2 ký", 2.0, "mass.kg"), ("2 kí", 2.0, "mass.kg"), ("2 ky", 2.0, "mass.kg"), ("3 ki lô gam", 3.0, "mass.kg"),
        ("3 ki-lô-gam", 3.0, "mass.kg"), ("1 tấn", 1.0, "mass.t"), ("1 tonne", 1.0, "mass.t"), ("250 mg", 250.0, "mass.mg"),
        ("1.500 g", 1500.0, "mass.g"),
    ])
    func readsMasses(text: String, value: Double, id: String) {
        #expect(matches(text, value, id))
    }

    @Test(arguments: [
        ("10 km", 10.0, "length.km"), ("1,5 km", 1.5, "length.km"), ("10 cây số", 10.0, "length.km"), ("3 mét", 3.0, "length.m"),
        ("3 met", 3.0, "length.m"), ("3 m", 3.0, "length.m"), ("180cm", 180.0, "length.cm"), ("10 miles", 10.0, "length.mi"),
        ("10 dặm", 10.0, "length.mi"), ("1 yard", 1.0, "length.yd"), ("5 mm", 5.0, "length.mm"), ("5 inch", 5.0, "length.in"),
        ("5\"", 5.0, "length.in"), ("2 inches", 2.0, "length.in"), ("6'", 6.0, "length.ft"), ("100.000 m", 100_000.0, "length.m"),
        ("1 ki lô mét", 1.0, "length.km"),
    ])
    func readsLengths(text: String, value: Double, id: String) {
        #expect(matches(text, value, id))
    }

    @Test(arguments: [
        ("250 ml", 250.0, "volume.ml"), ("2 l", 2.0, "volume.l"), ("2 L", 2.0, "volume.l"), ("2 lít", 2.0, "volume.l"),
        ("1 gallon", 1.0, "volume.gal"), ("16 fl oz", 16.0, "volume.floz"), ("16 fl. oz.", 16.0, "volume.floz"),
        ("2 cups", 2.0, "volume.cup"), ("1 qt", 1.0, "volume.qt"), ("2 tbsp", 2.0, "volume.tbsp"), ("1 ga-lông", 1.0, "volume.gal"),
    ])
    func readsVolumes(text: String, value: Double, id: String) {
        #expect(matches(text, value, id))
    }

    @Test(arguments: [
        ("100 m²", 100.0, "area.m2"), ("100 m2", 100.0, "area.m2"), ("50 sq ft", 50.0, "area.ft2"), ("50 sqft", 50.0, "area.ft2"),
        ("50 ft²", 50.0, "area.ft2"), ("1 ha", 1.0, "area.ha"), ("2 acres", 2.0, "area.ac"), ("10 mét vuông", 10.0, "area.m2"),
        ("2 hecta", 2.0, "area.ha"), ("3 km2", 3.0, "area.km2"), ("1 square mile", 1.0, "area.mi2"), ("85,5 m2", 85.5, "area.m2"),
    ])
    func readsAreas(text: String, value: Double, id: String) {
        #expect(matches(text, value, id))
    }

    @Test(arguments: [
        ("100 km/h", 100.0, "speed.kmh"), ("60 mph", 60.0, "speed.mph"), ("10 m/s", 10.0, "speed.mps"), ("30 knots", 30.0, "speed.kn"),
        ("100 kmh", 100.0, "speed.kmh"), ("100 km/giờ", 100.0, "speed.kmh"), ("55 dặm/giờ", 55.0, "speed.mph"),
    ])
    func readsSpeeds(text: String, value: Double, id: String) {
        #expect(matches(text, value, id))
    }

    @Test(arguments: [
        ("1 GB", 1.0, "data.GB"), ("500 MB", 500.0, "data.MB"), ("1,5 TB", 1.5, "data.TB"), ("1024 KB", 1024.0, "data.KB"),
        ("1 GiB", 1.0, "data.GiB"), ("100 bytes", 100.0, "data.B"), ("8 B", 8.0, "data.B"), ("5 mb", 5.0, "data.MB"),
        ("2 gigabytes", 2.0, "data.GB"), ("256 gb", 256.0, "data.GB"), ("1.024 MB", 1024.0, "data.MB"),
    ])
    func readsDataSizes(text: String, value: Double, id: String) {
        #expect(matches(text, value, id))
    }

    @Test(arguments: [("300 K", 300.0), ("300 °K", 300.0), ("300°K", 300.0), ("300º K", 300.0), ("300 kelvin", 300.0), ("300 Kelvin", 300.0), ("0 K", 0.0)])
    func kelvinNeedsACapitalKWithASpaceOrADegree(text: String, value: Double) {
        #expect(matches(text, value, "temperature.k"))
    }

    @Test(arguments: ["5k", "50k", "5 k", "300k", "300K", "5K", "10 k", "1,5k"])
    func aLowerCaseKIsThousandsNotKelvin(text: String) {
        #expect(UnitQuantityParser.parse(text) == nil, "\(text) -> \(String(describing: parsed(text)))")
    }

    @Test func readsRangesWithBothEnds() throws {
        let range = try #require(UnitQuantityParser.parse("5-10 kg"))
        #expect(range.value == 5 && range.upper == 10 && range.unit.id == "mass.kg")
        let negative = try #require(UnitQuantityParser.parse("-5 đến 10 °C"))
        #expect(negative.value == -5 && negative.upper == 10 && negative.unit.id == "temperature.c")
        let words = try #require(UnitQuantityParser.parse("1 000 to 2 000 m"))
        #expect(words.value == 1000 && words.upper == 2000)
        let single = try #require(UnitQuantityParser.parse("5 kg"))
        #expect(single.upper == nil)
        // Compound units are not ranges.
        #expect(UnitQuantityParser.parse("5 ft 11 in")?.upper == nil)
    }

    @Test(arguments: ["5-10", "5 kg - 10 lb", "5 - kg", "5-10 kg 3", "5 ft - 10 in", "5 - - 10 kg", "5-10-15 kg", "5 to to 10 kg", "5 - 10 apples", "5-", "5 kg -"])
    func refusesWhatIsNotARangeOfOneUnit(text: String) {
        #expect(UnitQuantityParser.parse(text) == nil, "\(text) -> \(String(describing: parsed(text)))")
    }

    @Test func compoundsAddUpInTheFirstUnit() throws {
        #expect(matches("1 lb 8 oz", 1.5, "mass.lb"))
        #expect(matches("1 m 80 cm", 1.8, "length.m"))
        #expect(matches("2 km 500 m", 2.5, "length.km"))
        #expect(matches("1 gal 2 qt", 1.5, "volume.gal", accuracy: 1e-5))
        #expect(matches("-5 ft 11 in", -(5 + 11.0 / 12), "length.ft"))
        #expect(matches("5 ft 0 in", 5, "length.ft"))
    }

    @Test(arguments: [
        "5", "5 apples", "km", "5 xx", "", "   ", "5 ft 3 mi", "5 ft 3 kg", "5 ft 11 in 3 ft", "1.2.3 km", "5 ft ft", "5 km, 3 mi",
        "°C 5", "5 °C 3 °C", "5 in 11 ft", "5 ft 11 12", "5 ft in", "- km", "5 km!", "1 5000 km", "1 50 km", "5 °C 3", "5 kg 3", "5 m 7",
        "15.10.2024 km", "5 ² m", "5 / 3 km", "12:30 km", "0 B x", "5 b",
    ])
    func refusesWhatIsNotOneQuantity(text: String) {
        #expect(UnitQuantityParser.parse(text) == nil, "\(text) -> \(String(describing: parsed(text)))")
    }

    @Test func knowsWhichReadingsAreSafeInRunningText() throws {
        func safe(_ text: String) -> Bool? { UnitQuantityParser.parse(text)?.isUnambiguous }
        #expect(safe("5 kg") == true)
        #expect(safe("5 ft") == true)
        #expect(safe("30°C") == true)
        #expect(safe("5 m") == false)
        #expect(safe("5 in") == false)
        #expect(safe("72 F") == false)
        #expect(safe("5\"") == false)
        #expect(safe("8 B") == false)
        #expect(safe("12 pt") == false)
        #expect(safe("5 ký") == false)
        #expect(safe("5 kí") == false)
        #expect(safe("5 gigs") == false)
        #expect(safe("5 kt") == false)
        #expect(safe("5 pint") == true)
        // Two pairs cannot be a slip: "5'11\"" is a height.
        #expect(safe("5'11\"") == true)
        #expect(safe("5 m 7 cm") == true)
    }
}

@Suite struct UnitConversionTests {
    func lines(_ text: String, _ system: UnitSystem = .metric) throws -> [String] {
        let quantity = try #require(UnitQuantityParser.parse(text), "\(text)")
        return UnitConversion.lines(for: quantity, localeSystem: system).map(\.text)
    }

    @Test func theExamplesOfTheBrief() throws {
        #expect(try lines("5 ft 11 in") == ["180 cm"])
        #expect(try lines("72 °F") == ["22,2 °C"])
        #expect(try lines("2 lb") == ["0,91 kg"])
    }

    @Test(arguments: [
        ("180 cm", ["5 ft 11 in"]), ("30 °C", ["86 °F"]), ("0 °C", ["32 °F"]), ("-40 °F", ["-40 °C"]), ("37 °C", ["98,6 °F"]),
        ("1 mile", ["1,61 km"]), ("26,2 miles", ["42 km"]), ("100 km/h", ["62 mph"]), ("60 mph", ["97 km/h"]),
        ("10 m/s", ["36 km/h", "22 mph"]), ("30 knots", ["56 km/h", "35 mph"]), ("5 km", ["3,11 mi"]),
        ("1500 m", ["1,5 km", "0,93 mi"]), ("5 cm", ["1,97 in"]), ("1 inch", ["2,54 cm"]), ("10 ft", ["3,05 m"]),
        ("50 m", ["164 ft"]), ("1 ft", ["30 cm"]), ("100 yards", ["91 m", "300 ft"]),
        ("2 l", ["0,53 gal"]), ("250 ml", ["8,45 fl oz"]), ("1 gallon", ["3,79 l"]), ("2 cups", ["473 ml", "16 fl oz"]),
        ("500 g", ["0,5 kg", "1,1 lb"]), ("400 g", ["14 oz"]), ("8 oz", ["227 g"]), ("5 lb", ["2,27 kg"]), ("1 tấn", ["2.205 lb"]),
        ("100 m²", ["1.076 ft²"]), ("50 sq ft", ["4,65 m²"]), ("1 ha", ["2,47 ac"]), ("2 acres", ["8.094 m²"]),
        ("1 GB", ["954 MiB"]), ("1 GiB", ["1,07 GB"]), ("1536 KB", ["1,54 MB", "1,46 MiB"]), ("500 GB", ["466 GiB"]),
        ("0 K", ["-273,2 °C", "-459,7 °F"]), ("5 mm", ["0,2 in"]), ("-5 ft", ["-152 cm"]), ("0 kg", []), ("0 ft", []), ("0 °C", ["32 °F"]),
    ])
    func convertsForAMetricUser(text: String, expected: [String]) throws {
        #expect(try lines(text) == expected)
    }

    @Test(arguments: [
        ("180 cm", ["5 ft 11 in"]), ("5 ft 11 in", ["180 cm"]), ("72 °F", ["22,2 °C"]), ("30 °C", ["86 °F"]), ("1500 m", ["0,93 mi", "1,5 km"]),
        ("2 lb", ["0,91 kg"]), ("1 kg", ["2,2 lb"]), ("100 km/h", ["62 mph"]), ("60 mph", ["97 km/h"]), ("5 km", ["3,11 mi"]),
    ])
    func convertsForAUsUser(text: String, expected: [String]) throws {
        #expect(try lines(text, .us) == expected)
    }

    @Test func putsTheUsersSystemFirst() throws {
        #expect(try lines("1500 m", .metric) == ["1,5 km", "0,93 mi"])
        #expect(try lines("1500 m", .us) == ["0,93 mi", "1,5 km"])
    }

    @Test func heightsAreFeetAndInchesNotDecimals() throws {
        #expect(try lines("170 cm", .us) == ["5 ft 7 in"])
        #expect(try lines("183 cm", .us) == ["6 ft"])
        #expect(try lines("150 cm", .us) == ["4 ft 11 in"])
        #expect(try lines("-170 cm", .us) == ["-5 ft 7 in"])
        // Beyond three metres, and below one foot, decimals.
        #expect(try lines("500 cm", .us) == ["16 ft", "5 m"])
        #expect(try lines("20 cm", .us) == ["7,87 in"])
    }

    @Test func neverRepeatsAResult() throws {
        for text in ["180 cm", "5 ft", "72 °F", "30 °C", "1 kg", "2 lb", "1 GB", "1 GiB", "100 km/h", "60 mph", "3 l", "3 gal"] {
            let result = try lines(text)
            #expect(Set(result).count == result.count, "\(text) -> \(result)")
        }
    }

    @Test func leavesOutTheUnitTheTextAlreadyUsed() throws {
        #expect(try lines("5 ft 11 in") == ["180 cm"])
        #expect(try lines("180 cm") == ["5 ft 11 in"])
        #expect(try lines("100 GB") == ["93 GiB"])
    }

    @Test(arguments: [
        ("37 °C", ["98,6 °F"]), ("37,5 °C", ["99,5 °F"]), ("38 °C", ["100,4 °F"]), ("38,5 °C", ["101,3 °F"]), ("21,5 °C", ["70,7 °F"]),
        ("72 °F", ["22,2 °C"]), ("98.6 °F", ["37 °C"]), ("100 °C", ["212 °F"]), ("212 °F", ["100 °C"]), ("-40 °C", ["-40 °F"]),
        ("300 K", ["26,9 °C", "80,3 °F"]), ("-10 °C", ["14 °F"]),
    ])
    func temperaturesKeepOneDecimal(text: String, expected: [String]) throws {
        #expect(try lines(text) == expected)
    }

    @Test func otherUnitsKeepTheTwoSignificantDigitRule() throws {
        #expect(try lines("6 ft") == ["183 cm"])
        #expect(try lines("26,2 miles") == ["42 km"])
        #expect(try lines("1 GB") == ["954 MiB"])
        #expect(try lines("2 lb") == ["0,91 kg"])
    }

    @Test(arguments: [
        ("5-10 kg", ["11–22 lb"]), ("5 - 10 kg", ["11–22 lb"]), ("5 kg - 10 kg", ["11–22 lb"]), ("5 to 10 kg", ["11–22 lb"]),
        ("5 đến 10 kg", ["11–22 lb"]), ("5 tới 10 kg", ["11–22 lb"]), ("5–10 kg", ["11–22 lb"]), ("5—10 kg", ["11–22 lb"]), ("5~10 kg", ["11–22 lb"]),
        ("10-20 km", ["6,21–12 mi"]), ("-5 đến 10 °C", ["23–50 °F"]), ("-30 đến -20 °C", ["-22 – -4 °F"]), ("500-2000 m", ["0,5–2 km", "0,31–1,24 mi"]),
        ("1 000-2 000 kg", ["1–2 tấn", "2.205–4.409 lb"]), ("50-100 °F", ["10–37,8 °C"]), ("0-5 kg", ["0–11 lb"]), ("10-5 kg", ["22–11 lb"]),
    ])
    func convertsBothEndsOfARange(text: String, expected: [String]) throws {
        #expect(try lines(text) == expected)
    }

    @Test func aRangeInHeightsIsFeetAndInchesAtBothEnds() throws {
        #expect(try lines("150-180 cm", .us) == ["4 ft 11 in – 5 ft 11 in"])
        #expect(try lines("150-180 cm") == ["4 ft 11 in – 5 ft 11 in"])
    }

    @Test func aRangeKeepsOneUnitForBothEnds() throws {
        // The larger end decides, so 500 m to 2 km reads 0,5 to 2 km, not 500 m to 2.
        #expect(try lines("500 m - 2000 m") == ["0,5–2 km", "0,31–1,24 mi"])
    }

    @Test func cupsAreEightFluidOunces() throws {
        #expect(try lines("1 cup", .us) == ["8 fl oz", "237 ml"])
        #expect(try lines("1 cup") == ["237 ml", "8 fl oz"])
        #expect(try lines("2 cups") == ["473 ml", "16 fl oz"])
    }

    @Test(arguments: [("33 cl", ["330 ml", "11 fl oz"]), ("2 dl", ["200 ml", "6,76 fl oz"]), ("50 cl", ["500 ml", "17 fl oz"])])
    func readsCentilitresAndDecilitres(text: String, expected: [String]) throws {
        #expect(try lines(text) == expected)
    }
}
