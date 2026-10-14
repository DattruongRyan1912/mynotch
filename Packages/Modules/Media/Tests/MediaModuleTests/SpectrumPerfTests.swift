#if DEBUG
import AppKit
import MyNotchTestSupport
import NotchUI
import Testing
@testable import MediaModule

@Suite struct SpectrumPerfTests {
    @Test func everyRedrawOfTheBarsIsCounted() {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        store.apply(line: AdapterLines.track(), receivedAt: Date())
        let scheduler = ManualScheduler()
        let view = SpectrumBarsView(store: store, scheduler: scheduler, now: Date.init)
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
