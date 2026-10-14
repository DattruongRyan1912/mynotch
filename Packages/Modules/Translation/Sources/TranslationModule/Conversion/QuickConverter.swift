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
}

/// What to show for a text now, and the rates it is still waiting for.
struct ConversionPlan {
    struct PendingMoney {
        var index: Int
        var amount: MoneyAmount
        var target: String
    }

    var conversions: [Conversion] = []
    /// The text is nothing but quantities that were converted, so it is not translated.
    var isPure = false
    var pending: [PendingMoney] = []
}

/// Turns the quantities in a text into conversions, with the user's settings: the zones, and whether and into what to
/// convert money. Everything but money is worked out at once; money waits for the day's rates, which are fetched
/// only when the setting is on and the text has an amount.
final class QuickConverter {
    private let settings: ModuleSettings
    private let keys: TranslationKeys
    private let rates: ExchangeRateService
    private let environment: ConversionEnvironment

    init(settings: ModuleSettings, keys: TranslationKeys, rates: ExchangeRateService, environment: ConversionEnvironment) {
        self.settings = settings
        self.keys = keys
        self.rates = rates
        self.environment = environment
    }

    func plan(for text: String) -> ConversionPlan {
        let currencyOn = settings.value(keys.convertCurrency)
        let recognition = QuantityRecognizer.recognize(text, currency: currencyOn)
        var plan = ConversionPlan()
        var showedAll = true
        for item in recognition.items {
            switch item.quantity {
            case .unit(let quantity):
                let lines = UnitConversion.lines(for: quantity, localeSystem: environment.system())
                if lines.isEmpty { showedAll = false } else { plan.conversions.append(Conversion(source: item.source, outcome: .lines(lines))) }
            case .time(let query):
                let conversion = TimeConversion.conversion(for: query, source: item.source, in: timeEnvironment())
                if case .lines(let lines) = conversion.outcome, !lines.isEmpty { plan.conversions.append(conversion) } else { showedAll = false }
            case .math(let result):
                let line = ConversionLine(text: VietnameseNumber.format(result.value))
                plan.conversions.append(Conversion(source: item.source + " =", outcome: .lines([line])))
            case .money(let amount):
                let target = target(for: amount.currency)
                plan.pending.append(.init(index: plan.conversions.count, amount: amount, target: target))
                plan.conversions.append(Conversion(source: item.source, outcome: .fetching, creditsRates: true))
            }
        }
        plan.isPure = recognition.isPure && showedAll && !plan.conversions.isEmpty
        return plan
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

    private func timeEnvironment() -> TimeEnvironment {
        let zones = [keys.firstZone, keys.secondZone].compactMap { TimeZone(identifier: settings.value($0)) }
        return TimeEnvironment(now: environment.now(), local: environment.localZone(), zones: zones)
    }

    /// The user's currency, or, for an amount already in it, the dollar (or the euro for a user of dollars): there is
    /// nothing to learn from "100.000đ" in dong.
    private func target(for currency: String) -> String {
        let own = settings.value(keys.currencyTarget)
        guard currency == own else { return own }
        return own == "USD" ? "EUR" : "USD"
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
        let isStale = environment.now().timeIntervalSince(rates.fetchedAt) >= ExchangeRateService.lifetime
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
