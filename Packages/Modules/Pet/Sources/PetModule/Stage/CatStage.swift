import AppKit
import MyNotchCore
import NotchUI

/// Where the cat lives: the views of the strip under the notches that show it, the brain that decides what it does, and the few things it
/// reads from the Mac to decide. The cat is alive only while some view of it can be seen, which is to say that when the last view leaves
/// its window the timer, the reads and the animations all stop, and nothing is left running for a cat nobody is looking at.
///
/// While it is alive it wakes a few times a second, and only to read: the pointer four times a second, the processors, the idle time and
/// the sound once a second. What the processors do is judged against what this Mac usually does (`BusyWatch`): the cat runs for its life only
/// when the Mac is much busier than it usually is, and then only now and then. What it draws it hands to Core Animation, which plays it on its own.
final class CatStage {
    /// What the stage reads and calls, all of it replaceable so that a test touches none of the real things.
    struct Sources {
        var idle: any IdleTimeSource = SystemIdleTime()
        var cpu: any CPULoadSource = HostCPULoad()
        var pointer: any PointerSource = SystemPointer()
        var audio: any AudioPlaybackSource = AudioOutputProbe()
        var meow: any MeowPlayer = SynthMeow()
        var hour: () -> Int = { Calendar.current.component(.hour, from: Date()) }
        var reducesMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        /// Where the stage hears that the user changed the Reduce Motion setting.
        var notifications: NotificationCenter = NSWorkspace.shared.notificationCenter
        /// Seconds on a clock that only goes forward.
        var clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
        var seed: UInt64 = .random(in: .min ... .max)
    }

    /// Between two wakings: the pointer is read at every one, the rest at every `slowEvery`-th.
    static let tick: Duration = .milliseconds(250)
    static let slowEvery = 4
    /// The least time between one pounce or startle and the next with the cat in the menu bar's row, where the pointer is all the time.
    static let bandReactionCooldown: TimeInterval = 20

    /// What the user chose.
    var tuning = CatTuning()
    var playsMeow = false
    var coat = CatCoat.tabby {
        didSet { if coat != oldValue { hostsDidMove() } }
    }

    private let scheduler: any Scheduler
    private var sources: Sources
    private var hosts: [CatSpriteView] = []
    private var brain: CatBrain?
    private var nextTick: ScheduledAction?
    private var motionObserver: (any NSObjectProtocol)?
    private var isShutDown = false
    private var isResting = false
    private var tickIndex = 0
    private var idle: TimeInterval = 0
    private var load: Double = 0
    private var hasLoad = false
    private var busy = BusyWatch()
    private var audioPlaying = false
    private var frames: [ObjectIdentifier: CGRect] = [:]
    private var fields: [ObjectIdentifier: CatField] = [:]
    private var dwell = PointerDwell()

    /// Counters for tests, never read by anything else.
    private(set) var ticks = 0
    private(set) var presentations = 0
    private(set) var strokes = 0

    init(scheduler: any Scheduler, sources: Sources = Sources()) {
        self.scheduler = scheduler
        self.sources = sources
    }

    isolated deinit {
        nextTick?.cancel()
        motionObserver.map(sources.notifications.removeObserver)
    }

    /// Whether a view of the cat is on a notch someone can see.
    var isAlive: Bool { !hosts.isEmpty }

    /// Whether the stage is waking up to read and move the cat. A cat that is resting (Reduce Motion) wakes for nothing.
    var isTicking: Bool { nextTick != nil }

    /// The picture the cat is in now, for tests.
    var plan: CatPlan? { brain?.plan }

    var scene: CatScene? { brain?.scene }

    var attachedHosts: [CatSpriteView] { hosts }

    // MARK: Views

    func attach(_ host: CatSpriteView) {
        guard !isShutDown, !hosts.contains(where: { $0 === host }) else { return }
        hosts.append(host)
        frames[ObjectIdentifier(host)] = host.windowFrame
        fields[ObjectIdentifier(host)] = host.field
        if hosts.count == 1 {
            wake()
        } else if isResting {
            host.showResting(coat: coat)
        } else if host.role.isStrip {
            show(on: host)
        } else {
            // A view that is one of two changes the field of the other: both are shown it again.
            hostsDidMove()
        }
    }

    func detach(_ host: CatSpriteView) {
        guard let index = hosts.firstIndex(where: { $0 === host }) else { return }
        hosts.remove(at: index)
        frames[ObjectIdentifier(host)] = nil
        fields[ObjectIdentifier(host)] = nil
        host.stopShowing()
        if hosts.isEmpty { doze() }
    }

    /// The module stopped: nothing runs and no view is taken on again.
    func shutDown() {
        isShutDown = true
        hosts.forEach { $0.stopShowing() }
        hosts.removeAll()
        frames.removeAll()
        fields.removeAll()
        doze()
    }

    /// A view moved or changed size: the cat's lane is not where it was.
    func hostDidMove(_ host: CatSpriteView) {
        guard hosts.contains(where: { $0 === host }), moved(host) else { return }
        hostsDidMove()
    }

    /// Whether the view's place in the cat's world is not what the stage last arranged: its frame for a strip, which is its place on the
    /// screen and is not the whole of the lane, and its field for a view across a notch's top row, whose lane is all the stage goes by (the
    /// notch moving about the screen changes none of it).
    private func moved(_ host: CatSpriteView) -> Bool {
        host.role.isStrip ? frames[ObjectIdentifier(host)] != host.windowFrame : fields[ObjectIdentifier(host)] != host.field
    }

    // MARK: Life

    /// The first view appeared: the cat starts to live.
    private func wake() {
        let now = sources.clock()
        isResting = sources.reducesMotion()
        observeMotionPreference()
        refreshFrames()
        if brain == nil { brain = CatBrain(seed: sources.seed, now: now) }
        brain?.settle(gaps: crossingShares())
        brain?.resume(now: now)
        dwell.reset()
        if isResting {
            hosts.forEach { $0.showResting(coat: coat) }
            return
        }
        // A baseline for the load, which is what the processors did since the last read: not the whole time the cat was away.
        _ = sources.cpu.load()
        load = 0
        hasLoad = false
        busy.resume()
        tickIndex = 0
        hosts.forEach(show(on:))
        scheduleTick()
    }

    /// The last view went: nothing of the cat's runs.
    private func doze() {
        nextTick?.cancel()
        nextTick = nil
        motionObserver.map(sources.notifications.removeObserver)
        motionObserver = nil
        isResting = false
    }

    private func scheduleTick() {
        nextTick?.cancel()
        nextTick = scheduler.schedule(after: Self.tick) { [weak self] in self?.tickFired() }
    }

    private func tickFired() {
        nextTick = nil
        guard isAlive, !isResting, var brain else { return }
        ticks += 1
        let now = sources.clock()
        if tickIndex % Self.slowEvery == 0 { readSlowSenses(at: now) }
        tickIndex += 1
        let senses = CatSenses(
            idleSeconds: idle, cpuLoad: load, busyBurst: busy.isBursting(at: now), pointer: pointerReading(), audioPlaying: audioPlaying,
            hour: sources.hour()
        )
        let field = referenceField()
        // In the menu bar's row the pointer is all the time on its way somewhere: it startles the cat less often.
        var effective = tuning
        if inBand { effective.reactionCooldown = max(effective.reactionCooldown, Self.bandReactionCooldown) }
        // The brain thinks in pixels of the cat's picture, so a bigger cat takes bigger steps in the time of the same ones.
        let outcome = brain.update(
            now: now, senses: senses, tuning: effective, travel: Double(field?.lane.travel ?? 0) / Double(field?.scale ?? 1),
            gaps: crossingShares()
        )
        self.brain = brain
        // The notch can move under the cat (a wider pill, another display) without telling it.
        let moved = framesChanged()
        if moved { refreshFrames() }
        if outcome == .changed || moved { hosts.forEach(show(on:)) }
        scheduleTick()
    }

    /// The things that change slowly, read once a second.
    private func readSlowSenses(at now: TimeInterval) {
        idle = sources.idle.secondsSinceLastInput()
        if let sample = sources.cpu.load() {
            // Half of the last second and half of what came before, so that a blip is not a load.
            load = hasLoad ? load * 0.5 + sample * 0.5 : sample
            hasLoad = true
            busy.record(load, at: now)
        }
        audioPlaying = sources.audio.isPlaying()
    }

    /// The pointer as the cat sees it from the strip it is nearest to, nil when no strip can see it. In the menu bar's row the pointer is
    /// near only a little way from the cat, and only once it has stopped there.
    private func pointerReading() -> PointerReading? {
        let point = sources.pointer.location()
        var nearest: (distance: CGFloat, reading: PointerReading)?
        for host in hosts {
            guard let strip = host.screenFrame else { continue }
            let field = host.field
            guard let reading = PointerLook.reading(
                of: point, strip: strip, lane: field.lane, spriteWidth: field.spriteWidth, origin: field.origin,
                nearMargin: host.role.isStrip ? PointerLook.nearMargin : PointerLook.bandNearMargin
            ) else { continue }
            let distance = hypot(max(strip.minX - point.x, point.x - strip.maxX, 0), max(strip.minY - point.y, point.y - strip.maxY, 0))
            if nearest == nil || distance < nearest!.distance { nearest = (distance, reading) }
        }
        guard var reading = nearest?.reading else {
            dwell.reset()
            return nil
        }
        if inBand {
            let settled = dwell.isSettled(near: reading.isNear, at: point, now: sources.clock())
            reading = PointerReading(share: reading.share, isNear: settled, isInRange: reading.isInRange, isAbove: reading.isAbove)
        }
        return reading
    }

    /// Whether the cat is in the menu bar's row, where the pointer is all the time, and not in a strip under the notch.
    private var inBand: Bool { hosts.contains { !$0.role.isStrip } }

    // MARK: Showing

    private func show(on host: CatSpriteView) {
        guard let brain else {
            host.stopShowing()
            return
        }
        presentations += 1
        host.show(plan: brain.plan, elapsed: max(sources.clock() - brain.plan.began, 0), coat: coat)
    }

    private func hostsDidMove() {
        guard isAlive else { return }
        refreshFrames()
        // The views the cat plays in are not what they were: where it must not stop is not either.
        brain?.settle(gaps: crossingShares())
        for host in hosts {
            if isResting { host.showResting(coat: coat) } else { show(on: host) }
        }
    }

    private func refreshFrames() {
        frames = Dictionary(uniqueKeysWithValues: hosts.map { (ObjectIdentifier($0), $0.windowFrame) })
        fields = Dictionary(uniqueKeysWithValues: hosts.map { (ObjectIdentifier($0), $0.field) })
    }

    private func framesChanged() -> Bool {
        hosts.contains { moved($0) }
    }

    /// The field of the first view, which is the one the cat's timings are worked out for: on another display with a lane of another length
    /// it covers the same share of it in the same time.
    private func referenceField() -> CatField? { hosts.first?.field }

    /// Where the cat must not stop, as shares of the lane: the crossing of every view, which are the same share of each (the same field of
    /// the two views of a notch) or near enough on another display.
    private func crossingShares() -> [ClosedRange<Double>] {
        var shares: [ClosedRange<Double>] = []
        for host in hosts {
            guard let share = host.field.crossingShares, !shares.contains(share) else { continue }
            shares.append(share)
        }
        return shares
    }

    // MARK: Petting

    /// The cat was clicked: it purrs, and mews if the user wants it to. A cat that does not move purrs without moving, and still mews.
    func catWasClicked() {
        strokes += 1
        if var brain, !isResting {
            let outcome = brain.pet(now: sources.clock())
            self.brain = brain
            if outcome == .changed { hosts.forEach(show(on:)) }
        }
        if playsMeow { sources.meow.play() }
    }

    // MARK: Reduce Motion

    private func observeMotionPreference() {
        guard motionObserver == nil else { return }
        motionObserver = sources.notifications.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.motionPreferenceChanged() }
        }
    }

    private func motionPreferenceChanged() {
        guard isAlive else { return }
        let reduces = sources.reducesMotion()
        guard reduces != isResting else { return }
        isResting = reduces
        if reduces {
            nextTick?.cancel()
            nextTick = nil
            hosts.forEach { $0.showResting(coat: coat) }
        } else {
            brain?.resume(now: sources.clock())
            _ = sources.cpu.load()
            load = 0
            hasLoad = false
            busy.resume()
            tickIndex = 0
            hosts.forEach(show(on:))
            scheduleTick()
        }
    }
}
