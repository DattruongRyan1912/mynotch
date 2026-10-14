import Foundation

enum UnitCategory: CaseIterable {
    case length, mass, temperature, volume, area, speed, data
}

/// The two ways a quantity can be written: for data, decimal (KB, MB) and binary (KiB, MiB).
enum UnitSystem {
    case metric, us

    var other: UnitSystem { self == .metric ? .us : .metric }
}

/// A unit `Measurement` can convert, with the symbol results show.
struct MeasureUnit: Equatable {
    let id: String
    let symbol: String
    let category: UnitCategory
    let dimension: Dimension

    static func == (lhs: MeasureUnit, rhs: MeasureUnit) -> Bool { lhs.id == rhs.id }

    /// The amount of `value` of this unit in the category's base unit (m, kg, K, L, m², m/s, bytes).
    func base(_ value: Double) -> Double {
        Measurement(value: value, unit: dimension).converted(to: type(of: dimension).baseUnit()).value
    }

    func value(fromBase base: Double) -> Double {
        Measurement(value: base, unit: type(of: dimension).baseUnit()).converted(to: dimension).value
    }
}

/// The units the quick convert knows and the words people write them with, English and Vietnamese.
enum UnitCatalog {
    struct Match {
        var unit: MeasureUnit
        /// Safe to look for inside running text: not a single letter ("5 m", "5 c") and not "in" ("2 in a row").
        var isUnambiguous: Bool
    }

    static let millimeter = unit("length.mm", "mm", .length, UnitLength.millimeters)
    static let centimeter = unit("length.cm", "cm", .length, UnitLength.centimeters)
    static let meter = unit("length.m", "m", .length, UnitLength.meters)
    static let kilometer = unit("length.km", "km", .length, UnitLength.kilometers)
    static let inch = unit("length.in", "in", .length, UnitLength.inches)
    static let foot = unit("length.ft", "ft", .length, UnitLength.feet)
    static let yard = unit("length.yd", "yd", .length, UnitLength.yards)
    static let mile = unit("length.mi", "mi", .length, UnitLength.miles)

    static let milligram = unit("mass.mg", "mg", .mass, UnitMass.milligrams)
    static let gram = unit("mass.g", "g", .mass, UnitMass.grams)
    static let kilogram = unit("mass.kg", "kg", .mass, UnitMass.kilograms)
    static let tonne = unit("mass.t", "tấn", .mass, UnitMass.metricTons)
    static let ounce = unit("mass.oz", "oz", .mass, UnitMass.ounces)
    static let pound = unit("mass.lb", "lb", .mass, UnitMass.pounds)

    static let celsius = unit("temperature.c", "°C", .temperature, UnitTemperature.celsius)
    static let fahrenheit = unit("temperature.f", "°F", .temperature, UnitTemperature.fahrenheit)
    static let kelvin = unit("temperature.k", "K", .temperature, UnitTemperature.kelvin)

    static let milliliter = unit("volume.ml", "ml", .volume, UnitVolume.milliliters)
    static let liter = unit("volume.l", "l", .volume, UnitVolume.liters)
    static let fluidOunce = unit("volume.floz", "fl oz", .volume, UnitVolume.fluidOunces)
    static let cup = unit("volume.cup", "cup", .volume, UnitVolume.cups)
    static let tablespoon = unit("volume.tbsp", "tbsp", .volume, UnitVolume.tablespoons)
    static let teaspoon = unit("volume.tsp", "tsp", .volume, UnitVolume.teaspoons)
    static let pint = unit("volume.pt", "pt", .volume, UnitVolume.pints)
    static let quart = unit("volume.qt", "qt", .volume, UnitVolume.quarts)
    static let gallon = unit("volume.gal", "gal", .volume, UnitVolume.gallons)

    static let squareCentimeter = unit("area.cm2", "cm²", .area, UnitArea.squareCentimeters)
    static let squareMeter = unit("area.m2", "m²", .area, UnitArea.squareMeters)
    static let squareKilometer = unit("area.km2", "km²", .area, UnitArea.squareKilometers)
    static let hectare = unit("area.ha", "ha", .area, UnitArea.hectares)
    static let squareInch = unit("area.in2", "in²", .area, UnitArea.squareInches)
    static let squareFoot = unit("area.ft2", "ft²", .area, UnitArea.squareFeet)
    static let squareYard = unit("area.yd2", "yd²", .area, UnitArea.squareYards)
    static let squareMile = unit("area.mi2", "mi²", .area, UnitArea.squareMiles)
    static let acre = unit("area.ac", "ac", .area, UnitArea.acres)

    static let kilometersPerHour = unit("speed.kmh", "km/h", .speed, UnitSpeed.kilometersPerHour)
    static let milesPerHour = unit("speed.mph", "mph", .speed, UnitSpeed.milesPerHour)
    static let metersPerSecond = unit("speed.mps", "m/s", .speed, UnitSpeed.metersPerSecond)
    static let knot = unit("speed.kn", "kn", .speed, UnitSpeed.knots)

    static let byte = unit("data.B", "B", .data, UnitInformationStorage.bytes)
    static let kilobyte = unit("data.KB", "KB", .data, UnitInformationStorage.kilobytes)
    static let megabyte = unit("data.MB", "MB", .data, UnitInformationStorage.megabytes)
    static let gigabyte = unit("data.GB", "GB", .data, UnitInformationStorage.gigabytes)
    static let terabyte = unit("data.TB", "TB", .data, UnitInformationStorage.terabytes)
    static let petabyte = unit("data.PB", "PB", .data, UnitInformationStorage.petabytes)
    static let kibibyte = unit("data.KiB", "KiB", .data, UnitInformationStorage.kibibytes)
    static let mebibyte = unit("data.MiB", "MiB", .data, UnitInformationStorage.mebibytes)
    static let gibibyte = unit("data.GiB", "GiB", .data, UnitInformationStorage.gibibytes)
    static let tebibyte = unit("data.TiB", "TiB", .data, UnitInformationStorage.tebibytes)
    static let pebibyte = unit("data.PiB", "PiB", .data, UnitInformationStorage.pebibytes)

    private static func unit(_ id: String, _ symbol: String, _ category: UnitCategory, _ dimension: Dimension) -> MeasureUnit {
        MeasureUnit(id: id, symbol: symbol, category: category, dimension: dimension)
    }

    /// The unit written as `text` (what follows the number): case, accents, spaces after a degree sign and dots do not
    /// matter, so "Sq. Ft." is "sq ft" and "mét" is "met". Only a capital B is a byte, since "b" is a bit.
    static func match(_ text: String) -> Match? {
        let words = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if words == "B" { return Match(unit: byte, isUnambiguous: false) }
        let key = words.folded.replacing(".", with: "").replacing("º", with: "°").replacing("° ", with: "°")
        guard let unit = aliases[key] else { return nil }
        return Match(unit: unit, isUnambiguous: key.count >= 2 && key != "in")
    }

    private static let aliases: [String: MeasureUnit] = {
        let entries: [(MeasureUnit, [String])] = [
            (millimeter, ["mm", "millimeter", "millimeters", "millimetre", "millimetres", "milimét", "mi-li-mét"]),
            (centimeter, ["cm", "centimeter", "centimeters", "centimetre", "centimetres", "xăng-ti-mét", "xentimét", "xăng ti mét"]),
            (meter, ["m", "meter", "meters", "metre", "metres", "mét"]),
            (kilometer, ["km", "kilometer", "kilometers", "kilometre", "kilometres", "ki lô mét", "ki-lô-mét", "kilômét", "cây số"]),
            (inch, ["in", "inch", "inches", "\"", "”", "″", "“", "inchs", "insơ"]),
            (foot, ["ft", "foot", "feet", "'", "’", "′", "‘", "feets", "phít"]),
            (yard, ["yd", "yds", "yard", "yards"]),
            (mile, ["mi", "mile", "miles", "dặm"]),
            (milligram, ["mg", "milligram", "milligrams", "miligam", "mi-li-gam"]),
            (gram, ["g", "gram", "grams", "gam"]),
            (kilogram, ["kg", "kgs", "kilogram", "kilograms", "kilo", "kilos", "ki lô gam", "ki-lô-gam", "kilôgam", "ki lô", "ký", "kí"]),
            (tonne, ["t", "tonne", "tonnes", "tấn"]),
            (ounce, ["oz", "ounce", "ounces", "ao-xơ", "aoxơ"]),
            (pound, ["lb", "lbs", "pound", "pounds", "cân anh"]),
            (celsius, [
                "°c", "c", "℃", "celsius", "độ c", "độ xê", "degree c", "degrees c", "degree celsius", "degrees celsius",
                "độ celsius", "deg c",
            ]),
            (fahrenheit, [
                "°f", "f", "℉", "fahrenheit", "độ f", "độ ép", "degree f", "degrees f", "degree fahrenheit",
                "degrees fahrenheit", "độ fahrenheit", "deg f",
            ]),
            (kelvin, ["k", "kelvin", "°k", "độ k"]),
            (milliliter, ["ml", "milliliter", "milliliters", "millilitre", "millilitres", "mililít", "mi-li-lít"]),
            (liter, ["l", "liter", "liters", "litre", "litres", "lít", "lit"]),
            (fluidOunce, ["fl oz", "floz", "fluid ounce", "fluid ounces"]),
            (cup, ["cup", "cups"]),
            (tablespoon, ["tbsp", "tablespoon", "tablespoons"]),
            (teaspoon, ["tsp", "teaspoon", "teaspoons"]),
            (pint, ["pt", "pint", "pints"]),
            (quart, ["qt", "quart", "quarts"]),
            (gallon, ["gal", "gallon", "gallons", "ga-lông", "ga lông", "galông"]),
            (squareCentimeter, ["cm²", "cm2", "sq cm", "square centimeter", "square centimeters", "square centimetre", "square centimetres"]),
            (squareMeter, [
                "m²", "m2", "sq m", "sqm", "square meter", "square meters", "square metre", "square metres", "mét vuông",
                "m vuông",
            ]),
            (squareKilometer, [
                "km²", "km2", "sq km", "square kilometer", "square kilometers", "square kilometre", "square kilometres",
                "ki lô mét vuông", "ki-lô-mét vuông",
            ]),
            (hectare, ["ha", "hectare", "hectares", "héc ta", "héc-ta", "hecta"]),
            (squareInch, ["in²", "in2", "sq in", "square inch", "square inches"]),
            (squareFoot, ["ft²", "ft2", "sq ft", "sqft", "square foot", "square feet", "feet vuông", "foot vuông"]),
            (squareYard, ["yd²", "yd2", "sq yd", "square yard", "square yards"]),
            (squareMile, ["mi²", "mi2", "sq mi", "square mile", "square miles", "dặm vuông"]),
            (acre, ["ac", "acre", "acres"]),
            (kilometersPerHour, [
                "km/h", "kmh", "kph", "kmph", "km/hr", "km/giờ", "kilometers per hour", "kilometres per hour",
            ]),
            (milesPerHour, ["mph", "mi/h", "mi/hr", "miles per hour", "dặm/giờ"]),
            (metersPerSecond, ["m/s", "mps", "meters per second", "metres per second", "mét/giây"]),
            (knot, ["kn", "kt", "knot", "knots", "hải lý/giờ"]),
            (byte, ["byte", "bytes"]),
            (kilobyte, ["kb", "kilobyte", "kilobytes"]),
            (megabyte, ["mb", "megabyte", "megabytes"]),
            (gigabyte, ["gb", "gigabyte", "gigabytes", "gig", "gigs"]),
            (terabyte, ["tb", "terabyte", "terabytes"]),
            (petabyte, ["pb", "petabyte", "petabytes"]),
            (kibibyte, ["kib", "kibibyte", "kibibytes"]),
            (mebibyte, ["mib", "mebibyte", "mebibytes"]),
            (gibibyte, ["gib", "gibibyte", "gibibytes"]),
            (tebibyte, ["tib", "tebibyte", "tebibytes"]),
            (pebibyte, ["pib", "pebibyte", "pebibytes"]),
        ]
        var table: [String: MeasureUnit] = [:]
        for (unit, names) in entries {
            for name in names { table[name.folded.replacing(".", with: "")] = unit }
        }
        return table
    }()
}
