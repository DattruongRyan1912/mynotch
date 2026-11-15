import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct OCRLanguagesTests {
    /// Vision reports Vietnamese as vi-VT and Chinese by script, so those are the languages the lists below must handle.
    let supported = ["en-US", "fr-FR", "vi-VT", "zh-Hans", "zh-Hant"].map(Locale.Language.init(identifier:))
    var english: Locale.Language { supported[0] }
    var french: Locale.Language { supported[1] }
    var vietnamese: Locale.Language { supported[2] }
    var simplified: Locale.Language { supported[3] }
    var traditional: Locale.Language { supported[4] }

    @Test func storedIdentifiersSelectTheSupportedLanguagesTheyMatch() {
        let selected = OCRService.defaultLanguages
        #expect(OCRLanguages.isSelected(vietnamese, in: selected, supported: supported))
        #expect(OCRLanguages.isSelected(english, in: selected, supported: supported))
        #expect(!OCRLanguages.isSelected(french, in: selected, supported: supported))
        #expect(!OCRLanguages.isSelected(simplified, in: selected, supported: supported))
    }

    @Test func turningALanguageOnAppendsAnIdentifierThatSelectsOnlyIt() {
        let selected = OCRLanguages.toggling(traditional, in: OCRService.defaultLanguages, supported: supported)
        #expect(selected.count == 3)
        #expect(OCRLanguages.isSelected(traditional, in: selected, supported: supported))
        #expect(!OCRLanguages.isSelected(simplified, in: selected, supported: supported))
        #expect(OCRService.recognitionLanguages(for: selected, supported: supported) == [vietnamese, english, traditional])
    }

    @Test func turningALanguageOffRemovesEveryIdentifierMatchingIt() {
        let selected = OCRLanguages.toggling(vietnamese, in: ["vi-VN", "en-US", "vi-Latn-VT", "xx-YY"], supported: supported)
        #expect(selected == ["en-US", "xx-YY"])
        #expect(!OCRLanguages.isSelected(vietnamese, in: selected, supported: supported))
    }

    @Test func togglingTwiceGivesTheOriginalSelection() {
        let once = OCRLanguages.toggling(french, in: OCRService.defaultLanguages, supported: supported)
        let twice = OCRLanguages.toggling(french, in: once, supported: supported)
        #expect(OCRService.recognitionLanguages(for: twice, supported: supported) == [vietnamese, english])
    }

    @Test func namesAreInVietnamese() {
        #expect(OCRLanguages.name(of: vietnamese) == "Tiếng Việt")
        #expect(OCRLanguages.name(of: english) == "Tiếng Anh")
    }

    @Test func summaryListsTheSelectedNamesOrSaysThereAreNone() {
        #expect(OCRLanguages.summary(of: OCRService.defaultLanguages, supported: supported) == "Tiếng Việt, Tiếng Anh")
        #expect(OCRLanguages.summary(of: [], supported: supported) == "Tự động")
        #expect(OCRLanguages.summary(of: ["xx-YY"], supported: supported) == "Tự động")
    }
}
