#if DEBUG
import AppKit
import MyNotchTestSupport
import NotchUI
import Testing
@testable import MediaModule

@Suite struct SpectrumPerfTests {
    @Test func everyRedrawOfTheBarsIsCounted() {
        let scheduler = ManualScheduler()
        let store = NowPlayingStore(lookUpApp: { _ in nil }, scheduler: scheduler, now: Date.init)
        store.apply(line: AdapterLines.track(), receivedAt: Date())
        let view = SpectrumBarsView(store: store, accent: CGColor(gray: 1, alpha: 1))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 40, height: 20), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = view
        let before = NotchPerf.counted(.spectrumUpdates)
        store.showSpectrum([0.1, 0.2, 0.3, 0.4])
        scheduler.advance(by: .milliseconds(40))
        #expect(NotchPerf.counted(.spectrumUpdates) > before)
        window.contentView = nil
    }
}
#endif
