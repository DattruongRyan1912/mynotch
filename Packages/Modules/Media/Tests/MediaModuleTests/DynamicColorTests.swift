import AppKit
import Dispatch
import Testing
@testable import MediaModule

/// AppKit asks a dynamic colour for its value on whatever thread is drawing with it, so the provider must not be main-actor
/// isolated: the runtime traps when an isolated closure is entered from another thread.
@Suite struct DynamicColorTests {
    @Test func aDynamicColourResolvesOnAnotherThread() async throws {
        let color = NSColor.dynamic(.labelColor, alpha: 0.5)
        let alpha = await withCheckedContinuation { (done: CheckedContinuation<CGFloat?, Never>) in
            DispatchQueue.global().async {
                done.resume(returning: color.usingColorSpace(.sRGB)?.alphaComponent)
            }
        }
        #expect(abs(try #require(alpha) - 0.5) < 0.001)
    }

    @Test func aDynamicColourKeepsItsAlphaOnTheMainThreadToo() throws {
        let alpha = try #require(NSColor.dynamic(.secondaryLabelColor, alpha: 0.7).usingColorSpace(.sRGB)?.alphaComponent)
        #expect(abs(alpha - 0.7) < 0.001)
    }
}
