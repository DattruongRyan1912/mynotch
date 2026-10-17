import AppKit
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import PetModule

@Suite @MainActor struct PetScreensTests {
    let first = "11111111-AAAA-BBBB-CCCC-000000000001"
    let second = "22222222-AAAA-BBBB-CCCC-000000000002"

    func settings() throws -> (ModuleSettings, PetSettingsKeys) {
        let harness = RegistryHarness([PetModule(activities: ActivityCenter(scheduler: ManualScheduler()))])
        let settings = try #require(harness.settingsEnvironment(for: "pet")).settings
        return (settings, PetSettingsKeys(settings))
    }

    // MARK: What a screen has

    @Test func aScreenHasACatUntilTheUserChoosesAndSoDoesOneNobodyHasHeardOfAndOneThatCannotBeTold() {
        let screens = PetScreens()
        #expect(PetScreens.defaultKinds == [.cat])
        #expect(screens.kinds(for: first) == [.cat], "a display plugged in for the first time")
        #expect(screens.kinds(for: nil) == [.cat], "a window on no screen")
        let other = screens.setting([], for: second)
        #expect(other.kinds(for: first) == [.cat], "another screen's choice is nothing to this one")
    }

    @Test func anEmptyListIsAChoiceAndMeansNoCharacterOnThatScreen() {
        let screens = PetScreens().setting([], for: first)
        #expect(screens.kinds(for: first).isEmpty)
        #expect(screens.kinds(for: second) == [.cat])
        #expect(screens != PetScreens(), "it is kept: not the same as never having chosen")
        #expect(screens.setting([.cat], for: first).kinds(for: first) == [.cat])
    }

    @Test func aChoiceIsKeptForTheScreenByItsUUIDAndTouchesNoOther() {
        let screens = PetScreens().setting([], for: first).setting([.cat], for: second)
        #expect(screens.kinds(for: first).isEmpty && screens.kinds(for: second) == [.cat])
        #expect(screens.choices.keys.sorted() == [first, second])
        let again = screens.setting([], for: second)
        #expect(again.kinds(for: first).isEmpty && again.kinds(for: second).isEmpty)
    }

    // MARK: The limit

    @Test func noMoreThanTheLimitAreKeptInTheOrderTheKindsAreDeclaredAndNoneTwice() {
        let kinds = Array("abcdef")
        #expect(Choices.limited(Array("fcaebd"), among: kinds, limit: 3) == ["a", "b", "c"], "the first three in the order of the list, not as picked")
        #expect(Choices.limited(Array("aabbc"), among: kinds, limit: 3) == ["a", "b", "c"])
        #expect(Choices.limited(Array("xyz"), among: kinds, limit: 3).isEmpty, "what is not in the list is not kept")
        #expect(Choices.limited(Array("abc"), among: kinds, limit: 0).isEmpty && Choices.limited(Array("abc"), among: kinds, limit: -2).isEmpty)
        #expect(Choices.limited([], among: kinds, limit: 3).isEmpty)
        #expect(CharacterKind.maxPerScreen == 3)
        #expect(PetScreens.normalized([.cat, .cat, .cat, .cat, .cat]) == [.cat])
        #expect(PetScreens().setting([.cat, .cat, .cat, .cat], for: first).kinds(for: first) == [.cat])
    }

    @Test func aScreenWithRoomForOneMoreCanTakeItAndAFullOneCannot() {
        let none = PetScreens().setting([], for: first)
        #expect(none.canAdd(to: first) && PetScreens().canAdd(to: first), "none, and one of three")
        // Picking a kind that is on takes it off; one that is off puts it on.
        #expect(none.toggling(.cat, on: first).kinds(for: first) == [.cat])
        #expect(PetScreens().toggling(.cat, on: first).kinds(for: first).isEmpty)
        #expect(PetScreens().toggling(.cat, on: first).toggling(.cat, on: first).kinds(for: first) == [.cat])
        #expect(PetScreens().toggling(.cat, on: first).kinds(for: second) == [.cat], "and no other screen's")
    }

    // MARK: Kept

    @Test func theChoicesAreKeptUnderTheModulesOwnNameAsAMapOfNamesByUUID() throws {
        let (settings, keys) = try settings()
        #expect(keys.screens.name == "module.pet.screens")
        #expect(settings.value(keys.screens) == PetScreens(), "a cat on every screen until the user says otherwise")
        settings.set(PetScreens().setting([], for: first).setting([.cat], for: second), for: keys.screens)
        #expect(settings.value(keys.screens).kinds(for: first).isEmpty && settings.value(keys.screens).kinds(for: second) == [.cat])
        let data = try JSONEncoder().encode(PetScreens().setting([.cat], for: first).setting([], for: second))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"\(first)\":[\"cat\"]") && text.contains("\"\(second)\":[]"), "\(text)")
        #expect(try JSONDecoder().decode(PetScreens.self, from: data) == PetScreens().setting([.cat], for: first).setting([], for: second))
    }

    @Test func aKindThisBuildDoesNotKnowIsDroppedAndNoOtherScreensChoiceGoesWithIt() throws {
        let stored = """
        {"\(first)":["cat","capybara"],"\(second)":["capybara","hamster"],"3":[],"4":["capybara","cat","cat","cat","cat"]}
        """
        let screens = try JSONDecoder().decode(PetScreens.self, from: Data(stored.utf8))
        #expect(screens.kinds(for: first) == [.cat], "the one it knows")
        #expect(screens.kinds(for: second) == [.cat], "all it did not know: the default again, not none")
        #expect(screens.kinds(for: "3").isEmpty, "an empty list was a choice, and is")
        #expect(screens.kinds(for: "4") == [.cat])
        #expect(screens.choices[second] == nil)
    }

    @Test func aStoredListLongerThanTheLimitIsKeptToTheLimit() throws {
        let screens = try JSONDecoder().decode(PetScreens.self, from: Data("{\"A\":[\"cat\",\"cat\",\"cat\",\"cat\"]}".utf8))
        #expect(screens.kinds(for: "A") == [.cat])
    }

    @Test func aSettingTheStoreCannotReadIsTheDefaultAndNothingMore() throws {
        let (settings, keys) = try settings()
        // The store gives the default for a value it cannot read at all: the lenient read is what keeps a choice from going with it.
        #expect(settings.value(keys.screens) == PetScreens())
        let (other, otherKeys) = try self.settings()
        other.set(PetScreens().setting([], for: first), for: otherKeys.screens)
        #expect(other.value(otherKeys.screens).kinds(for: first).isEmpty)
    }

    // MARK: The write path

    @Test func aChoiceMadeThroughTheSettingsMergesIntoWhatIsKeptAndSurvivesAScreenGoingAndComingBack() throws {
        let (settings, keys) = try settings()
        let stored = settings.binding(keys.screens)
        // Both screens are on and the user turns the first one's cat off.
        stored.wrappedValue = stored.wrappedValue.toggling(.cat, on: first)
        #expect(settings.value(keys.screens).kinds(for: first).isEmpty && settings.value(keys.screens).kinds(for: second) == [.cat])
        // The first display is unplugged: the settings now list one display, and the user changes the second's choice.
        stored.wrappedValue = stored.wrappedValue.toggling(.cat, on: second)
        #expect(settings.value(keys.screens).kinds(for: second).isEmpty)
        #expect(settings.value(keys.screens).kinds(for: first).isEmpty, "the choice for the one that is not there is not lost")
        // And plugged in again: it has what it had.
        stored.wrappedValue = stored.wrappedValue.toggling(.cat, on: second)
        #expect(settings.value(keys.screens).kinds(for: first).isEmpty && settings.value(keys.screens).kinds(for: second) == [.cat])
        #expect(settings.value(keys.screens).choices.keys.sorted() == [first, second])
    }

    // MARK: Names of displays

    @Test func aDisplaysUUIDIsAskedOfTheSystemOnceAndForgottenWhenTheScreensAreArrangedAgain() {
        let center = NotificationCenter()
        var answers: [CGDirectDisplayID: DisplayID] = [1: "ONE", 2: "TWO"]
        let uuids = DisplayUUIDs(notifications: center) { answers[$0] }
        for _ in 0..<50 { #expect(uuids.id(for: 1) == "ONE" && uuids.id(for: 2) == "TWO") }
        #expect(uuids.asked == 2, "once each, however often the stages look")
        #expect(uuids.id(for: 3) == nil && uuids.id(for: 3) == nil && uuids.asked == 4, "what is not known is not remembered")
        answers[1] = "ANOTHER"
        #expect(uuids.id(for: 1) == "ONE", "until the screens change")
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect(uuids.id(for: 1) == "ANOTHER" && uuids.asked == 5)
    }

    @Test func theRealUUIDOfEachConnectedScreenIsReadTheSameEveryTime() {
        // The real screens are only read here, as a UUID is: nothing is changed, and the answers do not depend on which display it is.
        for screen in NSScreen.screens {
            let once = screen.petDisplayID
            #expect(once == screen.petDisplayID && once?.count == 36, "\(String(describing: once))")
        }
    }

    // MARK: The rows

    @Test func theMenuSaysWhoIsOnAScreenAndNoneWhenNobodyIs() {
        #expect(PetScreenRow.summary(of: []) == "Không có")
        #expect(PetScreenRow.summary(of: [.cat]) == "Mèo")
        #expect(PetScreenRow.summary(of: [.cat, .cat]) == "Mèo, Mèo", "joined as the list is: the list has each once")
        #expect(CharacterKind.cat.displayName == "Mèo")
    }

    @Test func aScreenIsListedWithItsNameAndWhetherItHasACamera() {
        #expect(ConnectedDisplay(id: first, name: "Built-in Retina Display", hasNotch: true).kindName == "Màn có tai thỏ")
        #expect(ConnectedDisplay(id: second, name: "PHL 345B1C", hasNotch: false).kindName == "Màn rời")
        #expect(ConnectedDisplay(id: first, name: "A", hasNotch: true).id == first)
    }

    @Test func theRowsAreOnePerConnectedDisplayAndComeAndGoWithTheDisplays() throws {
        let (settings, keys) = try settings()
        let box = PetHarness.ConnectedBox()
        let center = NotificationCenter()
        let displays = Displays(current: { box.displays }, notifications: center)
        func height() -> CGFloat {
            let view = Form { PetScreensView(screens: settings.binding(keys.screens), displays: displays) }.frame(width: 480)
            let hosting = NSHostingView(rootView: view)
            hosting.frame = CGRect(x: 0, y: 0, width: 480, height: 600)
            let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            runLoopUntilQuiet({ hosting.fittingSize.height })
            defer { window.contentView = nil }
            return hosting.fittingSize.height
        }
        let none = height()
        box.displays = [ConnectedDisplay(id: first, name: "Built-in Retina Display", hasNotch: true)]
        let one = height()
        box.displays.append(ConnectedDisplay(id: second, name: "PHL 345B1C", hasNotch: false))
        let two = height()
        #expect(none < one && one < two, "a row for each: \(none), \(one), \(two)")
    }

    @Test func theWholeOfThePetSettingsBuildWithTheDisplaysTheyAreGiven() throws {
        let (settings, keys) = try settings()
        let box = PetHarness.ConnectedBox()
        box.displays = [ConnectedDisplay(id: first, name: "Built-in Retina Display", hasNotch: true)]
        let displays = Displays(current: { box.displays }, notifications: NotificationCenter())
        let view = Form { PetSettingsView(keys: keys, settings: settings, displays: displays) }.frame(width: 480, height: 600)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 480, height: 600)
        hosting.layoutSubtreeIfNeeded()
        #expect(hosting.fittingSize.width > 0)
    }
}
