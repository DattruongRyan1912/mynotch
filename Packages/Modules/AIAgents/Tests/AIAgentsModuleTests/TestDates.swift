import Foundation

/// Parses a fixture timestamp written without fractional seconds, independently of the code under test.
func utc(_ text: String) -> Date {
    try! Date(text, strategy: .iso8601)
}
