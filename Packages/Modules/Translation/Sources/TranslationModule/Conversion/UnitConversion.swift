import Foundation

/// Turns a quantity into what the user thinks in: their own measurement system first, then the other one.
enum UnitConversion {
    /// A result for each system whose best unit is not the unit the text already used, so "72 °F" for a metric user
    /// is "22 °C" and nothing else, and "1500 m" is "1,5 km" and "0,93 mi". Nothing for none of anything: a zero has no
    /// best unit (0 °C still has a value in °F, since temperatures start at different places).
    static func lines(for quantity: UnitQuantity, localeSystem: UnitSystem) -> [ConversionLine] {
        guard quantity.value != 0 || quantity.unit.category == .temperature else { return [] }
        let base = quantity.unit.base(quantity.value)
        var lines: [ConversionLine] = []
        for system in [localeSystem, localeSystem.other] {
            let result = render(base: base, category: quantity.unit.category, system: system)
            let line = ConversionLine(text: result.text)
            if result.primary != quantity.unit, !lines.contains(line) { lines.append(line) }
        }
        return lines
    }

    /// The unit that reads best for an amount (1,8 m as 180 cm, 907 g as 0,91 kg) in `system`, and the amount in it.
    /// `base` is in the category's base unit.
    static func render(base: Double, category: UnitCategory, system: UnitSystem) -> (primary: MeasureUnit, text: String) {
        let size = abs(base)
        if category == .length, system == .us, size >= 0.3048, size < 3 {
            return feetAndInches(base)
        }
        let unit = ladder(category, system).first { size < $0.below }!.unit
        return (unit, "\(VietnameseNumber.quick(unit.value(fromBase: base))) \(unit.symbol)")
    }

    /// "5 ft 11 in": people say heights this way, not as 5,92 ft.
    private static func feetAndInches(_ meters: Double) -> (primary: MeasureUnit, text: String) {
        let inches = Int((abs(meters) / 0.0254).rounded())
        let feet = inches / 12
        let rest = inches % 12
        let sign = meters < 0 ? "-" : ""
        return (UnitCatalog.foot, sign + "\(feet) ft" + (rest == 0 ? "" : " \(rest) in"))
    }

    /// Each unit serves amounts below its limit, in the base unit of the category.
    private static func ladder(_ category: UnitCategory, _ system: UnitSystem) -> [(below: Double, unit: MeasureUnit)] {
        typealias U = UnitCatalog
        let infinity = Double.infinity
        switch (category, system) {
        case (.length, .metric): return [(0.01, U.millimeter), (3, U.centimeter), (1000, U.meter), (infinity, U.kilometer)]
        case (.length, .us): return [(0.3048, U.inch), (402.336, U.foot), (infinity, U.mile)]
        case (.mass, .metric): return [(0.001, U.milligram), (0.5, U.gram), (1000, U.kilogram), (infinity, U.tonne)]
        case (.mass, .us): return [(0.45359237, U.ounce), (infinity, U.pound)]
        case (.temperature, .metric): return [(infinity, U.celsius)]
        case (.temperature, .us): return [(infinity, U.fahrenheit)]
        case (.volume, .metric): return [(1, U.milliliter), (infinity, U.liter)]
        case (.volume, .us): return [(1.892706, U.fluidOunce), (infinity, U.gallon)]
        case (.area, .metric):
            return [(0.1, U.squareCentimeter), (10_000, U.squareMeter), (1_000_000, U.hectare), (infinity, U.squareKilometer)]
        case (.area, .us): return [(1011.7, U.squareFoot), (2_589_988, U.acre), (infinity, U.squareMile)]
        case (.speed, .metric): return [(infinity, U.kilometersPerHour)]
        case (.speed, .us): return [(infinity, U.milesPerHour)]
        case (.data, .metric):
            return [(1e3, U.byte), (1e6, U.kilobyte), (1e9, U.megabyte), (1e12, U.gigabyte), (1e15, U.terabyte), (infinity, U.petabyte)]
        case (.data, .us):
            return [
                (1024, U.byte), (pow(1024, 2), U.kibibyte), (pow(1024, 3), U.mebibyte), (pow(1024, 4), U.gibibyte),
                (pow(1024, 5), U.tebibyte), (infinity, U.pebibyte),
            ]
        }
    }
}
