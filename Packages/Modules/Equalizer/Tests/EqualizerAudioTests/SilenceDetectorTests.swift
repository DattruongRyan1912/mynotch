import Testing
@testable import EqualizerAudio

@Suite struct SilenceDetectorTests {
    @Test func silenceForMoreThanTenSecondsIsLikelyDenied() {
        var detector = SilenceDetector()
        #expect(detector.update(peak: 0, at: 100) == nil)
        #expect(detector.update(peak: 0, at: 105) == nil)
        #expect(detector.update(peak: 0, at: 110) == nil)
        #expect(!detector.isLikelyDenied)
        #expect(detector.update(peak: 0, at: 110.1) == true)
        #expect(detector.isLikelyDenied)
        // Reported once, not on every silent frame.
        #expect(detector.update(peak: 0, at: 115) == nil)
    }

    @Test func soundRestartsTheCount() {
        var detector = SilenceDetector()
        detector.update(peak: 0, at: 0)
        #expect(detector.update(peak: 0.2, at: 9) == nil)
        #expect(detector.update(peak: 0, at: 10) == nil)
        #expect(detector.update(peak: 0, at: 19) == nil)
        #expect(detector.update(peak: 0, at: 20.1) == true)
    }

    @Test func noNewSamplesCountAsSilence() {
        var detector = SilenceDetector()
        detector.update(peak: nil, at: 0)
        #expect(detector.update(peak: nil, at: 10.5) == true)
    }

    @Test func soundAfterADenialClearsIt() {
        var detector = SilenceDetector()
        detector.update(peak: 0, at: 0)
        detector.update(peak: 0, at: 11)
        #expect(detector.update(peak: 0.01, at: 12) == false)
        #expect(!detector.isLikelyDenied)
        #expect(detector.update(peak: 0.01, at: 13) == nil)
    }

    /// A denied tap hands over exact zeros; the quietest real music is far above the threshold.
    @Test func quietMusicIsNotSilence() {
        var detector = SilenceDetector()
        detector.update(peak: 0.0001, at: 0)
        #expect(detector.update(peak: 0.0001, at: 30) == nil)
        #expect(!detector.isLikelyDenied)
    }
}
