import AppKit
import MyNotchCore
import NotchUI

/// Where the characters live: the views of the notches that show them, a brain for each that decides what it does, and the few things they
/// read from the Mac to decide. There is one for each display that has characters (`CatStages`), so what is of a screen is of its stage: the
/// pointer that is near, the cooldown of its reactions, the places a character must not stop, a click.
///
/// The characters are alive only while some view of them can be seen, which is to say that when the last view leaves its window the timer,
/// the reads and the animations all stop, and nothing is left running for a character nobody is looking at. They share one lane and one
/// clock: each has a brain of its own and is told, at every tick, where the others stand and whether one is in the camera's crossing
/// (`LaneRules`), so that they walk past each other and never stop on each other, and one at a time goes through the portal.
///
/// While it is alive it wakes a few times a second, and only to read: the pointer four times a second, the processors, the idle time and
/// the sound once a second. What the processors do is judged against what this Mac usually does (`BusyWatch`): a character runs for its life
/// only when the Mac is much busier than it usually is, and then only now and then. What it draws it hands to Core Animation, which plays
/// it on its own.
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
        /// Which species a kind of character is: the real one, unless a test puts another in.
        var species: (CharacterKind) -> any Species = { $0.species }
    }

    /// A character on the stage: who, and what decides what it does, made when the stage wakes.
    private struct Slot {
        var kind: CharacterKind
        var species: any Species
        var brain: (any CharacterBrain)?
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
    private var slots: [Slot] = []
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
    /// Which two characters are playing together, if any, and when the next scene may begin (`JointDirector`).
    private var joint: JointDirector

    /// Counters for tests, never read by anything else.
    private(set) var ticks = 0
    private(set) var presentations = 0
    private(set) var strokes = 0

    init(scheduler: any Scheduler, sources: Sources = Sources(), characters: [CharacterKind] = [.cat]) {
        self.scheduler = scheduler
        self.sources = sources
        // Its own stream, so that what it decides never changes what a character does by itself.
        joint = JointDirector(seed: sources.seed ^ 0x6A09_E667_F3BC_C909)
        self.characters = characters
    }

    isolated deinit {
        nextTick?.cancel()
        motionObserver.map(sources.notifications.removeObserver)
    }

    /// Whether a view of the cat is on a notch someone can see.
    var isAlive: Bool { !hosts.isEmpty }

    /// Whether the stage is waking up to read and move the cat. A cat that is resting (Reduce Motion) wakes for nothing.
    var isTicking: Bool { nextTick != nil }

    /// Who is on the stage, in the order they are drawn in (the first at the bottom), at most `CharacterKind.maxPerScreen`. A change
    /// takes effect at once: a character that stays keeps its brain, one that comes is made, one that goes is gone.
    var characters: [CharacterKind] {
        get { slots.map(\.kind) }
        set { setCharacters(newValue) }
    }

    /// The picture the first cat is in now, for tests.
    var plan: CatPlan? { (slots.first?.brain as? CatBrain)?.plan }

    var scene: CatScene? { (slots.first?.brain as? CatBrain)?.scene }

    /// What every character is doing now, in the order they are drawn in.
    var poses: [Pose] { slots.compactMap { $0.brain?.pose } }

    var attachedHosts: [CatSpriteView] { hosts }

    /// The joint scene the characters are in, if any, and how many have been begun: for tests.
    var jointPlay: JointDirector.Play? { joint.play }
    var jointScenesBegun: Int { joint.begun }

    // MARK: Views

    func attach(_ host: CatSpriteView) {
        guard !isShutDown, !hosts.contains(where: { $0 === host }) else { return }
        hosts.append(host)
        frames[ObjectIdentifier(host)] = host.windowFrame
        fields[ObjectIdentifier(host)] = host.field
        if hosts.count == 1 {
            wake()
        } else if isResting {
            showResting(on: host)
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
        joint.reset()
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
        makeBrains(now: now)
        // The characters are not where they were, or in a scene: each sits down where it is, and the next scene is a few minutes away.
        joint.reset()
        for index in slots.indices {
            let lane = laneContext(for: index, now: now)
            slots[index].brain?.settle(lane: lane)
            slots[index].brain?.resume(now: now)
        }
        dwell.reset()
        if isResting {
            hosts.forEach(showResting(on:))
            return
        }
        guard !slots.isEmpty else { return }
        // A baseline for the load, which is what the processors did since the last read: not the whole time the cat was away.
        _ = sources.cpu.load()
        load = 0
        hasLoad = false
        busy.resume()
        tickIndex = 0
        showAll()
        scheduleTick()
    }

    /// The last view went: nothing of the cat's runs.
    private func doze() {
        joint.reset()
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
        guard isAlive, !isResting, !slots.isEmpty else { return }
        ticks += 1
        let now = sources.clock()
        if tickIndex % Self.slowEvery == 0 { readSlowSenses(at: now) }
        tickIndex += 1
        let senses = CatSenses(
            idleSeconds: idle, cpuLoad: load, busyBurst: busy.isBursting(at: now), pointer: pointerReading(), audioPlaying: audioPlaying,
            hour: sources.hour()
        )
        let field = referenceField()
        // In the menu bar's row the pointer is all the time on its way somewhere: it startles a character less often.
        var effective = tuning
        if inBand { effective.reactionCooldown = max(effective.reactionCooldown, Self.bandReactionCooldown) }
        // The brain thinks in pixels of the picture, so a bigger character takes bigger steps in the time of the same ones.
        let travel = Double(field?.lane.travel ?? 0) / Double(field?.scale ?? 1)
        // One at a time, each told where the others stand after the one before it chose: two never pick the same stop, or both the portal.
        var outcome = BrainOutcome.unchanged
        if directJointScene(now: now) { outcome = .changed }
        for index in slots.indices {
            guard slots[index].brain != nil else { continue }
            let lane = laneContext(for: index, now: now)
            if let result = slots[index].brain?.update(now: now, senses: senses, tuning: effective, travel: travel, lane: lane), result == .changed {
                outcome = .changed
            }
        }
        // A scene whose guest has just finished is over for the host now, not a waking later.
        if joint.play != nil, directJointScene(now: now) { outcome = .changed }
        // The notch can move under them (a wider pill, another display) without telling it.
        let moved = lookAtViews()
        if moved { refreshFrames() }
        if outcome == .changed || moved { showAll() }
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

    /// Shows the characters on one view, from `media` (a reading of the animation clock) and `clock` (one of their own).
    private func show(on host: CatSpriteView, media: CFTimeInterval = CACurrentMediaTime(), clock: TimeInterval? = nil) {
        let now = clock ?? sources.clock()
        let drawings = slots.compactMap { slot -> CharacterDrawing? in
            guard let pose = slot.brain?.pose else { return nil }
            return CharacterDrawing(species: slot.species, pose: pose, elapsed: max(now - pose.began, 0), appearance: appearance)
        }
        guard !drawings.isEmpty else {
            host.stopShowing()
            return
        }
        presentations += 1
        host.show(characters: drawings, at: media)
    }

    /// Shows every character on one view sitting still, which is what Reduce Motion asks for.
    private func showResting(on host: CatSpriteView) {
        host.showResting(slots.map(\.species), appearance: appearance)
    }

    /// What the user chose that changes how a character looks.
    private var appearance: Appearance { Appearance(coat: coat) }

    /// Shows the cat on every view, all of them from the same moment: one reading of each clock for them all. That is what keeps the two
    /// views of a notch's top row in step, whatever the machine is doing between one and the next, with the cat going out of one into the
    /// other, and the portals at their edges opening and closing together.
    private func showAll() {
        let (media, clock) = (CACurrentMediaTime(), sources.clock())
        for host in hosts { show(on: host, media: media, clock: clock) }
    }

    private func hostsDidMove() {
        guard isAlive else { return }
        // The lane is not what the scene was made for: the characters in it are not where it needs them, so it is over.
        _ = endJointScene(now: sources.clock())
        refreshFrames()
        // The views they play in are not what they were: where a character must not stop is not either.
        let now = sources.clock()
        for index in slots.indices {
            let lane = laneContext(for: index, now: now)
            slots[index].brain?.settle(lane: lane)
        }
        if isResting { hosts.forEach(showResting(on:)) } else { showAll() }
    }

    private func refreshFrames() {
        frames = Dictionary(uniqueKeysWithValues: hosts.map { (ObjectIdentifier($0), $0.windowFrame) })
        fields = Dictionary(uniqueKeysWithValues: hosts.map { (ObjectIdentifier($0), $0.field) })
    }

    /// The stage's own look at its views, which finds what nothing says. A view that is not where it was arranged is a reason to show the cat
    /// again (the answer), and with one whose container has the wings laid out for a camera that is not where it is now (a window that moved,
    /// or got its screen, in silence) is a reason to lay the container out again: the cat is shown again for that once the layout has moved a
    /// view, which `hostDidMove` sees.
    private func lookAtViews() -> Bool {
        var anyMoved = false
        for host in hosts {
            let hostMoved = moved(host)
            anyMoved = anyMoved || hostMoved
            if hostMoved || host.isInStaleLayout { host.askForLayout() }
        }
        return anyMoved
    }

    /// The field of the first view, which is the one the cat's timings are worked out for: on another display with a lane of another length
    /// it covers the same share of it in the same time.
    private func referenceField() -> CatField? { hosts.first?.field }

    /// Where the cat must not stop, as shares of the lane: the crossing of every view, which are the same share of each (the same field of
    /// the two views of a notch) or near enough on another display. None for the cat of a virtual notch, which has no camera.
    func crossingShares() -> [ClosedRange<Double>] {
        var shares: [ClosedRange<Double>] = []
        for host in hosts {
            guard let share = host.field.crossingShares, !shares.contains(share) else { continue }
            shares.append(share)
        }
        return shares
    }

    /// What character `index` has to keep to in the lane: the crossing, where the others stand, and whether the crossing is closed to it.
    private func laneContext(for index: Int, now: TimeInterval, playing: Set<Int>? = nil) -> LaneContext {
        let crossing = crossingShares()
        guard slots.count > 1 else { return LaneContext(crossing: crossing) }
        var lane = LaneRules.context(
            for: index, poses: slots.map { $0.brain?.pose }, crossing: crossing, separation: referenceField()?.separation ?? 0, now: now,
            exempt: playing ?? joint.exempt
        )
        // A character in a joint scene is told where the other is, and which part it plays.
        if playing == nil, let play = joint.play, index == play.host || index == play.guest {
            let other = index == play.host ? play.guest : play.host
            if slots.indices.contains(other), let partner = slots[other].brain?.pose {
                lane.joint = JointSight(scene: play.scene.id, role: index == play.host ? .host : .guest, partner: partner)
            }
        }
        return lane
    }

    // MARK: Playing together

    /// Begins a joint scene when it is time and two characters are ready, and ends the one there is when it is over. True if that changed
    /// what a character is doing. A stage whose characters cannot play together (one kind of them, or none that make a pair) does not so
    /// much as look.
    private func directJointScene(now: TimeInterval) -> Bool {
        guard slots.count > 1, joint.isPossible(among: slots.map(\.kind)) else { return false }
        var brains = slots.map(\.brain)
        // The director is a copy while it asks for the lanes, which the stage works out from its own.
        var director = joint
        let changed = director.direct(now: now, kinds: slots.map(\.kind), brains: &brains) { index, playing in
            self.laneContext(for: index, now: now, playing: playing)
        }
        joint = director
        for index in slots.indices { slots[index].brain = brains[index] }
        return changed
    }

    /// The scene is over, for whatever reason: both are told. True if that changed what a character is doing.
    private func endJointScene(now: TimeInterval) -> Bool {
        guard joint.play != nil else { return false }
        var brains = slots.map(\.brain)
        var director = joint
        let changed = director.end(now: now, brains: &brains)
        joint = director
        for index in slots.indices { slots[index].brain = brains[index] }
        return changed
    }

    // MARK: Who is on the stage

    private func setCharacters(_ kinds: [CharacterKind]) {
        let wanted = Array(kinds.prefix(CharacterKind.maxPerScreen))
        guard wanted != characters else { return }
        // Their numbers change, and one of a scene's two may be going: the scene is over before they do.
        _ = endJointScene(now: sources.clock())
        // A character that stays keeps what it was doing, and one that is not there before comes with nothing.
        var kept = slots
        slots = wanted.map { kind in
            if let index = kept.firstIndex(where: { $0.kind == kind }) { return kept.remove(at: index) }
            return Slot(kind: kind, species: sources.species(kind), brain: nil)
        }
        guard isAlive, !isShutDown else { return }
        if slots.isEmpty {
            nextTick?.cancel()
            nextTick = nil
            hosts.forEach { $0.stopShowing() }
            return
        }
        // One that comes sits down where it is made, and none is startled by a pointer that was already there.
        let now = sources.clock()
        for index in makeBrains(now: now) { slots[index].brain?.resume(now: now) }
        hostsDidMove()
        if !isResting, nextTick == nil {
            _ = sources.cpu.load()
            load = 0
            hasLoad = false
            busy.resume()
            tickIndex = 0
            scheduleTick()
        }
    }

    /// A brain for every character that has none, each with a stream of its own (the first place's is the stage's own, so a character alone
    /// is as it was, and one that joins it changes nothing of what it does) and standing where it leaves room for the others. Which
    /// characters got one.
    @discardableResult
    private func makeBrains(now: TimeInterval) -> [Int] {
        let made = slots.indices.filter { slots[$0].brain == nil }
        for index in made {
            let seed = sources.seed &+ UInt64(index) &* 0xD1B5_4A32_D192_ED03
            slots[index].brain = slots[index].species.makeBrain(
                seed: seed, now: now, position: LaneRules.startingPlace(index, of: slots.count)
            )
        }
        return made
    }

    // MARK: Petting

    /// A character was clicked: it purrs, and the cat mews if the user wants it to. One that does not move purrs without moving, and still
    /// mews.
    func catWasClicked(character index: Int = 0) {
        strokes += 1
        // A stroke is for one of the two: the one that is stroked is not played with, and the other comes down.
        if let play = joint.play, index == play.host || index == play.guest, endJointScene(now: sources.clock()) { showAll() }
        if slots.indices.contains(index), !isResting, var brain = slots[index].brain {
            let outcome = brain.pet(now: sources.clock())
            slots[index].brain = brain
            if outcome == .changed { showAll() }
        }
        if playsMeow, slots.indices.contains(index) ? slots[index].species.meowsWhenPetted : true { sources.meow.play() }
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
        // Still, or about to move again: either way a scene in progress is over, and the next is a few minutes away.
        _ = endJointScene(now: sources.clock())
        joint.reset()
        if reduces {
            nextTick?.cancel()
            nextTick = nil
            hosts.forEach(showResting(on:))
        } else {
            let now = sources.clock()
            for index in slots.indices { slots[index].brain?.resume(now: now) }
            _ = sources.cpu.load()
            load = 0
            hasLoad = false
            busy.resume()
            tickIndex = 0
            showAll()
            scheduleTick()
        }
    }
}
