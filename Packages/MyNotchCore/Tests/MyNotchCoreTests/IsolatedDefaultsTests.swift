import Foundation
import Testing
import MyNotchTestSupport

@Suite struct IsolatedDefaultsTests {
    private func writeAndRelease() -> String {
        let defaults = IsolatedUserDefaults(suiteName: "MyNotchTests.\(UUID().uuidString)")!
        defaults.set("value", forKey: "key")
        #expect(defaults.string(forKey: "key") == "value")
        return defaults.suite
    }

    @Test func releasingTheDefaultsEmptiesTheirDomain() {
        let suite = writeAndRelease()

        #expect(UserDefaults.standard.persistentDomain(forName: suite) == nil)
        #expect(UserDefaults(suiteName: suite)?.string(forKey: "key") == nil)
    }

    @Test func refusesNamesOutsideTheTestPrefix() {
        #expect(IsolatedUserDefaults(suiteName: "com.apple.finder") == nil)
    }

    @Test func makeIsolatedDefaultsReturnsFreshDefaults() {
        let first = makeIsolatedDefaults()
        let second = makeIsolatedDefaults()
        first.set(1, forKey: "key")
        #expect(second.object(forKey: "key") == nil)
    }
}
