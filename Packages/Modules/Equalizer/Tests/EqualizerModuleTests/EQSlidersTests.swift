import Foundation
import MyNotchCore
import Testing
@testable import EqualizerModule

/// What the sliders print and how a touch becomes a gain, without a view.
@Suite struct EQSlidersTests {
    // MARK: The number next to a slider

    @Test func gainsAreWrittenWithADecimalCommaAndASign() {
        #expect(GainFormat.text(1.5) == "+1,5 dB")
        #expect(GainFormat.text(-1.5) == "-1,5 dB")
        #expect(GainFormat.text(0.5) == "+0,5 dB")
        #expect(GainFormat.text(-0.5) == "-0,5 dB")
    }

    @Test func wholeGainsHaveNoDecimals() {
        #expect(GainFormat.text(3) == "+3 dB")
        #expect(GainFormat.text(-3) == "-3 dB")
        #expect(GainFormat.text(12) == "+12 dB")
        #expect(GainFormat.text(-12) == "-12 dB")
    }

    @Test func noGainIsZeroWithNoSign() {
        #expect(GainFormat.text(0) == "0 dB")
        #expect(GainFormat.text(-0.0) == "0 dB")
        #expect(GainFormat.text(0.04) == "0 dB")
        #expect(GainFormat.text(-0.04) == "0 dB")
    }

    // MARK: A touch is a gain

    @Test func theEndsOfTheTrackAreTheEndsOfTheRange() {
        #expect(GainScale.gain(atFraction: 0) == -24)
        #expect(GainScale.gain(atFraction: 1) == 24)
        #expect(GainScale.gain(atFraction: 0.5) == 0)
        #expect(GainScale.gain(atFraction: 0.75) == 12)
    }

    @Test func aTouchPastTheEndsIsHeldToTheRange() {
        #expect(GainScale.gain(atFraction: -3) == -24)
        #expect(GainScale.gain(atFraction: 4) == 24)
    }

    @Test func gainsSnapToHalfDecibels() {
        let step = 1.0 / 96
        #expect(GainScale.gain(atFraction: 0.5 + 0.2 * step) == 0)
        #expect(GainScale.gain(atFraction: 0.5 + 0.6 * step) == 0.5)
        #expect(GainScale.gain(atFraction: 0.5 - 0.6 * step) == -0.5)
        #expect(GainScale.gain(atFraction: 0.5 + 3 * step) == 1.5)
        for tenth in 0...100 {
            let gain = GainScale.gain(atFraction: Double(tenth) / 100)
            #expect(gain * 2 == (gain * 2).rounded())
            #expect(EQProfile.gainRange.contains(gain))
        }
    }

    @Test func aGainIsWhereItsKnobSits() {
        #expect(GainScale.fraction(of: -24) == 0)
        #expect(GainScale.fraction(of: 0) == 0.5)
        #expect(GainScale.fraction(of: 24) == 1)
        #expect(GainScale.fraction(of: 30) == 1)
        #expect(GainScale.fraction(of: -30) == 0)
    }

    @Test func aKnobAndATouchAgree() {
        for gain in stride(from: -24.0, through: 24.0, by: 0.5) {
            #expect(GainScale.gain(atFraction: GainScale.fraction(of: gain)) == gain)
        }
    }

    @Test func bandRangeIsPlusMinus24AndPreampRangeRemainsPlusMinus12() {
        #expect(GainScale.gain(atFraction: 0, range: EQProfile.gainRange) == -24)
        #expect(GainScale.gain(atFraction: 1, range: EQProfile.gainRange) == 24)
        #expect(GainScale.gain(atFraction: 0.5, range: EQProfile.gainRange) == 0)
        for gain in stride(from: -24.0, through: 24.0, by: 0.5) {
            #expect(GainScale.gain(atFraction: GainScale.fraction(of: gain, range: EQProfile.gainRange), range: EQProfile.gainRange) == gain)
        }

        #expect(GainScale.gain(atFraction: 0, range: EQProfile.preampRange) == -12)
        #expect(GainScale.gain(atFraction: 1, range: EQProfile.preampRange) == 12)
        #expect(GainScale.gain(atFraction: 0.5, range: EQProfile.preampRange) == 0)
        for gain in stride(from: -12.0, through: 12.0, by: 0.5) {
            #expect(GainScale.gain(atFraction: GainScale.fraction(of: gain, range: EQProfile.preampRange), range: EQProfile.preampRange) == gain)
        }

        #expect(GainFormat.text(24) == "+24 dB")
        #expect(GainFormat.text(-24) == "-24 dB")
        #expect(GainFormat.text(7.2) == "+7,2 dB")
    }

    // MARK: The bands

    @Test func everyBandHasALabel() {
        #expect(EQBandLabel.short.count == EQProfile.frequencies.count)
        #expect(EQBandLabel.short == ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"])
    }

    @Test func spokenNamesUseHertzAndKilohertz() {
        #expect(EQBandLabel.spoken(32) == "32 Hz")
        #expect(EQBandLabel.spoken(500) == "500 Hz")
        #expect(EQBandLabel.spoken(1000) == "1 kHz")
        #expect(EQBandLabel.spoken(16000) == "16 kHz")
    }

    // MARK: The profile row

    @Test func addingAProfileKeepsItsRenameOpen() {
        let new = UUID()
        #expect(ProfileEdit.renaming(new).afterSelection(new) == .renaming(new))
        #expect(ProfileEdit.confirmingDelete(new).afterSelection(new) == .confirmingDelete(new))
    }

    @Test func choosingOrDeletingAnotherProfileEndsWhatWasBeingDone() {
        let one = UUID()
        let other = UUID()
        #expect(ProfileEdit.renaming(one).afterSelection(other) == .choosing)
        #expect(ProfileEdit.confirmingDelete(one).afterSelection(other) == .choosing)
        #expect(ProfileEdit.confirmingDelete(one).afterSelection(nil) == .choosing)
        #expect(ProfileEdit.choosing.afterSelection(other) == .choosing)
    }
}
