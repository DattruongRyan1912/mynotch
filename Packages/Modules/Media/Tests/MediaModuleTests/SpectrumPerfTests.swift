#if DEBUG
import NotchUI
import SwiftUI
import Testing
@testable import MediaModule

@Suite struct SpectrumPerfTests {
    @Test func everyRedrawOfTheBarsIsCounted() {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        let before = NotchPerf.counted(.spectrumUpdates)
        let renderer = ImageRenderer(content: NowPlayingBars(store: store))
        _ = renderer.cgImage
        #expect(NotchPerf.counted(.spectrumUpdates) > before)
    }
}
#endif
