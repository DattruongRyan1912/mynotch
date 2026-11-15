import AppKit
import Foundation
import MyNotchCore
import Testing
@testable import ClipboardModule

@Suite struct ClipboardSoundGateTests {
    /// What the gate says to a sound at each of `times`, in order.
    func answers(_ times: [Double]) -> [Bool] {
        var gate = ClipboardSoundGate()
        return times.map { gate.admit(at: $0) }
    }

    @Test func theFirstSoundPlaysAndAnotherWithinThreeHundredMillisecondsDoesNot() {
        #expect(answers([100, 100.0, 100.1, 100.299, 100.3, 100.5, 100.6]) == [true, false, false, false, true, false, true])
        #expect(ClipboardSoundGate.interval == 0.3)
    }

    /// A sound that was held back does not start the wait again: a steady stream still lets one through every 300 ms.
    @Test func aRefusedSoundDoesNotStartTheWaitAgain() {
        #expect(answers([0, 0.2, 0.31, 0.4, 0.5, 0.6, 0.62]) == [true, false, true, false, false, false, true])
    }

    @Test func aClockThatStepsBackDoesNotLetMoreThrough() {
        #expect(answers([500, 100, 499, 500.2, 500.3]) == [true, false, false, false, true])
    }
}

@Suite final class ClipboardSoundModuleTests {
    let fixture = OptionalFeaturesFixture()
    var module: ClipboardModule { fixture.module }
    var sounds: [ClipboardSound] { fixture.sounds.played }

    /// Time enough between two things that the rate limit is not what makes the second one silent.
    func later() { fixture.clock.advance(by: 1) }

    // MARK: Off, and on

    @Test func soundsAreOffByDefault() async throws {
        let (settings, keys) = try fixture.settings()
        #expect(settings.value(keys.playSounds) == false)
        await fixture.start()
        fixture.copy("một đoạn chữ")
        let item = try fixture.item("một đoạn chữ")
        later()
        module.paste(item)
        fixture.harness.scheduler.advance(by: .milliseconds(80))
        #expect(fixture.keystrokes.pasteCount == 1)
        #expect(sounds.isEmpty)
    }

    @Test func aCaptureMakesOneSoundWhenOn() async throws {
        try fixture.setSounds(true)
        await fixture.start()
        fixture.copy("một")
        #expect(sounds == [.captured])
        later()
        fixture.copy("hai")
        later()
        fixture.copy("ba")
        #expect(sounds == [.captured, .captured, .captured])
    }

    @Test func aPasteMakesOneSoundWhenOn() async throws {
        try fixture.setSounds(true)
        await fixture.start()
        fixture.copy("để dán")
        let item = try fixture.item("để dán")
        later()
        fixture.system.trusted = true
        module.paste(item)
        // The sound is for ⌘V going out, not for asking.
        #expect(sounds == [.captured])
        fixture.harness.scheduler.advance(by: .milliseconds(80))
        #expect(fixture.keystrokes.pasteCount == 1)
        #expect(sounds == [.captured, .pasted])
        #expect(ClipboardSound.captured.systemName == "Pop")
        #expect(ClipboardSound.pasted.systemName == "Tink")
    }

    /// MyNotch's own write has the marker, and the monitor drops it: only the paste's sound plays.
    @Test func myNotchsOwnWriteIsNotACaptureAndMakesNoSound() async throws {
        try fixture.setSounds(true)
        await fixture.start()
        fixture.copy("viết lại")
        let item = try fixture.item("viết lại")
        later()
        let before = fixture.items.count
        module.paste(item)
        fixture.harness.scheduler.advance(by: .milliseconds(80))
        // The write is on the pasteboard now, with the marker; the next poll sees it.
        #expect(fixture.pasteboard.writes.count == 1)
        later()
        fixture.harness.scheduler.advance(by: ClipboardModuleTests.pollInterval)
        #expect(fixture.items.count == before)
        #expect(sounds == [.captured, .pasted])
    }

    @Test func aRecopyOfAnItemIsACaptureToo() async throws {
        try fixture.setSounds(true)
        await fixture.start()
        fixture.copy("hai lần")
        later()
        fixture.copy("hai lần")
        #expect(fixture.items.count == 1)
        #expect(sounds == [.captured, .captured])
    }

    // MARK: When there is none

    @Test func aPasteThatFellBackToACopyIsSilent() async throws {
        try fixture.setSounds(true)
        await fixture.start()
        fixture.copy("không quyền")
        let item = try fixture.item("không quyền")
        later()
        fixture.system.trusted = false
        #expect(module.paste(item) == .copiedNeedsPermission)
        fixture.harness.scheduler.advance(by: .seconds(1))
        #expect(fixture.keystrokes.pasteCount == 0)
        #expect(sounds == [.captured])
    }

    @Test func aClickThatCopiesMakesNoSound() async throws {
        try fixture.setSounds(true)
        await fixture.start()
        let (settings, keys) = try fixture.settings()
        settings.set(.copy, for: keys.clickAction)
        fixture.copy("chỉ chép")
        let item = try fixture.item("chỉ chép")
        later()
        #expect(module.activate(item) == .copied)
        fixture.harness.scheduler.advance(by: .seconds(1))
        #expect(sounds == [.captured])
    }

    @Test func aPasteThatTheKeyboardRefusedIsSilent() async throws {
        try fixture.setSounds(true)
        await fixture.start()
        fixture.copy("bàn phím chưa về")
        let item = try fixture.item("bàn phím chưa về")
        later()
        // The panel's way: the gate says no, nothing is pasted.
        #expect(module.activate(item, beforePaste: { false }) == .copied)
        fixture.harness.scheduler.advance(by: .seconds(1))
        #expect(fixture.keystrokes.pasteCount == 0)
        #expect(sounds == [.captured])
    }

    @Test func aSecretIsSilent() async throws {
        try fixture.setSounds(true)
        await fixture.start()
        let (settings, keys) = try fixture.settings()
        // Dropped by the classifier: never recorded, never heard.
        fixture.copy("mật khẩu thật", extraTypes: ["org.nspasteboard.ConcealedType"])
        #expect(fixture.items.isEmpty)
        #expect(sounds.isEmpty)
        // Kept because the user chose to keep them: recorded, still silent.
        settings.set(false, for: keys.ignoreSensitive)
        later()
        fixture.copy("mật khẩu giữ lại", extraTypes: ["org.nspasteboard.ConcealedType"])
        #expect(fixture.items.count == 1)
        #expect(sounds.isEmpty)
    }

    @Test(arguments: [
        "password: hunter2hunter2", "mật khẩu: abc12345", "ghp_abcdefghijklmnopqrstuvwxyz0123456789", "AKIAIOSFODNN7EXAMPLE",
        "https://api.example.org/v1?token=abcdef1234567890", "-----BEGIN PRIVATE KEY-----\nMIIE",
    ])
    func somethingThatLooksLikeASecretIsSilent(_ text: String) async throws {
        try fixture.setSounds(true)
        await fixture.start()
        fixture.copy(text)
        #expect(fixture.items.count == 1, "\(text)")
        #expect(sounds.isEmpty, "\(text)")
        // An ordinary item right after is heard: the silence was about the secret.
        later()
        fixture.copy("một câu bình thường")
        #expect(sounds == [.captured])
    }

    /// The caption promises silence for these, and a paste goes through one place that knows only that ⌘V went out, so the item is
    /// remembered when the paste is asked for.
    @Test func aPasteOfASecretOrALockedItemIsSilent() async throws {
        try fixture.setSounds(true)
        await fixture.start()
        let (settings, keys) = try fixture.settings()
        settings.set(false, for: keys.ignoreSensitive)
        fixture.copy("mã của trình quản lý", extraTypes: ["org.nspasteboard.ConcealedType"])
        fixture.copy("password: hunter2hunter2")
        fixture.copy("trong két")
        _ = try await fixture.pinToOpenLockedBoard(try fixture.item("trong két"))
        fixture.copy("một câu bình thường")
        #expect(sounds == [.captured])

        var pastes = 0
        for text in ["mã của trình quản lý", "password: hunter2hunter2", "trong két"] {
            later()
            module.paste(try fixture.item(text))
            fixture.harness.scheduler.advance(by: .milliseconds(80))
            pastes += 1
            #expect(fixture.keystrokes.pasteCount == pastes, "\(text) is pasted")
            #expect(sounds == [.captured], "\(text) makes no sound")
        }
        // An ordinary one, right after, is heard: the silence was about the item.
        later()
        module.paste(try fixture.item("một câu bình thường"))
        fixture.harness.scheduler.advance(by: .milliseconds(80))
        #expect(sounds == [.captured, .pasted])
        // And the item is the latest one asked for: a secret pasted after an ordinary one is silent, an ordinary one after a secret is not.
        later()
        module.paste(try fixture.item("password: hunter2hunter2"))
        fixture.harness.scheduler.advance(by: .milliseconds(80))
        later()
        module.paste(try fixture.item("một câu bình thường"))
        fixture.harness.scheduler.advance(by: .milliseconds(80))
        #expect(sounds == [.captured, .pasted, .pasted])
    }

    @Test func anIgnoredAppIsSilent() async throws {
        try fixture.setSounds(true)
        await fixture.start()
        let (settings, keys) = try fixture.settings()
        settings.set(["com.apple.Safari"], for: keys.excludedBundleIDs)
        fixture.copy("từ app bị bỏ qua")
        #expect(fixture.items.isEmpty)
        #expect(sounds.isEmpty)
    }

    @Test func pausedRecordingIsSilent() async throws {
        try fixture.setSounds(true)
        await fixture.start()
        let (settings, keys) = try fixture.settings()
        settings.set(true, for: keys.paused)
        fixture.copy("khi tạm dừng")
        #expect(fixture.items.isEmpty)
        #expect(sounds.isEmpty)
    }

    @Test func anItemOfALockedBoardIsSilent() async throws {
        try fixture.setSounds(true)
        await fixture.start()
        fixture.copy("trong két")
        let item = try fixture.item("trong két")
        _ = try await fixture.pinToOpenLockedBoard(item)
        later()
        let before = sounds.count
        // Copied again, the item is moved to the top: it is in a board that has a lock, which is for what must stay private.
        fixture.copy("trong két")
        #expect(sounds.count == before)
    }

    // MARK: Pause All

    @Test func pauseAllModulesIsSilent() async throws {
        try fixture.setSounds(true)
        await fixture.start()
        fixture.copy("trước khi dừng")
        let item = try fixture.item("trước khi dừng")
        later()
        // A ⌘V is on its way when everything is paused.
        module.paste(item)
        await fixture.harness.registry.pauseAll()
        #expect(fixture.harness.registry.state(of: "clipboard") != .running)
        fixture.harness.scheduler.advance(by: .seconds(1))
        #expect(fixture.keystrokes.pasteCount == 0)
        #expect(sounds == [.captured])

        // And nothing is recorded or pasted while it lasts.
        later()
        fixture.copy("trong lúc dừng")
        fixture.harness.scheduler.advance(by: .seconds(1))
        #expect(module.paste(item) == nil)
        #expect(sounds == [.captured])

        // Resumed, it is heard again.
        await fixture.harness.registry.resumeAll()
        later()
        fixture.copy("sau khi tiếp tục")
        #expect(sounds == [.captured, .captured])
    }

    // MARK: Every way of pasting, and the limit

    @Test func theStackShortcutsPasteMakesTheSoundWhenItGoesOut() async throws {
        try fixture.setSounds(true)
        await fixture.start()
        module.startStack()
        fixture.copy("mục trong ngăn xếp")
        later()
        let before = sounds
        module.pasteNextInStack()
        fixture.harness.scheduler.advance(by: .seconds(1))
        #expect(fixture.keystrokes.pasteCount == 1)
        #expect(Array(sounds.dropFirst(before.count)) == [.pasted])
    }

    @Test func aBurstOfCopiesMakesOneSound() async throws {
        try fixture.setSounds(true)
        await fixture.start()
        for number in 1...8 {
            fixture.clock.advance(by: 0.02)
            fixture.copy("trong một loạt \(number)")
        }
        #expect(fixture.items.count == 8)
        #expect(sounds == [.captured])
    }

    @Test func aPasteRightAfterACaptureIsHeldBackAndAfterTheWaitIsHeard() async throws {
        try fixture.setSounds(true)
        await fixture.start()
        fixture.copy("vừa chép xong")
        let item = try fixture.item("vừa chép xong")
        fixture.clock.advance(by: 0.1)
        module.paste(item)
        fixture.harness.scheduler.advance(by: .milliseconds(80))
        #expect(fixture.keystrokes.pasteCount == 1)
        #expect(sounds == [.captured])
        fixture.clock.advance(by: 0.3)
        module.paste(item)
        fixture.harness.scheduler.advance(by: .milliseconds(80))
        #expect(sounds == [.captured, .pasted])
    }

    @Test func turningTheSettingOffSilencesTheNextOne() async throws {
        try fixture.setSounds(true)
        await fixture.start()
        fixture.copy("còn kêu")
        #expect(sounds == [.captured])
        try fixture.setSounds(false)
        later()
        fixture.copy("hết kêu")
        #expect(sounds == [.captured])
    }

    @Test func aModuleMadeWithoutASpeakerHasNone() {
        // What every other test gets: nothing to play with.
        ClipboardSilentPlayer().play(.captured)
        ClipboardSilentPlayer().play(.pasted)
    }
}
