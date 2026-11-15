import Foundation
import Testing
@testable import EqualizerModule

/// TC-2: Unit tests for Slider Gain Badges, Caution thresholds, and formatting.
@Suite("GainSlider Caution & Badge Tests")
struct GainSliderCautionTests {

    @Test("EQBandLabel display returns short frequency name when activeGain is nil")
    func bandLabelDisplayDefault() {
        #expect(EQBandLabel.display(band: 0, activeGain: nil) == "32")
        #expect(EQBandLabel.display(band: 1, activeGain: nil) == "64")
        #expect(EQBandLabel.display(band: 5, activeGain: nil) == "1k")
        #expect(EQBandLabel.display(band: 9, activeGain: nil) == "16k")
    }

    @Test("EQBandLabel display returns formatted gain text when activeGain is provided")
    func bandLabelDisplayActiveGain() {
        #expect(EQBandLabel.display(band: 0, activeGain: 14.5) == "+14,5 dB")
        #expect(EQBandLabel.display(band: 0, activeGain: 0.0) == "0 dB")
        #expect(EQBandLabel.display(band: 0, activeGain: -3.5) == "-3,5 dB")
    }

    @Test("GainScale cautionThreshold is exactly 12.0 dB")
    func cautionThresholdValue() {
        #expect(GainScale.cautionThreshold == 12.0)
    }

    @Test("GainScale isCaution evaluates correctly against 12.0 dB threshold")
    func cautionEvaluations() {
        #expect(GainScale.isCaution(12.0) == false)
        #expect(GainScale.isCaution(12.5) == true)
        #expect(GainScale.isCaution(24.0) == true)
        #expect(GainScale.isCaution(-24.0) == false)
        #expect(GainScale.isCaution(0.0) == false)
        #expect(GainScale.isCaution(.nan) == false)
    }

    @Test("GainScale fractions map to exact snapped half-dB gains at 80% and 90%")
    func fractionsMapToSnappedGains() {
        // Range -24...24:
        // at 0.80: -24 + 0.80 * 48 = 14.4 -> rounds to 14.5
        #expect(GainScale.gain(atFraction: 0.80) == 14.5)
        // at 0.90: -24 + 0.90 * 48 = 19.2 -> rounds to 19.0
        #expect(GainScale.gain(atFraction: 0.90) == 19.0)
    }

    @Test("GainSlider isCaution helper respects cautionAbove parameter")
    func gainSliderCautionCheck() {
        #expect(GainSlider.isCaution(15.0, cautionAbove: nil) == false)
        #expect(GainSlider.isCaution(15.0, cautionAbove: 12.0) == true)
        #expect(GainSlider.isCaution(10.0, cautionAbove: 12.0) == false)
    }
}
