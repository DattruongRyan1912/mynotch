import AppKit
import MyNotchCore
import Testing
import MyNotchTestSupport
@testable import PetModule

/// What the cat reads, held by the test: each counts how often it was read, which is how a test shows that nothing is read while the
/// cat is not on the notch.
final class FakeIdle: IdleTimeSource {
    var seconds: TimeInterval = 0
    private(set) var reads = 0

    func secondsSinceLastInput() -> TimeInterval {
        reads += 1
        return seconds
    }
}

final class FakeCPU: CPULoadSource {
    var value: Double? = 0.05
    private(set) var reads = 0

    func load() -> Double? {
        reads += 1
        return value
    }
}

final class FakePointer: PointerSource {
    /// Far from everything.
    var point = CGPoint(x: 5000, y: 5000)
    private(set) var reads = 0

    func location() -> CGPoint {
        reads += 1
        return point
    }
}

final class FakeAudio: AudioPlaybackSource {
    var playing = false
    private(set) var reads = 0

    func isPlaying() -> Bool {
        reads += 1
        return playing
    }
}

final class FakeMeow: MeowPlayer {
    private(set) var plays = 0
    func play() { plays += 1 }
}

extension ManualScheduler {
    /// The scheduler's time in seconds, which is the cat's clock in a test.
    var seconds: TimeInterval {
        let parts = now.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}

/// What the stage asks the world about, held by the test and changed while it runs.
final class Knobs {
    var hour = 12
    var reducesMotion = false
}

/// A stage with everything it reads held by the test, and a strip of a notch in a window that is never shown.
@MainActor final class StageRig {
    let scheduler = ManualScheduler()
    let idle = FakeIdle()
    let cpu = FakeCPU()
    let pointer = FakePointer()
    let audio = FakeAudio()
    let meow = FakeMeow()
    let notifications = NotificationCenter()
    let knobs = Knobs()
    let sources: CatStage.Sources
    let stage: CatStage
    let window: NSWindow
    let host: CatSpriteView

    /// The strip of a MacBook's collapsed notch: its width, less the padding the notch gives it, by the height the cat asks for.
    static let stripSize = CGSize(width: 300, height: CatActivity.stripHeight)

    var hour: Int {
        get { knobs.hour }
        set { knobs.hour = newValue }
    }

    var reducesMotion: Bool {
        get { knobs.reducesMotion }
        set { knobs.reducesMotion = newValue }
    }

    init(reducesMotion: Bool = false, hour: Int = 12, seed: UInt64 = 7, width: CGFloat = 300) {
        let knobs = knobs
        knobs.reducesMotion = reducesMotion
        knobs.hour = hour
        let scheduler = scheduler
        let sources = CatStage.Sources(
            idle: idle, cpu: cpu, pointer: pointer, audio: audio, meow: meow,
            hour: { knobs.hour }, reducesMotion: { knobs.reducesMotion }, notifications: notifications,
            clock: { scheduler.seconds }, seed: seed
        )
        self.sources = sources
        stage = CatStage(scheduler: scheduler, sources: sources)
        window = NSWindow(
            contentRect: CGRect(x: 100, y: 800, width: width, height: Self.stripSize.height), styleMask: .borderless, backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        host = CatSpriteView(stage: stage)
        host.frame = CGRect(x: 0, y: 0, width: width, height: Self.stripSize.height)
    }

    /// The strip comes into the window: the cat's view is on a notch that can be seen.
    func show() {
        window.contentView?.addSubview(host)
    }

    /// The strip leaves: the notch is open, or hidden, or another activity took its place.
    func hide() {
        host.removeFromSuperview()
    }

    func advance(_ seconds: Double) {
        scheduler.advance(by: .milliseconds(Int((seconds * 1000).rounded())))
    }

    /// The pointer, on the screen, at a share of the lane and `above` points over the strip.
    func place(pointerAtShare share: Double, above: CGFloat = 0) {
        guard let strip = host.screenFrame else { return }
        let lane = host.lane
        pointer.point = CGPoint(
            x: strip.minX + lane.minX + CatSpriteView.spriteSize.width / 2 + lane.travel * CGFloat(share), y: strip.midY + above
        )
    }
}

/// A scheduler for a stage that is never woken.
enum ManualSchedulerStub {
    static func make() -> ManualScheduler { ManualScheduler() }
}

/// What the render server does when a leg runs to its end: the animation's delegate is told.
@MainActor func arrive(_ layer: CALayer) throws {
    let walk = try #require(layer.animation(forKey: CatSpriteView.walkKey) as? CAKeyframeAnimation)
    let delegate = try #require(walk.delegate)
    delegate.animationDidStop?(walk, finished: true)
}
