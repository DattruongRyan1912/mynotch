import Foundation
import Testing
@testable import FanHelperKit

/// The names that the app, the launchd plist and the helper must agree on, pinned in one place.
@Suite struct FanHelperIdentityTests {
    @Test func theMachServiceIsTheJobLabelAndTheFileIsNamedAfterIt() {
        #expect(FanHelperIdentity.machServiceName == "io.lucasvu.mynotch.fanhelper")
        #expect(FanHelperIdentity.plistName == FanHelperIdentity.machServiceName + ".plist")
    }

    @Test func theProgramIsInsideTheAppsExecutablesFolder() {
        #expect(FanHelperIdentity.helperProgram == "Contents/MacOS/mynotch-fan-helper")
        #expect(FanHelperIdentity.helperProgram.hasSuffix("/" + FanHelperIdentity.helperIdentifier))
    }

    /// Xcode signs a command-line tool with its product name as the identifier (the sibling tools in the built app all are), and
    /// the app's requirement on the helper is built from this one.
    @Test func theHelperIsSignedWithItsProductName() {
        #expect(FanHelperIdentity.helperIdentifier == "mynotch-fan-helper")
    }

    @Test func theLaunchdPlistInTheRepoSaysWhatTheCodeExpects() throws {
        let plist = try Self.launchdPlist()
        #expect(plist["Label"] as? String == FanHelperIdentity.machServiceName)
        #expect(plist["BundleProgram"] as? String == FanHelperIdentity.helperProgram)
        #expect((plist["MachServices"] as? [String: Any])?.keys.sorted() == [FanHelperIdentity.machServiceName])
        #expect(plist["AssociatedBundleIdentifiers"] as? [String] == [FanHelperIdentity.appIdentifier])
        #expect(plist["Program"] == nil, "BundleProgram, not an absolute path: the helper is the one inside the app")
        #expect(plist["ProgramArguments"] == nil)
        #expect(plist["KeepAlive"] == nil && plist["RunAtLoad"] == nil, "launchd starts it when the app connects, not before")
    }

    /// The plist the app target copies into `Contents/Library/LaunchDaemons`; found from this file's place in the repo.
    static func launchdPlist(file: StaticString = #filePath) throws -> [String: Any] {
        var url = URL(fileURLWithPath: "\(file)")
        for _ in 0..<6 { url.deleteLastPathComponent() }   // the file, FanHelperKitTests, Tests, Performance, Modules, Packages: the repo root
        url.append(path: "Tools/mynotch-fan-helper/Daemon/\(FanHelperIdentity.plistName)")
        let data = try Data(contentsOf: url)
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }
}
