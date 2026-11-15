import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct SaveLocationTests {
    @Test func rawValuesAreTheStoredSettingValues() {
        #expect(SaveLocation.allCases.map(\.rawValue) == ["desktop", "downloads", "pictures"])
        #expect(SaveLocation(rawValue: "desktop") == .desktop)
    }

    @Test func titlesNameTheFolders() {
        #expect(SaveLocation.allCases.map(\.title) == ["Desktop", "Downloads", "Pictures"])
    }

    @Test func standardDirectoriesAreTheUsersFolders() {
        #expect(SaveLocation.desktop.standardDirectory?.lastPathComponent == "Desktop")
        #expect(SaveLocation.downloads.standardDirectory?.lastPathComponent == "Downloads")
        #expect(SaveLocation.pictures.standardDirectory?.lastPathComponent == "Pictures")
    }
}
