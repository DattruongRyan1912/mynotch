import Foundation
import Testing
@testable import TranslationModule

final class LoadCounter {
    var count = 0
}

@Suite struct SupportedLanguagesTests {
    @Test func sortsByVietnameseNameAndLoadsOnce() async {
        let loads = LoadCounter()
        let languages = SupportedLanguages {
            loads.count += 1
            return ["vi", "ja", "de", "da", "pl", "en", "ar-AE", "en-GB"].map(Locale.Language.init(identifier:))
        }
        let first = await languages.all()
        // Vietnamese collation: "Ả Rập" before "Anh", "Đan Mạch"/"Đức" right after "Ba Lan", before "Nhật".
        #expect(first.map(\.minimalIdentifier) == ["ar-AE", "en", "en-GB", "pl", "da", "de", "ja", "vi"])
        #expect(await languages.all() == first)
        #expect(loads.count == 1)
    }

    @Test func namesAreVietnamese() {
        #expect(SupportedLanguages.name(of: Locale.Language(identifier: "en-GB")) == "Tiếng Anh (Vương quốc Anh)")
        #expect(SupportedLanguages.name(of: Locale.Language(identifier: "vi")) == "Tiếng Việt")
    }
}
