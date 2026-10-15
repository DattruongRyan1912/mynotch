import AppKit
import NotchUI
import SwiftUI
import Testing
@testable import MediaModule

@Suite struct SRGBColorBridgeTests {
    @Test func aColourSurvivesTheTripThroughSwiftUIWithinOneStep() {
        for color in [SRGBColor(red: 0.49, green: 0.36, blue: 1), SRGBColor(red: 0, green: 0, blue: 0), SRGBColor(red: 1, green: 0.5, blue: 0.25)] {
            let back = SRGBColor(color.color)
            #expect(back.isClose(to: color, tolerance: 1.0 / 255), "\(color) came back as \(back)")
        }
    }

    @Test func aColourFromAnotherColourSpaceIsConvertedToSRGB() {
        // Display P3 red is outside sRGB: it is clamped into it, and stays red.
        let p3 = Color(NSColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1))
        let converted = SRGBColor(p3)
        #expect(converted.red == 1 && converted.green < 0.05 && converted.blue < 0.05)
    }
}

@Suite struct ArtworkGlowTests {
    let tint = ArtworkPalette(primary: SRGBColor(red: 0.9, green: 0.2, blue: 0.1), secondary: SRGBColor(red: 0.1, green: 0.4, blue: 0.9))

    @Test func noTintNoGlow() {
        #expect(ArtworkGlow.spots(for: nil).isEmpty)
    }

    @Test func oneColourMakesOneSpotUnderTheCover() throws {
        let spots = ArtworkGlow.spots(for: ArtworkPalette(primary: tint.primary, secondary: nil))
        #expect(spots.count == 1)
        let spot = try #require(spots.first)
        #expect(spot.color == tint.primary)
        #expect(spot.center.x < 0.5, "the cover is on the left of the player")
    }

    @Test func aSecondColourMakesASecondSpotAwayFromTheFirst() throws {
        let spots = ArtworkGlow.spots(for: tint)
        #expect(spots.count == 2)
        #expect(spots[1].color == tint.secondary)
        #expect(spots[1].center.x > spots[0].center.x)
    }

    @Test func theGlowIsFaintSoTheTextOnItStaysReadable() {
        for spot in ArtworkGlow.spots(for: tint) {
            #expect(spot.opacity > 0 && spot.opacity <= 0.35)
        }
        // And what is the strongest colour at its strongest, over black, is still dark enough for white text: a contrast over 7.
        let brightest = SRGBColor(red: 1, green: 1, blue: 1)
        let strongest = ArtworkGlow.spots(for: ArtworkPalette(primary: brightest, secondary: nil))[0]
        let over = SRGBColor(red: 0, green: 0, blue: 0).mixed(with: brightest, amount: strongest.opacity)
        #expect((1.05) / (over.luminance + 0.05) > 7)
    }
}

@Suite struct ProgressTintTests {
    @Test func withoutATintTheBarKeepsItsOwnColours() {
        #expect(PlaybackProgressView.fill(tint: nil, isActive: false, accent: .green) == NotchTokens.primaryText.opacity(0.85))
        #expect(PlaybackProgressView.fill(tint: nil, isActive: true, accent: .green) == .green)
    }

    @Test func withATintTheBarIsTheTintWhetherOrNotThePointerIsOnIt() {
        let tint = SRGBColor(red: 0.9, green: 0.2, blue: 0.1)
        #expect(PlaybackProgressView.fill(tint: tint, isActive: false, accent: .green) == tint.color)
        #expect(PlaybackProgressView.fill(tint: tint, isActive: true, accent: .green) == tint.color)
    }
}

@Suite struct SpectrumColorRowsTests {
    @Test func theGradientPickersShowOnlyForTheGradient() {
        #expect(SpectrumColorRows.showsGradientPickers(for: .gradient))
        #expect(!SpectrumColorRows.showsGradientPickers(for: .artwork))
        #expect(!SpectrumColorRows.showsGradientPickers(for: .white))
    }

    @Test func theCoverModeSaysWhyItHasNoEffectWhileTheTintIsOff() {
        #expect(SpectrumColorRows.note(for: .artwork, tintIsOn: false) == SpectrumColorRows.tintOffNote)
        #expect(SpectrumColorRows.note(for: .artwork, tintIsOn: true) == nil)
        #expect(SpectrumColorRows.note(for: .white, tintIsOn: false) == nil)
        #expect(SpectrumColorRows.note(for: .gradient, tintIsOn: false) == nil)
        #expect(SpectrumColorRows.tintOffNote.contains(MediaSettingsView.tintTitle))
    }

    @Test func theTintHasItsOwnSwitchWithItsExplanation() {
        #expect(MediaSettingsView.tintTitle == "Màu theo ảnh bìa")
        #expect(!MediaSettingsView.tintExplanation.isEmpty)
        #expect(SpectrumColorRows.title == "Màu phổ âm thanh")
    }
}

/// The glow and the tinted bar are drawn in the tab's own space: the tab asks the notch for the same height with or without them.
@Suite struct TintedTabHeightTests {
    func idealHeight(tinted: Bool) -> CGFloat {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        store.apply(line: AdapterLines.track(), receivedAt: Date())
        store.setLyricsOn(true)
        if tinted {
            store.showTint(ArtworkPalette(primary: SRGBColor(red: 0.9, green: 0.2, blue: 0.1), secondary: SRGBColor(red: 0.1, green: 0.4, blue: 0.9)))
        }
        let tab = MediaTabView(
            store: store, actions: MediaActions(send: { _ in }, seek: { _ in }),
            volume: VolumeModel(hardware: NoVolumeHardware(), queue: ManualVolumeQueue())
        )
        .frame(width: 480 - 2 * (8 + NotchTokens.padding))
        return NSHostingView(rootView: tab).fittingSize.height
    }

    @Test func aTintChangesNothingOfTheTabsSize() {
        #expect(idealHeight(tinted: true) == idealHeight(tinted: false))
    }
}
