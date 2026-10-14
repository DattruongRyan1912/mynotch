import Foundation

/// One result under a conversion, with the copy button of its own.
struct ConversionLine: Equatable {
    /// What the result is for, such as the time zone; nil when the conversion needs no label.
    var label: String?
    /// The result as the line shows it, and as its copy button copies it.
    var text: String
}

/// What the quick convert found in the text, and what it came to.
struct Conversion: Equatable {
    enum Outcome: Equatable {
        case lines([ConversionLine])
        /// Currency: waiting for the day's rates.
        case fetching
        /// Currency: why there is no result ("Chưa lấy được tỷ giá").
        case failed(String)
    }

    /// The quantity as the text wrote it, such as "5 ft 11 in".
    var source: String
    var outcome: Outcome
    /// A line under the results: the rates' date, or how a time was read.
    var note: String?
    /// Rates need a credit line; the view adds the link.
    var creditsRates = false
}
