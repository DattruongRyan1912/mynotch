@testable import MediaModule

/// Stands in for `SystemAudioTap`, so no test ever captures system audio or triggers its permission prompt.
final class FakeSpectrumSource: SpectrumSource {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var onEvent: (@MainActor (SpectrumEvent) -> Void)?

    var isStarted: Bool { onEvent != nil }

    func start(onEvent: @escaping @MainActor (SpectrumEvent) -> Void) {
        startCount += 1
        self.onEvent = onEvent
    }

    func stop() {
        stopCount += 1
        onEvent = nil
    }

    func emit(_ event: SpectrumEvent) { onEvent?(event) }
}
