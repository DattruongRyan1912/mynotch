import Testing
@testable import MediaModule

@Suite struct TransportControlTests {
    @Test func theSkipButtonsAreDisabledWhenNothingCanSkipAndThePlayButtonNever() {
        #expect(TransportControl.allCases == [.previous, .playPause, .next])
        for control in TransportControl.allCases {
            #expect(control.isEnabled(canSkip: true))
        }
        #expect(!TransportControl.previous.isEnabled(canSkip: false))
        #expect(!TransportControl.next.isEnabled(canSkip: false))
        #expect(TransportControl.playPause.isEnabled(canSkip: false), "play and pause work through MediaRemote everywhere")
    }

    @Test func aDisabledSkipButtonSaysWhatToInstallInsteadOfItsName() {
        #expect(TransportControl.skipUnavailableHelp == "Cài extension MyNotch cho YouTube để chuyển bài")
        #expect(TransportControl.next.help(isPlaying: true, canSkip: false) == "Cài extension MyNotch cho YouTube để chuyển bài")
        #expect(TransportControl.previous.help(isPlaying: false, canSkip: false) == "Cài extension MyNotch cho YouTube để chuyển bài")
    }

    @Test func everyOtherButtonKeepsItsLabelAsItsHelp() {
        #expect(TransportControl.next.help(isPlaying: true, canSkip: true) == "Bài sau")
        #expect(TransportControl.previous.help(isPlaying: true, canSkip: true) == "Bài trước")
        #expect(TransportControl.playPause.help(isPlaying: true, canSkip: false) == "Tạm dừng")
        #expect(TransportControl.playPause.help(isPlaying: false, canSkip: false) == "Phát")
    }

    @Test func theTabsActionsCanSkipByDefaultSoOlderCallersAreUnchanged() {
        let actions = MediaActions(send: { _ in }, seek: { _ in })
        #expect(actions.canSkip())
    }
}
