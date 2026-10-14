import Foundation

extension String {
    /// Lowercase and without accents, so "Hà Nội" and "ha noi", or "Mét" and "met", are the same word. "đ" is a letter of
    /// its own to Unicode and has to be folded by hand.
    var folded: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).replacing("đ", with: "d")
    }
}
