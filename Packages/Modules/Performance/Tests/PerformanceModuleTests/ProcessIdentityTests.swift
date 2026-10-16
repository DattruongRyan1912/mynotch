import AppKit
import Testing
@testable import PerformanceModule

@Suite struct ProcessIdentityTests {
    func process(_ pid: Int32, _ name: String, path: String?, footprint: UInt64 = 1 << 30) -> ProcessMemory {
        ProcessMemory(pid: pid, name: name, footprint: footprint, path: path)
    }

    @Test func aRowHasTheNameAndTheSizeOfItsProcess() {
        let rows = ProcessIdentity().rows(for: [process(900_001, "python3.11", path: "/usr/local/bin/python3.11", footprint: 3 << 30)])
        #expect(rows.map(\.name) == ["python3.11"])
        #expect(rows.map(\.size) == ["3 GB"])
        #expect(rows.map(\.id) == [900_001])
    }

    @Test func aProcessOutsideAnyAppHasNoIcon() {
        let rows = ProcessIdentity().rows(for: [process(900_001, "python3.11", path: "/usr/local/bin/python3.11"), process(900_002, "kernel thing", path: nil)])
        #expect(rows.allSatisfy { $0.icon == nil })
    }

    @Test func aHelperInsideAnAppGetsTheAppsIconAndKeepsItsOwnName() {
        let helper = "/Applications/Google Chrome.app/Contents/Frameworks/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        let rows = ProcessIdentity().rows(for: [process(900_003, "Google Chrome Helper (Renderer)", path: helper)])
        #expect(rows.first?.name == "Google Chrome Helper (Renderer)")
        #expect(rows.first?.icon != nil)
    }

    @Test func aRunningAppTakesItsLocalizedNameAndIcon() throws {
        let finder = try #require(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first)
        let rows = ProcessIdentity().rows(for: [process(finder.processIdentifier, "Finder", path: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder")])
        #expect(rows.first?.name == finder.localizedName)
        #expect(rows.first?.icon != nil)
    }

    @Test func iconsAreKeptByAppAndTheKeptOnesAreBounded() {
        let identity = ProcessIdentity()
        let one = process(900_004, "a", path: "/Applications/Safari.app/Contents/MacOS/a")
        _ = identity.rows(for: [one, one, one])
        #expect(identity.cachedIcons == 1)
        let many = (0..<(ProcessIdentity.iconLimit + 10)).map { process(Int32(910_000 + $0), "p\($0)", path: "/Applications/Fake\($0).app/Contents/MacOS/p") }
        _ = identity.rows(for: many)
        #expect(identity.cachedIcons <= ProcessIdentity.iconLimit)
    }
}
