import Foundation
import MyNotchCore

/// What the Mac says about the moment and the user, so tests can set all of it.
struct ConversionEnvironment {
    var now: () -> Date = Date.init
    var localZone: () -> TimeZone = { TimeZone.autoupdatingCurrent }
    /// The measurement system of the Mac's region: metric for vi_VN, US for en_US.
    var system: () -> UnitSystem = { Locale.autoupdatingCurrent.measurementSystem == .us ? .us : .metric }
}

/// Everything the quick convert takes from outside the module; tests replace it with fakes.
struct ConversionSetup {
    var rates: any RatesHTTPClient = URLSessionRatesClient()
    var environment = ConversionEnvironment()
    /// What reads quantities in a text. Tests replace it with one that watches when and where it is called.
    var recognize: @Sendable (String, Bool) -> Recognition = { QuantityRecognizer.recognize($0, currency: $1) }
}

/// What to show for a text now, and the rates it is still waiting for.
nonisolated struct ConversionPlan: Sendable {
    struct PendingMoney: Sendable {
        var index: Int
        var amount: MoneyAmount
        var target: String
    }

    var conversions: [Conversion] = []
    /// The text is nothing but quantities that were converted, so it is not translated.
    var isPure = false
    var pending: [PendingMoney] = []
}

/// The settings and the moment a plan is made from, taken on the main actor so the work itself can leave it.
nonisolated struct ConversionInputs: Sendable {
    var currencyOn: Bool
    var currencyTarget: String
    var time: TimeEnvironment
    var system: UnitSystem
    var recognize: @Sendable (String, Bool) -> Recognition
}

nonisolated enum ConversionPlanner {
    /// Reads the quantities in `text` and converts all but money, which waits for the rates. Runs off the main actor and
    /// stops early when the task that awaits it is cancelled, which is what a newer selection does.
    @concurrent static func plan(for text: String, inputs: ConversionInputs) async -> ConversionPlan {
        guard QuickConverter.mightHaveQuantities(text) else { return ConversionPlan() }
        let recognition = inputs.recognize(text, inputs.currencyOn)
        var plan = ConversionPlan()
        var showedAll = true
        for item in recognition.items {
            switch item.quantity {
            case .unit(let quantity):
                let lines = UnitConversion.lines(for: quantity, localeSystem: inputs.system)
                if lines.isEmpty { showedAll = false } else { plan.conversions.append(Conversion(source: item.source, outcome: .lines(lines))) }
            case .time(let query):
                let conversion = TimeConversion.conversion(for: query, source: item.source, in: inputs.time)
                if case .lines(let lines) = conversion.outcome, !lines.isEmpty { plan.conversions.append(conversion) } else { showedAll = false }
            case .math(let result):
                let line = ConversionLine(text: VietnameseNumber.format(result.value))
                plan.conversions.append(Conversion(source: item.source + " =", outcome: .lines([line])))
            case .money(let amount):
                let target = target(for: amount.currency, own: inputs.currencyTarget)
                plan.pending.append(.init(index: plan.conversions.count, amount: amount, target: target))
                plan.conversions.append(Conversion(source: item.source, outcome: .fetching, creditsRates: true))
            }
        }
        plan.isPure = recognition.isPure && showedAll && !plan.conversions.isEmpty
        return plan
    }

    /// The user's currency, or, for an amount already in it, the dollar (or the euro for a user of dollars): there is
    /// nothing to learn from "100.000đ" in dong.
    private static func target(for currency: String, own: String) -> String {
        guard currency == own else { return own }
        return own == "USD" ? "EUR" : "USD"
    }
}

/// Turns the quantities in a text into conversions, with the user's settings: the zones, and whether and into what to
/// convert money. Everything but money is worked out at once, off the main actor; money waits for the day's rates, which
/// are fetched only when the setting is on and the text has an amount.
final class QuickConverter {
    private let settings: ModuleSettings
    private let keys: TranslationKeys
    private let rates: ExchangeRateService
    private let environment: ConversionEnvironment
    private let recognize: @Sendable (String, Bool) -> Recognition

    init(
        settings: ModuleSettings, keys: TranslationKeys, rates: ExchangeRateService, environment: ConversionEnvironment,
        recognize: @escaping @Sendable (String, Bool) -> Recognition = { QuantityRecognizer.recognize($0, currency: $1) }
    ) {
        self.settings = settings
        self.keys = keys
        self.rates = rates
        self.environment = environment
        self.recognize = recognize
    }

    /// A text can only be a quantity if it has a digit and is short, which is all it takes to skip the rest of the work
    /// for most selections. A selection longer than `QuantityRecognizer.maxSelectionLength` is just translated.
    nonisolated static func mightHaveQuantities(_ text: String) -> Bool {
        text.contains(where: \.isASCIIDigit) && text.count <= QuantityRecognizer.maxSelectionLength
    }

    /// The conversions for `text`. Reads the settings now and does the rest off the main actor.
    func plan(for text: String) async -> ConversionPlan {
        let zones = [keys.firstZone, keys.secondZone].compactMap { TimeZone(identifier: settings.value($0)) }
        let inputs = ConversionInputs(
            currencyOn: settings.value(keys.convertCurrency),
            currencyTarget: settings.value(keys.currencyTarget),
            time: TimeEnvironment(now: environment.now(), local: environment.localZone(), zones: zones),
            system: environment.system(),
            recognize: recognize
        )
        return await ConversionPlanner.plan(for: text, inputs: inputs)
    }

    /// The plan with the amounts of money worked out: waits for the rates, which come from the cache when they are
    /// less than a day old.
    func resolve(_ plan: ConversionPlan) async -> [Conversion] {
        guard !plan.pending.isEmpty else { return plan.conversions }
        let rates = await rates.rates()
        var conversions = plan.conversions
        for pending in plan.pending {
            conversions[pending.index] = money(pending, rates: rates, source: conversions[pending.index].source)
        }
        return conversions
    }

    private func money(_ pending: ConversionPlan.PendingMoney, rates: ExchangeRates?, source: String) -> Conversion {
        var conversion = Conversion(source: source, outcome: .failed("Chưa lấy được tỷ giá"), creditsRates: true)
        guard let rates else { return conversion }
        let value = NSDecimalNumber(decimal: pending.amount.value).doubleValue
        guard let converted = rates.convert(value, from: pending.amount.currency, to: pending.target) else {
            conversion.outcome = .failed("Chưa có tỷ giá \(rates.rates[pending.amount.currency] == nil ? pending.amount.currency : pending.target)")
            return conversion
        }
        conversion.outcome = .lines([ConversionLine(text: CurrencyCatalog.format(converted, code: pending.target))])
        // Rates "fetched in the future" (the clock was set back) are not known to be fresh either.
        let age = environment.now().timeIntervalSince(rates.fetchedAt)
        let isStale = age < 0 || age >= ExchangeRateService.lifetime
        conversion.note = "Tỷ giá ngày " + Self.day(rates.rateDate) + (isStale ? ", chưa lấy được tỷ giá mới" : "")
        return conversion
    }

    /// "14/10/2026" in UTC, the zone the source states its days in.
    static func day(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT")!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%02d/%02d/%04d", parts.day ?? 0, parts.month ?? 0, parts.year ?? 0)
    }
}
