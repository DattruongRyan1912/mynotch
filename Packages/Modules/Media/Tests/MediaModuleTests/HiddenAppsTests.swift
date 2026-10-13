import Foundation
import Testing
@testable import MediaModule

@Suite final class HiddenAppsTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "HiddenAppsTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    deinit { try? FileManager.default.removeItem(at: directory) }

    /// A minimal bundle on disk, as NSOpenPanel would return it.
    func makeApp(_ name: String, bundleID: String?) throws -> URL {
        let app = directory.appending(path: "\(name).app", directoryHint: .isDirectory)
        let contents = app.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleName": name, "CFBundlePackageType": "APPL"]
        info["CFBundleIdentifier"] = bundleID
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appending(path: "Info.plist"))
        return app
    }

    @Test func addsBundleIdentifiersOfPickedAppsOnce() throws {
        let player = try makeApp("Player", bundleID: "com.example.Player")
        let browser = try makeApp("Browser", bundleID: "com.example.Browser")
        let broken = try makeApp("Broken", bundleID: nil)
        let result = HiddenAppsRows.adding(apps: [player, broken, browser, player], to: ["com.example.Browser", "com.example.Old"])
        #expect(result == ["com.example.Browser", "com.example.Old", "com.example.Player"])
    }
}
