import AppKit
import MyNotchCore
import MyNotchTestSupport
import NotchUI
import SwiftUI
import Testing
@testable import PetModule

/// The screens the tests put a notch on: the Mac this was made for (a camera of 220 by 38 points in 1800 by 1169, which is x 790 to 1010),
/// and a display with none.
enum Screens {
    static let mac = ScreenDescriptor(
        frame: CGRect(x: 0, y: 0, width: 1800, height: 1169), safeAreaTop: 38, auxiliaryTopLeftWidth: 790, auxiliaryTopRightWidth: 790, menuBarHeight: 38
    )
    static let external = ScreenDescriptor(
        frame: CGRect(x: 1800, y: 0, width: 1920, height: 1080), safeAreaTop: 0, auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil, menuBarHeight: 25
    )

    static let hardware = NotchGeometry(screen: mac, config: NotchLayoutConfig())
    static let notch = NotchGeometry(screen: external, config: NotchLayoutConfig())
    static let pill = NotchGeometry(screen: external, config: NotchLayoutConfig(virtualNotchStyle: .pill))
    static let tallPill = NotchGeometry(screen: external, config: NotchLayoutConfig(virtualNotchStyle: .pill, pillHeight: 56))

    /// The width of the top row of a notch that has been asked for what the cat asks, as the notch makes it: the cat's request and the ears.
    static func row(of geometry: NotchGeometry, place: PlayPlace = .portal) -> CGFloat {
        let layout = CatBodyLayout(kind: geometry.kind, place: place)
        let asked = layout.requestedWidth(cameraWidth: geometry.notchSize.width)
        return geometry.compactWidth(stripWidth: asked - 2 * NotchTokens.stripPadding) - 2 * geometry.cornerRadii(for: .compact).top
    }

    /// Where the areas of the menu bar either side of the camera are, on the Mac, in screen coordinates.
    static let macAreas: (left: CGRect?, right: CGRect?) = (
        CGRect(x: 0, y: 1169 - 38, width: 790, height: 38), CGRect(x: 1010, y: 1169 - 38, width: 790, height: 38)
    )
}

/// The cat in the top row of one notch, everything it reads held by the test, in a window that is never shown.
@MainActor final class BodyRig {
    let scheduler = ManualScheduler()
    let idle = FakeIdle()
    let cpu = FakeCPU()
    let pointer = FakePointer()
    let audio = FakeAudio()
    let meow = FakeMeow()
    let notifications = NotificationCenter()
    let knobs = Knobs()
    let stage: CatStage
    let window: NSWindow
    let container: CatBodyContainer
    let geometry: NotchGeometry
    let rowWidth: CGFloat

    init(geometry: NotchGeometry, place: PlayPlace = .portal, seed: UInt64 = 7, hour: Int = 12, reducesMotion: Bool = false, width: CGFloat? = nil) {
        self.geometry = geometry
        knobs.hour = hour
        knobs.reducesMotion = reducesMotion
        let knobs = knobs
        let scheduler = scheduler
        let sources = CatStage.Sources(
            idle: idle, cpu: cpu, pointer: pointer, audio: audio, meow: meow, hour: { knobs.hour }, reducesMotion: { knobs.reducesMotion },
            notifications: notifications, clock: { scheduler.seconds }, seed: seed
        )
        stage = CatStage(scheduler: scheduler, sources: sources)
        rowWidth = width ?? Screens.row(of: geometry, place: place)
        // The row is in the middle of the screen's top, as the notch is.
        let screen = geometry.kind == .hardware ? Screens.mac : Screens.external
        let left = screen.frame.midX + geometry.centerOffset - rowWidth / 2
        window = NSWindow(
            contentRect: CGRect(x: left, y: screen.frame.maxY - geometry.notchSize.height, width: rowWidth, height: geometry.notchSize.height),
            styleMask: .borderless, backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        container = CatBodyContainer(stage: stage)
        container.frame = CGRect(x: 0, y: 0, width: rowWidth, height: geometry.notchSize.height)
        container.screenAreas = { _ in geometry.kind == .hardware ? Screens.macAreas : nil }
    }

    /// The notch is on screen: the cat's views are in it.
    func show() {
        window.contentView?.addSubview(container)
        container.configure(geometry: geometry)
        container.layoutSubtreeIfNeeded()
    }

    func hide() { container.removeFromSuperview() }

    func advance(_ seconds: Double) { scheduler.advance(by: .milliseconds(Int((seconds * 1000).rounded()))) }

    var hosts: [CatSpriteView] { container.catViews }
}
