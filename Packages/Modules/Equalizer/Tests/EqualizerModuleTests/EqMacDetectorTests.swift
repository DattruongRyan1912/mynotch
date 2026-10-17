import Testing
@testable import EqualizerModule

@Suite struct EqMacDetectorTests {
    @Test func lookForEqMacByItsBundleIdentifier() {
        #expect(EqMacDetector.bundleID == "com.bitgapp.eqmac")
    }

    @Test func detectedAmongTheRunningApps() {
        #expect(EqMacDetector.isRunning(among: ["com.apple.finder", "com.bitgapp.eqmac", nil]))
    }

    @Test func notDetectedWithoutIt() {
        #expect(!EqMacDetector.isRunning(among: ["com.apple.finder", nil, "com.bitgapp.eqmac.helper"]))
        #expect(!EqMacDetector.isRunning(among: [String?]()))
    }
}
