import AppKit
import MyNotchCore
import Observation
import SwiftUI

/// Pixel pets that live on the collapsed notch when nothing else is going on: a cat now, and each screen has the ones the user chose.
///
/// They are a live activity at the lowest priority, with one rule on top: it is published only while no other module has an activity of
/// its own, and taken back as soon as one appears, a moment before the notch would have made it a bubble. Priority alone cannot do that:
/// there is no priority below `.low`, and among activities of one priority the one that came first keeps the notch, which would be the
/// pets, ahead of the to-do count, an agent at work or the performance strip. The module is given the activity center to look at, and
/// the app wires it in (`ModuleList.make(activities:)`). It is not published at all while no connected screen has a pet to show, and it is
/// shown on the screens that have one only: a screen the user set to none has a notch as if the module were off.
///
/// The module has no tab, and the pets cost nothing while they are not seen: see `CatStage`. Each screen has a stage of its own
/// (`CatStages`) and the pets the user chose for it (`PetScreens`).
public final class PetModule: FeatureModule {
    public let descriptor = ModuleDescriptor(
        id: "pet",
        displayName: "Thú cưng",
        systemImage: "pawprint",
        defaultEnabled: true,
        order: 960
    )

    static let activityID = "cat"
    /// How long the notch has to be free of every other activity before the cat comes out: a pause between songs is not a free notch, and
    /// the activities published as the app launches get there first.
    static let settleDelay: Duration = .milliseconds(1500)

    private let activities: ActivityCenter
    private let makeStages: (any Scheduler) -> CatStages
    private let displays: Displays
    private var screenObserver: (any NSObjectProtocol)?
    private var context: ModuleContext?
    private var stages: CatStages?
    private var pendingShow: ScheduledAction?
    private var isPublished = false
    /// Where the cat was put to play when it was published, so that a change of the setting puts it somewhere else.
    private var publishedPlace: PlayPlace?
    /// The screens it was published for, so that a change of a screen's choice puts it on the screens that have a pet now.
    private var publishedScreens: DisplayScope?

    public convenience init(activities: ActivityCenter) {
        self.init(activities: activities, makeStages: { CatStages(scheduler: $0) })
    }

    init(activities: ActivityCenter, makeStages: @escaping (any Scheduler) -> CatStages, displays: Displays = .system) {
        self.activities = activities
        self.makeStages = makeStages
        self.displays = displays
    }

    /// Whether the cat's activity is on the notch's list (for tests).
    var isShowing: Bool { isPublished }

    /// Whether another module has an activity right now.
    private var othersAreLive: Bool {
        activities.entries.contains { $0.module != descriptor.id }
    }

    /// Whether some screen that is connected has a pet to show: with none, an activity would only make the notch wider for nothing.
    private var someScreenHasAPet: Bool {
        guard let context else { return true }
        let screens = context.settings.value(PetSettingsKeys(context.settings).screens)
        let connected = displays.current()
        return connected.isEmpty || connected.contains { !screens.kinds(for: $0.id).isEmpty }
    }

    public func start(_ context: ModuleContext) async throws(ModuleError) {
        self.context = context
        stages = makeStages(context.scheduler)
        applySettings()
        let settings = context.settings
        let keys = PetSettingsKeys(settings)
        let center = activities
        let id = descriptor.id
        context.run { [weak self] in
            for await _ in Observations({
                (
                    settings.value(keys.show), settings.value(keys.coat), settings.value(keys.meow), settings.value(keys.sleepMinutes),
                    settings.value(keys.busyReaction), settings.value(keys.playPlace), settings.value(keys.screens)
                )
            }) {
                self?.applySettings()
                self?.reconcile()
            }
        }
        context.run { [weak self] in
            for await _ in Observations({ center.entries.contains { $0.module != id } }) {
                self?.reconcile()
            }
        }
        // A screen that is plugged in or taken out is one that may have a pet to show, or none.
        screenObserver = displays.notifications.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        }
        reconcile()
    }

    public func stop() async {
        screenObserver.map(displays.notifications.removeObserver)
        screenObserver = nil
        pendingShow?.cancel()
        pendingShow = nil
        stages?.shutDown()
        stages = nil
        context = nil
        isPublished = false
        publishedPlace = nil
        publishedScreens = nil
    }

    public func makeTab() -> NotchTab? { nil }

    public func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? {
        AnyView(PetSettingsView(
            keys: PetSettingsKeys(environment.settings), settings: environment.settings, displays: displays
        ))
    }

    // MARK: Settings

    private func applySettings() {
        guard let context, let stages else { return }
        let keys = PetSettingsKeys(context.settings)
        // What the user chose is for every pet there is, on every screen, and the screens' own choices are for the screens.
        stages.tuning = keys.tuning(context.settings)
        stages.coat = context.settings.value(keys.coat)
        stages.playsMeow = context.settings.value(keys.meow)
        stages.apply(screens: context.settings.value(keys.screens))
    }

    private func place(in context: ModuleContext) -> PlayPlace {
        context.settings.value(PetSettingsKeys(context.settings).playPlace)
    }

    /// The screens the activity is for: those that have a pet. A screen set to none shows as if the module had no activity.
    private func screens(in context: ModuleContext) -> DisplayScope {
        context.settings.value(PetSettingsKeys(context.settings).screens).activityScope
    }

    private func activity(stages: CatStages, in context: ModuleContext) -> LiveActivity {
        CatActivity.make(stages: stages, place: place(in: context), screens: screens(in: context))
    }

    // MARK: On the notch or off it

    /// Puts the cat on the notch when it is wanted and the notch is free, takes it off at once when it is not, and waits `settleDelay`
    /// before putting it back. Idempotent: it looks at what is, not at what changed.
    private func reconcile() {
        guard let context else { return }
        let wanted = context.settings.value(PetSettingsKeys(context.settings).show) && !othersAreLive && someScreenHasAPet
        guard wanted else {
            pendingShow?.cancel()
            pendingShow = nil
            if isPublished {
                context.activities.clear(id: Self.activityID)
                isPublished = false
                publishedPlace = nil
                publishedScreens = nil
            }
            return
        }
        // Where the cat plays and which screens have a pet are the user's to change while it is on the notch: it is put again, in its new
        // place and on the screens that have one now, at once.
        if isPublished, let stages, publishedPlace != place(in: context) || publishedScreens != screens(in: context) {
            context.activities.set(activity(stages: stages, in: context))
            publishedPlace = place(in: context)
            publishedScreens = screens(in: context)
        }
        guard !isPublished, pendingShow == nil else { return }
        pendingShow = context.scheduler.schedule(after: Self.settleDelay) { [weak self] in
            self?.pendingShow = nil
            self?.publishIfFree()
        }
    }

    private func publishIfFree() {
        guard let context, let stages, !isPublished, !othersAreLive, someScreenHasAPet,
              context.settings.value(PetSettingsKeys(context.settings).show) else { return }
        context.activities.set(activity(stages: stages, in: context))
        isPublished = true
        publishedPlace = place(in: context)
        publishedScreens = screens(in: context)
    }
}
