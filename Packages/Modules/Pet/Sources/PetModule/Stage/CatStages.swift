import AppKit
import MyNotchCore
import NotchUI
import Observation

/// The stages, one for each display that has characters, and the way the views of the notches get to theirs.
///
/// A stage is a screen's: the characters the user chose for it, its brains, its lane, its pointer, its clicks and its clock. The two
/// wings of one notch are views on the same display, so they share a stage and its clock; another display has another stage, with other
/// characters if the user chose them, and what one does is nothing to the other. A display that has none has no stage and nothing runs
/// for it.
///
/// A view tells the registry it is in a window (`attach`), and the registry finds its display from that window (`displayOf`) and puts the
/// view on that display's stage, made the first time it is asked for. The registry hears of a window changing screen, and of the
/// displays being arranged again, and moves the views to the stage of the display they are on now. When the user changes who is on which
/// screen, `apply` makes the stages so, at once: a screen that was given characters starts, and one that was given none stops.
@Observable
final class CatStages {
    /// What a window on a screen that cannot be told is on: a display like any other, with whatever is chosen for it (the default).
    static let unknownDisplay: DisplayID = "unknown"

    /// What the user chose for each display. Observed, so that what is drawn on a screen follows it.
    private(set) var screens = PetScreens()

    /// What the user chose for every character there is: the stages made now have it, and so do the ones made later.
    @ObservationIgnored var tuning = CatTuning() {
        didSet { stages.values.forEach { $0.tuning = tuning } }
    }

    @ObservationIgnored var coat = CatCoat.tabby {
        didSet { stages.values.forEach { $0.coat = coat } }
    }

    @ObservationIgnored var playsMeow = false {
        didSet { stages.values.forEach { $0.playsMeow = playsMeow } }
    }

    /// Where it hears of a window changing screen and of the displays being arranged again.
    @ObservationIgnored let notifications: NotificationCenter

    /// Which display a window is on; a test says.
    @ObservationIgnored let displayOf: (NSWindow) -> DisplayID?

    private struct Route {
        weak var host: CatSpriteView?
        var display: DisplayID
    }

    @ObservationIgnored private let makeStage: (DisplayID) -> CatStage
    @ObservationIgnored private var stages: [DisplayID: CatStage] = [:]
    @ObservationIgnored private var routes: [ObjectIdentifier: Route] = [:]
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var isShutDown = false

    /// `makeStage` makes the stage of a display that is given characters: one that reads what a test holds, or the real Mac.
    init(
        makeStage: @escaping (DisplayID) -> CatStage, displayOf: @escaping (NSWindow) -> DisplayID? = { $0.screen?.petDisplayID },
        notifications: NotificationCenter = .default
    ) {
        self.makeStage = makeStage
        self.displayOf = displayOf
        self.notifications = notifications
        let names = [NSWindow.didChangeScreenNotification, NSApplication.didChangeScreenParametersNotification]
        // Delivered where it is posted, which for a window and the screens is the main thread: a view is on its display's stage when the
        // news is out.
        observers = names.map { name in
            notifications.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.rerouteAll() }
            }
        }
    }

    /// A stage for each display, each reading the real Mac.
    convenience init(scheduler: any Scheduler) {
        self.init(makeStage: { _ in CatStage(scheduler: scheduler) })
    }

    isolated deinit {
        observers.forEach(notifications.removeObserver)
    }

    /// The stages there are, in the order of their displays.
    var all: [CatStage] { stages.sorted { $0.key < $1.key }.map(\.value) }

    /// The stage of `display`, made the first time it is asked for; nil for a display that has no characters.
    func stage(for display: DisplayID) -> CatStage? {
        guard !isShutDown else { return nil }
        if let existing = stages[display] { return existing }
        let kinds = screens.kinds(for: display)
        guard !kinds.isEmpty else { return nil }
        let stage = makeStage(display)
        stage.tuning = tuning
        stage.coat = coat
        stage.playsMeow = playsMeow
        stage.characters = kinds
        stages[display] = stage
        return stage
    }

    /// Whether `display` has any character at all, which is whether the notch on it is made room for them.
    func hasCharacters(on display: DisplayID) -> Bool { !screens.kinds(for: display).isEmpty }

    // MARK: Views

    /// The display a view is on: its window's, or the unknown one while it has none.
    private func display(of host: CatSpriteView) -> DisplayID {
        host.window.flatMap(displayOf) ?? Self.unknownDisplay
    }

    /// A view is in a window: it is shown by its display's stage, if the display has one.
    func attach(_ host: CatSpriteView) {
        guard !isShutDown else { return }
        let display = display(of: host)
        routes[ObjectIdentifier(host)] = Route(host: host, display: display)
        place(host, on: display)
    }

    /// A view left its window.
    func detach(_ host: CatSpriteView) {
        routes[ObjectIdentifier(host)] = nil
        leave(host)
    }

    /// A view's display may be another: it is moved to that one's stage.
    func reroute(_ host: CatSpriteView) {
        guard !isShutDown, var route = routes[ObjectIdentifier(host)] else { return }
        let display = display(of: host)
        guard display != route.display else { return }
        leave(host)
        route.display = display
        routes[ObjectIdentifier(host)] = route
        place(host, on: display)
    }

    func rerouteAll() {
        routes = routes.filter { $0.value.host != nil }
        for route in Array(routes.values) {
            if let host = route.host { reroute(host) }
        }
    }

    /// Whether a view is shown by the stage of a display it is no longer on.
    func isRoutedElsewhere(_ host: CatSpriteView) -> Bool {
        routes[ObjectIdentifier(host)].map { $0.display != display(of: host) } ?? false
    }

    private func place(_ host: CatSpriteView, on display: DisplayID) {
        guard let stage = stage(for: display) else { return }
        host.stage = stage
        stage.attach(host)
    }

    private func leave(_ host: CatSpriteView) {
        host.stage?.detach(host)
        host.stage = nil
    }

    // MARK: What the user chose

    /// Puts the stages as `screens` says, at once: a display that has no character any more loses its stage, and with it everything that
    /// ran for it; one that has others has them; a display with a view on it that had no stage has one now.
    func apply(screens new: PetScreens) {
        guard new != screens else { return }
        screens = new
        for (display, stage) in Array(stages) {
            let kinds = new.kinds(for: display)
            if kinds.isEmpty {
                stages[display] = nil
                stage.shutDown()
                routes.values.filter { $0.display == display }.forEach { $0.host?.stage = nil }
            } else {
                stage.characters = kinds
            }
        }
        for route in Array(routes.values) {
            if let host = route.host, host.stage == nil { place(host, on: route.display) }
        }
    }

    /// The module stopped: nothing runs and no view is taken on again.
    func shutDown() {
        isShutDown = true
        observers.forEach(notifications.removeObserver)
        observers = []
        stages.values.forEach { $0.shutDown() }
        stages.removeAll()
        routes.values.forEach { $0.host?.stage = nil }
        routes.removeAll()
    }
}
