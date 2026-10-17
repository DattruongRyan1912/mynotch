import AppKit
import NotchUI

/// A display's identity as CoreGraphics gives it: a UUID that stays the same when the display is unplugged and plugged in again, which a
/// display's number and its place in the arrangement do not.
typealias DisplayID = String

extension NSScreen {
    /// The one way the module names a display, for the settings rows and for the stage a notch is shown by, so that the two always agree.
    var petDisplayID: DisplayID? {
        guard let number = (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
        return DisplayUUIDs.shared.id(for: number)
    }
}

/// The UUIDs of the displays by their numbers, each asked of the system once: the stages look at which display their views are on a few
/// times a second, and a UUID is a call to the window server and a string made each time. A display's number can mean another display
/// once the screens are arranged again, so what is known is forgotten then.
final class DisplayUUIDs {
    static let shared = DisplayUUIDs()

    private let make: (CGDirectDisplayID) -> DisplayID?
    private let notifications: NotificationCenter
    private var known: [CGDirectDisplayID: DisplayID] = [:]
    private var observer: (any NSObjectProtocol)?

    /// How many times the system was asked, for tests.
    private(set) var asked = 0

    init(
        notifications: NotificationCenter = .default,
        make: @escaping (CGDirectDisplayID) -> DisplayID? = { number in
            CGDisplayCreateUUIDFromDisplayID(number).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
        }
    ) {
        self.make = make
        self.notifications = notifications
        observer = notifications.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.known.removeAll() }
        }
    }

    isolated deinit {
        observer.map(notifications.removeObserver)
    }

    func id(for number: CGDirectDisplayID) -> DisplayID? {
        if let cached = known[number] { return cached }
        asked += 1
        guard let id = make(number) else { return nil }
        known[number] = id
        return id
    }
}

/// Which characters each display has, as the user chose: `[displayUUID: [CharacterKind]]`, kept under `module.pet.screens`.
///
/// A display that is not in it has the default, a cat, which is how the module was before there was a choice and what a display plugged
/// in for the first time gets. An empty list is a choice too: no character on that display. A choice is kept for good, by the display's
/// UUID, so a display that is unplugged and plugged in again has what it had, and one change never touches another display's.
nonisolated struct PetScreens: Equatable, Codable, Sendable {
    /// What a display has until the user chooses.
    static let defaultKinds: [CharacterKind] = [.cat]

    private(set) var choices: [DisplayID: [CharacterKind]]

    init(choices: [DisplayID: [CharacterKind]] = [:]) {
        self.choices = choices.mapValues(Self.normalized)
    }

    /// The characters on `display` (nil for one that cannot be told): the choice, or the default.
    func kinds(for display: DisplayID?) -> [CharacterKind] {
        display.flatMap { choices[$0] } ?? Self.defaultKinds
    }

    /// The choice with `kinds` for `display`, as many as a screen has room for.
    func setting(_ kinds: [CharacterKind], for display: DisplayID) -> PetScreens {
        var result = self
        result.choices[display] = Self.normalized(kinds)
        return result
    }

    /// The choice with `kind` taken off `display` if it is there, put on if it is not and the screen has room.
    func toggling(_ kind: CharacterKind, on display: DisplayID) -> PetScreens {
        let current = kinds(for: display)
        if current.contains(kind) { return setting(current.filter { $0 != kind }, for: display) }
        return canAdd(to: display) ? setting(current + [kind], for: display) : self
    }

    /// Whether another character fits on `display`.
    func canAdd(to display: DisplayID) -> Bool { kinds(for: display).count < CharacterKind.maxPerScreen }

    /// Every kind once, in the order the kinds are declared in (which is the order they are drawn in, whatever order the user picked them
    /// in), and no more than a screen has room for.
    static func normalized(_ kinds: [CharacterKind]) -> [CharacterKind] {
        Choices.limited(kinds, among: CharacterKind.allCases, limit: CharacterKind.maxPerScreen)
    }

    // MARK: Stored

    /// Read leniently: a character this build does not know (the setting came from a later one) is dropped from its display's list, and a
    /// display whose list was all of those has the default again; no other display's choice is lost for it, which a failed read would
    /// do, since the settings store gives the default for any value it cannot read.
    init(from decoder: any Decoder) throws {
        let stored = try decoder.singleValueContainer().decode([DisplayID: [String]].self)
        var choices: [DisplayID: [CharacterKind]] = [:]
        for (display, names) in stored {
            let known = names.compactMap(CharacterKind.init(rawValue:))
            if !names.isEmpty, known.isEmpty { continue }
            choices[display] = Self.normalized(known)
        }
        self.choices = choices
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(choices.mapValues { $0.map(\.rawValue) })
    }
}

/// Choosing some of a few, a few at most.
nonisolated enum Choices {
    /// `items` without repeats, in the order of `order` and not as given, and the first `limit` of them. Anything not in `order` is dropped.
    static func limited<Item: Hashable>(_ items: [Item], among order: [Item], limit: Int) -> [Item] {
        let chosen = Set(items)
        return Array(order.filter(chosen.contains).prefix(max(limit, 0)))
    }
}

/// A display that is connected now, as the settings list it.
struct ConnectedDisplay: Equatable, Identifiable {
    let id: DisplayID
    /// The name the system gives it, in the user's language.
    let name: String
    /// Whether it has a camera in its screen.
    let hasNotch: Bool

    /// What the settings say about it under its name.
    var kindName: String { hasNotch ? "Màn có tai thỏ" : "Màn rời" }
}

/// The displays that are connected, and where the news that they changed is heard: read from the system by default, and replaced by a test.
struct Displays {
    var current: () -> [ConnectedDisplay]
    var notifications: NotificationCenter

    static let system = Displays(
        current: {
            NSScreen.screens.compactMap { screen in
                guard let id = screen.petDisplayID else { return nil }
                let kind = NotchGeometry(screen: ScreenDescriptor(screen), config: NotchLayoutConfig()).kind
                return ConnectedDisplay(id: id, name: screen.localizedName, hasNotch: kind == .hardware)
            }
        },
        notifications: .default
    )
}
