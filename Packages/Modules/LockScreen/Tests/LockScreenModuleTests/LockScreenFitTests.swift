import AppKit
import MyNotchCore
import MyNotchTestSupport
import NotchUI
import SwiftUI
import Testing
@testable import LockScreenModule

/// The panel is as tall as the card it shows, so no strip of it is left that could take a click the card does not want. A card
/// with the lyric lines is about 105 tall and one without about 65; the panel follows when lyrics appear or go.
@Suite struct LockScreenFitTests {
    /// What a media card is without and with a lyric line (cover row, bar and padding; the lyric block and its gap added).
    let plainCard: CGFloat = 65
    let lyricCard: CGFloat = 105

    // MARK: the rule

    @Test func thePanelIsAsTallAsTheCard() {
        #expect(LockScreenPanel.height(forCard: plainCard) == plainCard)
        #expect(LockScreenPanel.height(forCard: lyricCard) == lyricCard)
        #expect(LockScreenPanel.height(forCard: lyricCard) > LockScreenPanel.height(forCard: plainCard), "lyrics make it taller")
    }

    @Test func aFractionOfAPointIsRoundedUpSoTheCardIsNeverClipped() {
        #expect(LockScreenPanel.height(forCard: 64.2) == 65)
        #expect(LockScreenPanel.height(forCard: 65.0) == 65)
    }

    @Test func aCardNeverMakesThePanelSmallerThanTheCardsOwnMinimumOrLargerThanTheLimit() {
        #expect(LockScreenPanel.height(forCard: 3) == LockScreenPanel.minimumHeight)
        #expect(LockScreenPanel.height(forCard: -20) == LockScreenPanel.minimumHeight)
        #expect(LockScreenPanel.height(forCard: .nan) == LockScreenPanel.minimumHeight)
        #expect(LockScreenPanel.height(forCard: 900) == LockScreenPanel.maximumHeight)
        #expect(LockScreenPanel.height(forCard: .infinity) == LockScreenPanel.maximumHeight)
        #expect(LockScreenPanel.minimumHeight == LockScreenRootView.minimumHeight)
        #expect(LockScreenPanel.height(forCard: lyricCard) <= LockScreenPanel.maximumHeight)
    }

    @Test func theFrameUnderTheNotchHasTheHeightItIsGiven() {
        let screen = ScreenDescriptor(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
            auxiliaryTopLeftWidth: 656, auxiliaryTopRightWidth: 656, menuBarHeight: 32
        )
        for height in [plainCard, lyricCard] {
            let frame = LockScreenPanel.frame(on: screen, height: height)
            #expect(frame.size == CGSize(width: LockScreenPanel.width, height: height))
            #expect(frame.maxY == 982 - 32 - LockScreenPanel.gap, "the top stays under the notch whatever the height")
        }
    }

    // MARK: the real panel, never shown

    func makePanel(height: CGFloat) -> LockScreenPanel {
        LockScreenPanel(
            frame: CGRect(x: 100, y: 500, width: LockScreenPanel.width, height: height), content: AnyView(Color.clear), interface: NotchInterface()
        )
    }

    @Test func fittingToAnotherCardKeepsTheTopAndTheSidesAndMovesTheBottom() {
        let panel = makePanel(height: plainCard)
        defer { panel.dismiss() }
        let top = panel.frame.maxY
        panel.fit(toCardHeight: lyricCard)
        #expect(panel.frame.height == lyricCard)
        #expect(panel.frame.maxY == top, "it grows downwards, away from the notch")
        #expect(panel.frame.minX == 100 && panel.frame.width == LockScreenPanel.width)
        panel.fit(toCardHeight: plainCard)
        #expect(panel.frame.height == plainCard)
        #expect(panel.frame.maxY == top, "and shrinks back up")
    }

    @Test func fittingToTheHeightItAlreadyHasMovesNothing() {
        let panel = makePanel(height: plainCard)
        defer { panel.dismiss() }
        let before = panel.frame
        panel.fit(toCardHeight: plainCard)
        panel.fit(toCardHeight: plainCard - 0.4)
        #expect(panel.frame == before)
    }

    @Test func aCardsHeightIsMeasuredAtThePanelsWidthBeforeThePanelIsMade() {
        // What `make` does: the height of whatever the root view draws now, so a card with lyrics is not shown clipped first.
        let plain = AnyView(Color.clear.frame(height: 49).padding(.vertical, 8).frame(maxWidth: .infinity, minHeight: LockScreenRootView.minimumHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
        let lyrics = AnyView(Color.clear.frame(height: 89).padding(.vertical, 8).frame(maxWidth: .infinity, minHeight: LockScreenRootView.minimumHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
        #expect(LockScreenPanel.cardHeight(of: plain) == plainCard)
        #expect(LockScreenPanel.cardHeight(of: lyrics) == lyricCard)
    }

    // MARK: clicks outside the card

    @Test func aClickBelowTheCardOrInItsRoundedCornersIsNotTheCards() throws {
        let panel = makePanel(height: lyricCard)
        defer { panel.dismiss() }
        panel.fit(toCardHeight: plainCard)
        // The panel is a moment taller than the card (lyrics just went), or the card's corners are in its frame.
        panel.setFrame(CGRect(x: 100, y: 500, width: LockScreenPanel.width, height: lyricCard), display: false)
        let hosting = try #require(panel.contentView as? LockScreenHostingView)
        hosting.cardHeight = plainCard
        hosting.layoutSubtreeIfNeeded()
        /// `hitTest` takes a point in the superview's coordinates, which may be flipped against the view's own.
        func point(x: CGFloat, fromTop y: CGFloat) -> NSPoint {
            let local = NSPoint(x: x, y: hosting.isFlipped ? y : hosting.bounds.height - y)
            return hosting.superview.map { hosting.convert(local, to: $0) } ?? local
        }
        let middle = LockScreenPanel.width / 2
        #expect(hosting.hitTest(point(x: middle, fromTop: plainCard / 2)) != nil, "the card itself")
        #expect(hosting.hitTest(point(x: middle, fromTop: 2)) != nil, "its top edge")
        #expect(hosting.hitTest(point(x: middle, fromTop: plainCard - 2)) != nil, "its bottom edge")
        #expect(hosting.hitTest(point(x: middle, fromTop: plainCard + 4)) == nil, "the clear strip under it")
        #expect(hosting.hitTest(point(x: middle, fromTop: lyricCard - 2)) == nil)
        #expect(hosting.hitTest(point(x: 1, fromTop: 1)) == nil, "a corner outside the rounded card")
        #expect(hosting.hitTest(point(x: LockScreenPanel.width - 1, fromTop: plainCard - 1)) == nil)
        #expect(hosting.hitTest(point(x: LockScreenPanel.width - 1, fromTop: plainCard / 2)) != nil, "the side, away from the corners")
    }

    @Test func aPanelWhoseCardIsNotKnownYetTakesClicksAnywhereInItAsBefore() throws {
        let panel = makePanel(height: lyricCard)
        defer { panel.dismiss() }
        let hosting = try #require(panel.contentView as? LockScreenHostingView)
        hosting.cardHeight = nil
        hosting.layoutSubtreeIfNeeded()
        let local = NSPoint(x: LockScreenPanel.width / 2, y: lyricCard - 3)
        #expect(hosting.hitTest(hosting.superview.map { hosting.convert(local, to: $0) } ?? local) != nil)
    }

    // MARK: through the module

    func offer(_ fixture: LockScreenFixture, height: CGFloat) {
        fixture.harness.lockScreen.set(AnyView(Color.clear.frame(height: height)), priority: .normal, isInteractive: true, from: "media")
    }

    /// A hosting view in a window that is never shown, so that SwiftUI lays the root view out and reports the card.
    func host(_ window: FakeLockScreenWindow) -> NSWindow {
        let hosting = NSHostingView(rootView: window.content)
        let offscreen = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: LockScreenPanel.width, height: 200), styleMask: .borderless, backing: .buffered, defer: true
        )
        offscreen.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return offscreen
    }

    @Test func theModuleFitsThePanelToTheCardAndFollowsWhenLyricsAppearAndGo() async {
        let fixture = LockScreenFixture()
        offer(fixture, height: 49)
        await fixture.enable()
        await fixture.lock()
        let window = fixture.factory.windows[0]
        let offscreen = host(window)
        defer { offscreen.contentView = nil }
        #expect(await waitUntil { window.fitted.last == plainCard }, "the card without lyrics: \(window.fitted)")

        offer(fixture, height: 89)
        #expect(await waitUntil { window.fitted.last == lyricCard }, "lyrics came: \(window.fitted)")

        offer(fixture, height: 49)
        #expect(await waitUntil { window.fitted.last == plainCard }, "and went: \(window.fitted)")
    }

    @Test func aWindowThatIsGoneIsNotFittedAnyMore() async {
        let fixture = LockScreenFixture()
        offer(fixture, height: 49)
        await fixture.enable()
        await fixture.lock()
        let window = fixture.factory.windows[0]
        let offscreen = host(window)
        defer { offscreen.contentView = nil }
        #expect(await waitUntil { window.fitted.last == plainCard })
        await fixture.unlock()
        fixture.harness.scheduler.advance(by: LockScreenModule.hideDelay)
        let fits = window.fitted.count
        offer(fixture, height: 89)
        for _ in 0..<50 { await Task.yield() }
        #expect(window.fitted.count == fits)
    }
}
