import AppKit
import MyNotchCore
import NotchUI

/// Where the cat lives: the views of the strip under the notches that show it, the brain that decides what it does, and the few things it
/// reads from the Mac to decide. The cat is alive only while some view of it can be seen, which is to say that when the last view leaves
/// its window the timer, the reads and the animations all stop, and nothing is left running for a cat nobody is looking at.
///
/// While it is alive it wakes a few times a second, and only to read: the pointer four times a second, the processors, the idle time and
/// the sound once a second. What it draws it hands to Core Animation, which plays it on its own.
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
    private var audioPlaying = false
    private var frames: [ObjectIdentifier: CGRect] = [:]

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
        if hosts.count == 1 {
            wake()
        } else if isResting {
            host.showResting(coat: coat)
        } else {
            show(on: host)
        }
    }

    func detach(_ host: CatSpriteView) {
        guard let index = hosts.firstIndex(where: { $0 === host }) else { return }
        hosts.remove(at: index)
        frames[ObjectIdentifier(host)] = nil
        host.stopShowing()
        if hosts.isEmpty { doze() }
    }

    /// The module stopped: nothing runs and no view is taken on again.
    func shutDown() {
        isShutDown = true
        hosts.forEach { $0.stopShowing() }
        hosts.removeAll()
        frames.removeAll()
        doze()
    }

    /// A view moved or changed size: the cat's lane is not where it was.
    func hostDidMove(_ host: CatSpriteView) {
        guard hosts.contains(where: { $0 === host }), frames[ObjectIdentifier(host)] != host.windowFrame else { return }
        hostsDidMove()
    }

    // MARK: Life

    /// The first view appeared: the cat starts to live.
    private func wake() {
        let now = sources.clock()
        isResting = sources.reducesMotion()
        observeMotionPreference()
        refreshFrames()
        if brain == nil { brain = CatBrain(seed: sources.seed, now: now) }
        brain?.resume(now: now)
        if isResting {
            hosts.forEach { $0.showResting(coat: coat) }
            return
        }
        // A baseline for the load, which is what the processors did since the last read: not the whole time the cat was away.
        _ = sources.cpu.load()
        load = 0
        hasLoad = false
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
        if tickIndex % Self.slowEvery == 0 { readSlowSenses() }
        tickIndex += 1
        let senses = CatSenses(
            idleSeconds: idle, cpuLoad: load, pointer: pointerReading(), audioPlaying: audioPlaying, hour: sources.hour()
        )
        let outcome = brain.update(now: now, senses: senses, tuning: tuning, travel: Double(referenceLane()?.travel ?? 0))
        self.brain = brain
        // The notch can move under the cat (a wider pill, another display) without telling it.
        let moved = framesChanged()
        if moved { refreshFrames() }
        if outcome == .changed || moved { hosts.forEach(show(on:)) }
        scheduleTick()
    }

    /// The things that change slowly, read once a second.
    private func readSlowSenses() {
        idle = sources.idle.secondsSinceLastInput()
        if let sample = sources.cpu.load() {
            // Half of the last second and half of what came before, so a spike makes the cat run and a blip does not.
            load = hasLoad ? load * 0.5 + sample * 0.5 : sample
            hasLoad = true
        }
        audioPlaying = sources.audio.isPlaying()
    }

    /// The pointer as the cat sees it from the strip it is nearest to, nil when no strip can see it.
    private func pointerReading() -> PointerReading? {
        let point = sources.pointer.location()
        var nearest: (distance: CGFloat, reading: PointerReading)?
        for host in hosts {
            guard let strip = host.screenFrame else { continue }
            let lane = host.lane
            guard let reading = PointerLook.reading(of: point, strip: strip, lane: lane, spriteWidth: CatSpriteView.spriteSize.width) else { continue }
            let distance = hypot(max(strip.minX - point.x, point.x - strip.maxX, 0), max(strip.minY - point.y, point.y - strip.maxY, 0))
            if nearest == nil || distance < nearest!.distance { nearest = (distance, reading) }
        }
        return nearest?.reading
    }

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
        for host in hosts {
            if isResting { host.showResting(coat: coat) } else { show(on: host) }
        }
    }

    private func refreshFrames() {
        frames = Dictionary(uniqueKeysWithValues: hosts.map { (ObjectIdentifier($0), $0.windowFrame) })
    }

    private func framesChanged() -> Bool {
        hosts.contains { frames[ObjectIdentifier($0)] != $0.windowFrame }
    }

    /// The lane of the first view, which is the one the cat's timings are worked out for: on another display with a lane of another length
    /// it covers the same share of it in the same time.
    private func referenceLane() -> WalkLane? { hosts.first?.lane }

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
            tickIndex = 0
            hosts.forEach(show(on:))
            scheduleTick()
        }
    }
}
