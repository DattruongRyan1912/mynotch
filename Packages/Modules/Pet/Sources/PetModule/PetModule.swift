import AppKit
import MyNotchCore
import Observation
import SwiftUI

/// A pixel cat that lives on a strip under the collapsed notch when nothing else is going on.
///
/// It is a live activity at the lowest priority, with one rule on top: it is published only while no other module has an activity of
/// its own, and taken back as soon as one appears, a moment before the notch would have made it a bubble. Priority alone cannot do that:
/// there is no priority below `.low`, and among activities of one priority the one that came first keeps the notch, which would be the
/// cat, ahead of the to-do count, an agent at work or the performance strip. The module is given the activity center to look at, and
/// the app wires it in (`ModuleList.make(activities:)`).
///
/// The module has no tab, and the cat costs nothing while it is not seen: see `CatStage`.
public final class PetModule: FeatureModule {
    public let descriptor = ModuleDescriptor(
        id: "pet",
        displayName: "Mèo",
        systemImage: "cat",
        defaultEnabled: true,
        order: 960
    )

    static let activityID = "cat"
    /// How long the notch has to be free of every other activity before the cat comes out: a pause between songs is not a free notch, and
    /// the activities published as the app launches get there first.
    static let settleDelay: Duration = .milliseconds(1500)

    private let activities: ActivityCenter
    private let makeStage: (any Scheduler) -> CatStage
    private var context: ModuleContext?
    private var stage: CatStage?
    private var pendingShow: ScheduledAction?
    private var isPublished = false

    public convenience init(activities: ActivityCenter) {
        self.init(activities: activities, makeStage: { CatStage(scheduler: $0) })
    }

    init(activities: ActivityCenter, makeStage: @escaping (any Scheduler) -> CatStage) {
        self.activities = activities
        self.makeStage = makeStage
    }

    /// Whether the cat's activity is on the notch's list (for tests).
    var isShowing: Bool { isPublished }

    /// Whether another module has an activity right now.
    private var othersAreLive: Bool {
        activities.entries.contains { $0.module != descriptor.id }
    }

    public func start(_ context: ModuleContext) async throws(ModuleError) {
        self.context = context
        stage = makeStage(context.scheduler)
        applySettings()
        let settings = context.settings
        let keys = PetSettingsKeys(settings)
        let center = activities
        let id = descriptor.id
        context.run { [weak self] in
            for await _ in Observations({
                (
                    settings.value(keys.show), settings.value(keys.coat), settings.value(keys.meow), settings.value(keys.sleepMinutes),
                    settings.value(keys.busyReaction)
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
        reconcile()
    }

    public func stop() async {
        pendingShow?.cancel()
        pendingShow = nil
        stage?.shutDown()
        stage = nil
        context = nil
        isPublished = false
    }

    public func makeTab() -> NotchTab? { nil }

    public func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? {
        AnyView(PetSettingsView(
            keys: PetSettingsKeys(environment.settings), settings: environment.settings
        ))
    }

    // MARK: Settings

    private func applySettings() {
        guard let context, let stage else { return }
        let keys = PetSettingsKeys(context.settings)
        stage.tuning = keys.tuning(context.settings)
        stage.coat = context.settings.value(keys.coat)
        stage.playsMeow = context.settings.value(keys.meow)
    }

    // MARK: On the notch or off it

    /// Puts the cat on the notch when it is wanted and the notch is free, takes it off at once when it is not, and waits `settleDelay`
    /// before putting it back. Idempotent: it looks at what is, not at what changed.
    private func reconcile() {
        guard let context else { return }
        let wanted = context.settings.value(PetSettingsKeys(context.settings).show) && !othersAreLive
        guard wanted else {
            pendingShow?.cancel()
            pendingShow = nil
            if isPublished {
                context.activities.clear(id: Self.activityID)
                isPublished = false
            }
            return
        }
        guard !isPublished, pendingShow == nil else { return }
        pendingShow = context.scheduler.schedule(after: Self.settleDelay) { [weak self] in
            self?.pendingShow = nil
            self?.publishIfFree()
        }
    }

    private func publishIfFree() {
        guard let context, let stage, !isPublished, !othersAreLive,
              context.settings.value(PetSettingsKeys(context.settings).show) else { return }
        context.activities.set(CatActivity.make(stage: stage))
        isPublished = true
    }
}
