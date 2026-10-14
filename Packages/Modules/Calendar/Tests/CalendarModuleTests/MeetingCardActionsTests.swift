import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CalendarModule

@Suite struct MeetingCardActionsTests {
    let calendar = fixedCalendar()
    var standup: AgendaEvent { event("standup", calendar.on(14, at: 10), calendar.on(14, at: 11)) }
    var onlineStandup: AgendaEvent {
        event("standup", calendar.on(14, at: 10), calendar.on(14, at: 11), meetingURL: URL(string: "https://whereby.com/acme-standup"))
    }

    // MARK: Which buttons

    @Test func joinNeedsALink() {
        #expect(MeetingCardActions.available(for: standup, canSnooze: false, canDismiss: false) == [])
        #expect(MeetingCardActions.available(for: onlineStandup, canSnooze: false, canDismiss: false) == [.join])
        #expect(MeetingCardActions.available(for: standup, canSnooze: true, canDismiss: true) == [.snooze, .dismiss])
    }

    @Test func snoozeAndDismissFollowWhatTheCardCanDo() {
        #expect(MeetingCardActions.available(for: onlineStandup, canSnooze: true, canDismiss: true) == [.join, .snooze, .dismiss])
        // Once the meeting has started there is nothing to wait for, but it can still be dismissed.
        #expect(MeetingCardActions.available(for: onlineStandup, canSnooze: false, canDismiss: true) == [.join, .dismiss])
        #expect(MeetingCardActions.available(for: standup, canSnooze: true, canDismiss: false) == [.snooze])
    }

    // MARK: Words

    @Test func theButtonsReadTheWordsOfTheBrief() {
        #expect(MeetingCardAction.join.title == "Tham gia")
        #expect(MeetingCardAction.snooze.title == "Báo lại")
        #expect(MeetingCardAction.dismiss.title == "Bỏ qua")
    }

    @Test func voiceOverNamesTheMeetingEachButtonActsOn() {
        let event = onlineStandup
        #expect(MeetingCardActions.accessibilityLabel(.join, for: event) == "Tham gia cuộc họp standup")
        #expect(MeetingCardActions.accessibilityLabel(.snooze, for: event) == "Báo lại cuộc họp standup")
        #expect(MeetingCardActions.accessibilityLabel(.dismiss, for: event) == "Bỏ qua cuộc họp standup")
        var untitled = event
        untitled.title = ""
        #expect(MeetingCardActions.accessibilityLabel(.dismiss, for: untitled) == "Bỏ qua cuộc họp (Không có tiêu đề)")
    }

    @Test func theSnoozeTooltipSaysWhenTheCardComesBack() {
        #expect(MeetingCardActions.help(.snooze, for: standup, now: calendar.on(14, at: 9, 50)) == "Nhắc lại sau 5 phút")
        #expect(MeetingCardActions.help(.snooze, for: standup, now: calendar.on(14, at: 9, 54)) == "Nhắc lại sau 5 phút")
        // Five minutes from 09:55 is the start itself.
        #expect(MeetingCardActions.help(.snooze, for: standup, now: calendar.on(14, at: 9, 55)) == "Nhắc lại khi cuộc họp bắt đầu")
        #expect(MeetingCardActions.help(.snooze, for: standup, now: calendar.on(14, at: 9, 56)) == "Nhắc lại khi cuộc họp bắt đầu")
        #expect(MeetingCardActions.help(.join, for: onlineStandup, now: calendar.on(14, at: 9, 50)) == "Mở liên kết cuộc họp")
        #expect(MeetingCardActions.help(.dismiss, for: standup, now: calendar.on(14, at: 9, 50)) == "Không nhắc lại cuộc họp này")
    }

    // MARK: Fit

    private func actions() -> CalendarActions {
        CalendarActions(
            open: { _ in }, join: { _ in }, snooze: { _ in }, dismiss: { _ in }, complete: { _ in },
            requestRemindersAccess: {}, appeared: {}
        )
    }

    private func fittingSize<Content: View>(of view: Content) -> CGSize {
        NSHostingView(rootView: view).fittingSize
    }

    /// The three buttons share one row of the card, so the row has to be no wider than the card's text.
    @Test func allThreeButtonsFitOneRowOfTheCard() {
        let row = MeetingCardActions(event: onlineStandup, now: calendar.on(14, at: 9, 57), canSnooze: true, canDismiss: true, actions: actions())
        let size = fittingSize(of: row)
        #expect(size.width > 0)
        #expect(size.width <= CalendarTabView.cardWidth - 2 * CalendarTabView.cardInset, "the row is \(size.width) pt wide")
    }

    /// With a two-line title, a calendar line and all three buttons, the card is no taller than the room the tab leaves it.
    @Test func theCardWithAllThreeButtonsFitsTheTab() {
        var event = onlineStandup
        event.title = "Họp kế hoạch quý bốn của nhóm sản phẩm và kỹ thuật"
        event.location = "Phòng họp 4B, tầng 12"
        let state = CalendarState(now: calendar.on(14, at: 9, 57), calendar: calendar)
        state.featured = event
        state.canDismissFeatured = true
        state.canSnoozeFeatured = true
        let card = UpcomingCard(state: state, actions: actions()).frame(width: CalendarTabView.cardWidth)
        let height = fittingSize(of: card).height
        #expect(height > 0)
        #expect(height <= CalendarTabView.cardMaxHeight, "the card needs \(height) pt")
    }
}
