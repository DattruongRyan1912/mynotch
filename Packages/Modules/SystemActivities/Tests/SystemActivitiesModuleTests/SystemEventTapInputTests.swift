import AppKit
import Testing
@testable import SystemActivitiesModule

/// `SystemEventTap.input(for:_:)` reads what the callback is handed. The events here are built in memory and never
/// posted, and no tap is created.
@Suite struct SystemEventTapInputTests {
    private static let systemDefined = CGEventType(rawValue: 14)!

    private func systemDefinedEvent(subtype: Int16, data1: Int, modifiers: NSEvent.ModifierFlags = []) throws -> CGEvent {
        let event = try #require(NSEvent.otherEvent(
            with: .systemDefined, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
            subtype: subtype, data1: data1, data2: -1))
        return try #require(event.cgEvent)
    }

    @Test func aSystemDefinedEventKeepsItsSubtypeItsKeyAndItsModifiers() throws {
        let data1 = (21 << 16) | (0xA << 8) | 1
        let event = try systemDefinedEvent(subtype: 8, data1: data1, modifiers: [.option, .shift])
        guard case .systemDefined(let subtype, let read, let modifiers)? = SystemEventTap.input(for: Self.systemDefined, event) else {
            Issue.record("a system-defined event is read as one")
            return
        }
        #expect(subtype == 8)
        #expect(read == data1)
        #expect(modifiers.isSuperset(of: [.option, .shift]))
        // And what the HUD makes of it.
        #expect(MediaKeyEvent(subtype: subtype, data1: read, modifiers: modifiers)
            == MediaKeyEvent(key: .keyboardLightUp, isDown: true, isRepeat: true, isFine: true))
    }

    @Test(arguments: [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput])
    func macOSSwitchingTheTapOffIsReportedWhateverEventComesWithIt(type: CGEventType) throws {
        let event = try #require(CGEvent(source: nil))
        guard case .disabled? = SystemEventTap.input(for: type, event) else {
            Issue.record("\(type) is read as the tap being disabled")
            return
        }
    }

    @Test func otherEventTypesAreNotOursAndPassThrough() throws {
        let key = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        #expect(SystemEventTap.input(for: .keyDown, key) == nil)
        #expect(SystemEventTap.input(for: .mouseMoved, key) == nil)
    }

    @Test func anEventOfAnotherKindUnderTheSystemDefinedTypeIsNotOurs() throws {
        let key = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        #expect(SystemEventTap.input(for: Self.systemDefined, key) == nil)
    }
}
