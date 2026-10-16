import AppKit
import MyNotchCore
import MyNotchTestSupport
import NotchUI
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
    var kind: NotchKind = .hardware
    /// How often the stage asked what kind of notch a window has.
    var kindAsks = 0
}

/// A stage with everything it reads held by the test, and the two wings of a notch in a window that is never shown.
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
    let leading: CatSpriteView
    let trailing: CatSpriteView

    /// A hardware notch: a wing of 64 by 32 points on each side of a camera 185 points wide.
    static let wingSize = CGSize(width: 64, height: 32)
    static let cameraWidth: CGFloat = 185

    var hour: Int {
        get { knobs.hour }
        set { knobs.hour = newValue }
    }

    var reducesMotion: Bool {
        get { knobs.reducesMotion }
        set { knobs.reducesMotion = newValue }
    }

    var kind: NotchKind {
        get { knobs.kind }
        set { knobs.kind = newValue }
    }

    var kindAsks: Int { knobs.kindAsks }

    init(kind: NotchKind = .hardware, reducesMotion: Bool = false, hour: Int = 12, seed: UInt64 = 7, wingHeight: CGFloat = 32) {
        let knobs = knobs
        knobs.kind = kind
        knobs.reducesMotion = reducesMotion
        knobs.hour = hour
        let scheduler = scheduler
        let sources = CatStage.Sources(
            idle: idle, cpu: cpu, pointer: pointer, audio: audio, meow: meow,
            hour: { knobs.hour }, reducesMotion: { knobs.reducesMotion }, notifications: notifications,
            clock: { scheduler.seconds }, notchKind: { _ in
                knobs.kindAsks += 1
                return knobs.kind
            }, seed: seed
        )
        self.sources = sources
        stage = CatStage(scheduler: scheduler, sources: sources)
        let width = Self.wingSize.width * 2 + Self.cameraWidth
        window = NSWindow(
            contentRect: CGRect(x: 100, y: 800, width: width, height: wingHeight), styleMask: .borderless, backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        leading = CatSpriteView(stage: stage, role: .leading)
        trailing = CatSpriteView(stage: stage, role: .trailing)
        leading.frame = CGRect(x: 0, y: 0, width: Self.wingSize.width, height: wingHeight)
        trailing.frame = CGRect(x: width - Self.wingSize.width, y: 0, width: Self.wingSize.width, height: wingHeight)
        leading.backingScaleOverride = 2
        trailing.backingScaleOverride = 2
    }

    /// Both wings come into the window: the cat's views are on a notch that can be seen.
    func show() {
        window.contentView?.addSubview(leading)
        window.contentView?.addSubview(trailing)
    }

    /// Both wings leave: the notch is open, or hidden, or another activity took its place.
    func hide() {
        leading.removeFromSuperview()
        trailing.removeFromSuperview()
    }

    func advance(_ seconds: Double) {
        scheduler.advance(by: .milliseconds(Int((seconds * 1000).rounded())))
    }
}

/// A scheduler for a stage that is never woken.
enum ManualSchedulerStub {
    static func make() -> ManualScheduler { ManualScheduler() }
}
