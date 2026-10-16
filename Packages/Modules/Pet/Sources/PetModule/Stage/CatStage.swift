import AppKit
import MyNotchCore
import NotchUI

/// Where the cat lives: the views of it on the notches that show it, the brain that decides what it does, and the few things it reads
/// from the Mac to decide. The cat is alive only while some view of it can be seen, which is to say that when the last view leaves its
/// window the timer, the reads and the animations all stop, and nothing is left running for a cat nobody is looking at.
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
        /// Whether the screen a window is on has a camera in it. Reads the screen's own numbers, which is all geometry needs to tell.
        var notchKind: (NSWindow) -> NotchKind = { CatStage.kind(of: $0) }
        var seed: UInt64 = .random(in: .min ... .max)
    }

    /// Between two wakings: the pointer is read at every one, the rest at every `slowEvery`-th.
    static let tick: Duration = .milliseconds(250)
    static let slowEvery = 4

    /// What the user chose.
    var tuning = CatTuning()
    var bothWings = false {
        didSet { if bothWings != oldValue { hostsDidMove() } }
    }
    var playsMeow = false

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
    /// What kind of notch each window has, asked of the screen once and not at every waking; asked again when a view moves.
    private var kinds: [ObjectIdentifier: NotchKind] = [:]

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

    var attachedHosts: [CatSpriteView] { hosts }

    // MARK: Views

    func attach(_ host: CatSpriteView) {
        guard !isShutDown, !hosts.contains(where: { $0 === host }) else { return }
        hosts.append(host)
        frames[ObjectIdentifier(host)] = host.windowFrame
        if hosts.count == 1 {
            wake()
        } else {
            // A second view is a wing the first one did not know about: where the cat may go changes for both.
            hostsDidMove()
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
        kinds.removeAll()
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
        let blind = referenceLane()?.blind
        if brain == nil {
            brain = CatBrain(seed: sources.seed, now: now)
        }
        brain?.resume(now: now, blind: blind)
        if isResting {
            hosts.forEach(showResting(on:))
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
        let pointerNear = PointerProximity.isNear(sources.pointer.location(), to: notchFrames())
        if tickIndex % Self.slowEvery == 0 { readSlowSenses() }
        tickIndex += 1
        let senses = CatSenses(
            idleSeconds: idle, cpuLoad: load, pointerNear: pointerNear, audioPlaying: audioPlaying, hour: sources.hour()
        )
        let lane = referenceLane()
        let outcome = brain.update(now: now, senses: senses, tuning: tuning, travel: Double(lane?.travel ?? 0), blind: lane?.blind)
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

    // MARK: Showing

    private func show(on host: CatSpriteView) {
        guard let brain, let lane = lane(for: host) else {
            host.stopShowing()
            return
        }
        presentations += 1
        host.show(plan: brain.plan, lane: lane, elapsed: max(sources.clock() - brain.plan.began, 0))
    }

    private func showResting(on host: CatSpriteView) {
        guard let lane = lane(for: host) else {
            host.stopShowing()
            return
        }
        presentations += 1
        host.showResting(lane: lane)
    }

    private func hostsDidMove() {
        guard isAlive else { return }
        refreshFrames()
        for host in hosts {
            if isResting { showResting(on: host) } else { show(on: host) }
        }
    }

    private func refreshFrames() {
        frames = Dictionary(uniqueKeysWithValues: hosts.map { (ObjectIdentifier($0), $0.windowFrame) })
        kinds.removeAll()
    }

    private func kind(in window: NSWindow) -> NotchKind {
        let key = ObjectIdentifier(window)
        if let known = kinds[key] { return known }
        let kind = sources.notchKind(window)
        kinds[key] = kind
        return kind
    }

    private func framesChanged() -> Bool {
        hosts.contains { frames[ObjectIdentifier($0)] != $0.windowFrame }
    }

    /// Where the notches are on the screen, one frame each: the views of a window together, so that the camera between two wings is
    /// part of the notch, and the pointer over it is on the notch.
    private func notchFrames() -> [CGRect] {
        var frames: [ObjectIdentifier: CGRect] = [:]
        for host in hosts {
            guard let window = host.window, let frame = host.screenFrame else { continue }
            let key = ObjectIdentifier(window)
            frames[key] = frames[key].map { $0.union(frame) } ?? frame
        }
        return Array(frames.values)
    }

    // MARK: Lanes

    /// The lane of the first view, which is the one the cat's timings are worked out for: on another display with a lane of another length
    /// it covers the same share of it in the same time.
    private func referenceLane() -> WalkLane? {
        hosts.first.flatMap { lane(for: $0) }
    }

    /// The lane of the notch `host` is in, made from the views of the cat it has.
    func lane(for host: CatSpriteView) -> WalkLane? {
        guard let window = host.window else { return nil }
        let mates = hosts.filter { $0.window === window }
        let wings = Wings(
            leading: mates.first { $0.role == .leading }?.windowFrame, trailing: mates.first { $0.role == .trailing }?.windowFrame
        )
        let metrics = (mates.first { $0.role == .trailing } ?? host).metrics
        let notch = kind(in: window)
        let roundEnd = notch == .virtual ? host.bounds.height / 2 : WalkLane.hardwareEndInset
        return WalkLane.make(
            mode: LaneMode.resolve(kind: notch, bothWings: bothWings), wings: wings, spriteWidth: metrics.size.width, roundEnd: roundEnd
        )
    }

    /// Whether the screen a window is on has a camera in it, by the same numbers the notch itself goes by.
    static func kind(of window: NSWindow) -> NotchKind {
        guard let screen = window.screen ?? NSScreen.main else { return .virtual }
        return NotchGeometry(screen: ScreenDescriptor(screen), config: NotchLayoutConfig()).kind
    }

    // MARK: Petting

    /// The cat was clicked: it purrs, and mews if the user wants it to. A cat that does not move purrs without moving, and still mews.
    func catWasClicked() {
        strokes += 1
        if var brain, !isResting {
            if brain.pet(now: sources.clock()) == .changed {
                self.brain = brain
                hosts.forEach(show(on:))
            } else {
                self.brain = brain
            }
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
            hosts.forEach(showResting(on:))
        } else {
            brain?.resume(now: sources.clock(), blind: referenceLane()?.blind)
            _ = sources.cpu.load()
            load = 0
            hasLoad = false
            tickIndex = 0
            hosts.forEach(show(on:))
            scheduleTick()
        }
    }
}
