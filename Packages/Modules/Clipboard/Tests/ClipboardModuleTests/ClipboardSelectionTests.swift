import Foundation
import Testing
@testable import ClipboardModule

@Suite struct ClipboardSelectionTests {
    let ids = [UUID(), UUID(), UUID()]

    @Test func nextMovesOneCardAndStopsAtTheLast() {
        #expect(ClipboardSelection.next(in: ids, current: ids[0]) == ids[1])
        #expect(ClipboardSelection.next(in: ids, current: ids[1]) == ids[2])
        #expect(ClipboardSelection.next(in: ids, current: ids[2]) == ids[2])
    }

    @Test func previousMovesOneCardAndStopsAtTheFirst() {
        #expect(ClipboardSelection.previous(in: ids, current: ids[2]) == ids[1])
        #expect(ClipboardSelection.previous(in: ids, current: ids[1]) == ids[0])
        #expect(ClipboardSelection.previous(in: ids, current: ids[0]) == ids[0])
    }

    @Test func anEmptyRowHasNoSelection() {
        let empty: [UUID] = []
        #expect(ClipboardSelection.current(in: empty, selected: ids[0]) == nil)
        #expect(ClipboardSelection.next(in: empty, current: ids[0]) == nil)
        #expect(ClipboardSelection.previous(in: empty, current: nil) == nil)
    }

    /// The tab marks the first card when nothing is selected, so moving starts from it.
    @Test func aMissingOrNilCurrentCountsAsTheFirstCard() {
        let filteredAway = UUID()
        #expect(ClipboardSelection.current(in: ids, selected: ids[1]) == ids[1])
        #expect(ClipboardSelection.current(in: ids, selected: filteredAway) == ids[0])
        #expect(ClipboardSelection.current(in: ids, selected: nil) == ids[0])
        #expect(ClipboardSelection.next(in: ids, current: filteredAway) == ids[1])
        #expect(ClipboardSelection.next(in: ids, current: nil) == ids[1])
        #expect(ClipboardSelection.previous(in: ids, current: filteredAway) == ids[0])
        #expect(ClipboardSelection.previous(in: ids, current: nil) == ids[0])
    }

    @Test func aSingleCardStaysSelected() {
        let only = [ids[0]]
        #expect(ClipboardSelection.next(in: only, current: ids[0]) == ids[0])
        #expect(ClipboardSelection.previous(in: only, current: ids[0]) == ids[0])
    }
}
