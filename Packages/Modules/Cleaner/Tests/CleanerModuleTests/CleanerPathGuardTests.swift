import Foundation
import Testing
@testable import CleanerModule

@Suite("CleanerPathGuard Safety Tests")
struct CleanerPathGuardTests {
    let home = URL(filePath: "/Users/testuser", directoryHint: .isDirectory)

    @Test("Cho phép đường dẫn hợp lệ trong ~/Library")
    func testSafePathsAllowed() {
        let safeCache = home.appending(path: "Library/Caches/com.example.foo")
        #expect(CleanerPathGuard.check(safeCache, home: home) == .allowed)

        let safePref = home.appending(path: "Library/Preferences/com.example.foo.plist")
        #expect(CleanerPathGuard.check(safePref, home: home) == .allowed)

        let safeAppSupport = home.appending(path: "Library/Application Support/ExampleApp")
        #expect(CleanerPathGuard.check(safeAppSupport, home: home) == .allowed)
    }

    @Test("Chặn đường dẫn ngoài thư mục Home")
    func testOutsideHomeBlocked() {
        let systemPath = URL(filePath: "/System/Library/Caches")
        if case .rejected = CleanerPathGuard.check(systemPath, home: home) {} else {
            Issue.record("Đường dẫn ngoài home phải bị từ chối")
        }

        let rootPath = URL(filePath: "/Library/Application Support/Foo")
        if case .rejected = CleanerPathGuard.check(rootPath, home: home) {} else {
            Issue.record("Đường dẫn ngoài home phải bị từ chối")
        }
    }

    @Test("Chặn path traversal chứa '..'")
    func testPathTraversalBlocked() {
        let traversal = home.appending(path: "Library/Caches/../../etc/passwd")
        if case .rejected = CleanerPathGuard.check(traversal, home: home) {} else {
            Issue.record("Đường dẫn chứa '..' phải bị từ chối")
        }
    }

    @Test("Chặn iCloud Drive và CloudStorage theo NC-MYN-028")
    func testCloudStorageBlocked() {
        let icloud = home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs/foo")
        if case .rejected = CleanerPathGuard.check(icloud, home: home) {} else {
            Issue.record("Đường dẫn Mobile Documents phải bị từ chối")
        }

        let cloudStorage = home.appending(path: "Library/CloudStorage/OneDrive-Personal/foo")
        if case .rejected = CleanerPathGuard.check(cloudStorage, home: home) {} else {
            Issue.record("Đường dẫn CloudStorage phải bị từ chối")
        }
    }

    @Test("Chặn bundle ID Apple và MyNotch")
    func testProtectedBundleIDsBlocked() {
        let appleCache = home.appending(path: "Library/Caches/com.apple.Safari")
        if case .rejected = CleanerPathGuard.check(appleCache, home: home) {} else {
            Issue.record("Bundle com.apple.* phải bị từ chối")
        }

        let mynotchPref = home.appending(path: "Library/Preferences/io.lucasvu.mynotch.plist")
        if case .rejected = CleanerPathGuard.check(mynotchPref, home: home) {} else {
            Issue.record("Bundle của MyNotch phải bị từ chối")
        }
    }

    @Test("Chặn xoá chính ứng dụng MyNotch")
    func testMyNotchAppBlocked() {
        let mynotchApp = home.appending(path: "Applications/MyNotch.app")
        if case .rejected = CleanerPathGuard.check(mynotchApp, home: home) {} else {
            Issue.record("Ứng dụng MyNotch.app phải bị từ chối")
        }
    }

    @Test("Cho phép ứng dụng .app hợp lệ trong /Applications và /Applications/Utilities")
    func testApplicationsBundleAllowed() {
        let aldente = URL(filePath: "/Applications/AlDente.app")
        #expect(CleanerPathGuard.check(aldente, home: home) == .allowed)

        let slack = URL(filePath: "/Applications/Slack.app")
        #expect(CleanerPathGuard.check(slack, home: home) == .allowed)

        let utilityApp = URL(filePath: "/Applications/Utilities/Foo.app")
        #expect(CleanerPathGuard.check(utilityApp, home: home) == .allowed)
    }

    @Test("Chặn tệp không phải .app hoặc thư mục thường trong /Applications")
    func testApplicationsNonAppBlocked() {
        let textFile = URL(filePath: "/Applications/foo.txt")
        if case .rejected = CleanerPathGuard.check(textFile, home: home) {} else {
            Issue.record("Tệp .txt trong /Applications phải bị từ chối")
        }

        let folder = URL(filePath: "/Applications/SomeFolder")
        if case .rejected = CleanerPathGuard.check(folder, home: home) {} else {
            Issue.record("Thư mục thường trong /Applications phải bị từ chối")
        }
    }

    @Test("Chặn thư mục gốc /Applications")
    func testApplicationsRootBlocked() {
        let rootAppDir = URL(filePath: "/Applications")
        if case .rejected = CleanerPathGuard.check(rootAppDir, home: home) {} else {
            Issue.record("Thư mục gốc /Applications phải bị từ chối")
        }

        let slashAppDir = URL(filePath: "/Applications/")
        if case .rejected = CleanerPathGuard.check(slashAppDir, home: home) {} else {
            Issue.record("Thư mục /Applications/ phải bị từ chối")
        }
    }

    @Test("Chặn bundle lồng nhau hoặc nằm trong thư mục con lạ của /Applications")
    func testNestedBundleInApplicationsBlocked() {
        let helperApp = URL(filePath: "/Applications/Foo.app/Contents/Helper.app")
        if case .rejected = CleanerPathGuard.check(helperApp, home: home) {} else {
            Issue.record("Helper app lồng nhau phải bị từ chối")
        }

        let vendorApp = URL(filePath: "/Applications/Vendor/Foo.app")
        if case .rejected = CleanerPathGuard.check(vendorApp, home: home) {} else {
            Issue.record("Ứng dụng nằm dưới thư mục cấp 2 /Applications/Vendor phải bị từ chối")
        }
    }

    @Test("Chặn các ứng dụng trong /System/Applications")
    func testSystemApplicationsBlocked() {
        let calc = URL(filePath: "/System/Applications/Calculator.app")
        if case .rejected = CleanerPathGuard.check(calc, home: home) {} else {
            Issue.record("Calculator trong /System/Applications phải bị từ chối")
        }

        let safari = URL(filePath: "/System/Applications/Safari.app")
        if case .rejected = CleanerPathGuard.check(safari, home: home) {} else {
            Issue.record("Safari trong /System/Applications phải bị từ chối")
        }
    }

    @Test("Chặn MyNotch trong /Applications")
    func testMyNotchInApplicationsBlocked() {
        let myNotch = URL(filePath: "/Applications/MyNotch.app")
        if case .rejected = CleanerPathGuard.check(myNotch, home: home) {} else {
            Issue.record("MyNotch.app trong /Applications phải bị từ chối")
        }

        let myNotchLower = URL(filePath: "/Applications/mynotch.app")
        if case .rejected = CleanerPathGuard.check(myNotchLower, home: home) {} else {
            Issue.record("mynotch.app trong /Applications phải bị từ chối")
        }
    }

    @Test("Chặn traversal từ /Applications")
    func testApplicationsTraversalBlocked() {
        let traversal = URL(filePath: "/Applications/../System/Applications/Calculator.app")
        if case .rejected = CleanerPathGuard.check(traversal, home: home) {} else {
            Issue.record("Traversal từ /Applications phải bị từ chối")
        }
    }

    @Test("Kiểm tra helper isProtectedBundleID")
    func testProtectedBundleIDHelper() {
        #expect(CleanerPathGuard.isProtectedBundleID("com.apple.dt.Xcode"))
        #expect(CleanerPathGuard.isProtectedBundleID("COM.APPLE.Pages"))
        #expect(CleanerPathGuard.isProtectedBundleID("io.lucasvu.mynotch"))
        #expect(!CleanerPathGuard.isProtectedBundleID("com.example.foo"))
        #expect(!CleanerPathGuard.isProtectedBundleID(nil))
        #expect(!CleanerPathGuard.isProtectedBundleID(""))
        #expect(!CleanerPathGuard.isProtectedBundleID("   "))
    }

    @Test("Smoke test đối soát với các app thật trên đĩa hệ thống")
    func testRealSystemAppsOnDisk() {
        let aldente = URL(filePath: "/Applications/AlDente.app")
        if FileManager.default.fileExists(atPath: aldente.path) {
            let verdict = CleanerPathGuard.check(aldente, home: home)
            print("[SMOKE TEST] /Applications/AlDente.app verdict: \(verdict)")
            #expect(verdict == .allowed)
        }

        let calc = URL(filePath: "/System/Applications/Calculator.app")
        let calcVerdict = CleanerPathGuard.check(calc, home: home)
        print("[SMOKE TEST] /System/Applications/Calculator.app verdict: \(calcVerdict)")
        if case .rejected = calcVerdict {} else {
            Issue.record("Calculator phải bị rejected")
        }

        let mynotch = URL(filePath: "/Applications/MyNotch.app")
        let mynotchVerdict = CleanerPathGuard.check(mynotch, home: home)
        print("[SMOKE TEST] /Applications/MyNotch.app verdict: \(mynotchVerdict)")
        if case .rejected = mynotchVerdict {} else {
            Issue.record("MyNotch phải bị rejected")
        }
    }
}
