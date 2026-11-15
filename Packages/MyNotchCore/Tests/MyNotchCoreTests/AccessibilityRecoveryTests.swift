import Foundation
import Testing
@testable import MyNotchCore

private nonisolated final class SafeBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ value: T) { _value = value }
    var value: T {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

@Suite struct AccessibilityRecoveryTests {
    @Test func resetPassesCorrectArgumentsToRunner() throws {
        let recordedExecutable = SafeBox<String?>(nil)
        let recordedArguments = SafeBox<[String]?>(nil)

        try AccessibilityRecovery.reset(bundleID: "io.lucasvu.mynotch") { executable, arguments in
            recordedExecutable.value = executable
            recordedArguments.value = arguments
        }

        #expect(recordedExecutable.value == "/usr/bin/tccutil")
        #expect(recordedArguments.value == ["reset", "Accessibility", "io.lucasvu.mynotch"])
    }

    @Test func resetWithEmptyBundleIdDoesNothing() throws {
        let runnerCalled = SafeBox<Bool>(false)

        try AccessibilityRecovery.reset(bundleID: "") { _, _ in
            runnerCalled.value = true
        }

        #expect(!runnerCalled.value)
    }

    @Test func resetPropagatesRunnerFailure() {
        struct MockError: Error, Equatable {}

        #expect(throws: MockError.self) {
            try AccessibilityRecovery.reset(bundleID: "com.test.app") { _, _ in
                throw MockError()
            }
        }
    }

    @Test func recoverReturnsFalseWhenResetFails() async {
        struct MockError: Error {}

        let result = await AccessibilityRecovery.recover(bundleID: "com.test.app") { _, _ in
            throw MockError()
        }

        #expect(!result)
    }
}
