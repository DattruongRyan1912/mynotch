import Foundation
import Testing
@testable import ClipboardModule

/// What `ClipboardState` tells the notch tab's preview: that the cards it shows, or the selected one, changed.
@Suite struct ClipboardStateShownObserverTests {
    final class Owner {}

    let state = ClipboardState()
    let owner = Owner()
    var count = 0

    init() {
        var history = ClipboardHistory()
        for text in ["một", "hai", "ba"] {
            let content = ClipboardContent.text(text)
            history.add(content, hash: ClipboardContent.hash(of: content), source: (nil, nil), at: .now)
        }
        state.history = history
    }

    final class Counter {
        var value = 0
    }

    func observe() -> Counter {
        let counter = Counter()
        state.observeShown(owner) { counter.value += 1 }
        return counter
    }

    @Test func aChangeOfSelectionIsTold() {
        let counter = observe()
        state.selectedID = state.visibleItems.last?.id
        #expect(counter.value == 1)
    }

    @Test func aSearchAFilterAndAChangeOfHistoryAreTold() {
        let counter = observe()
        state.query.text = "hai"
        let afterSearch = counter.value
        #expect(afterSearch > 0)
        state.query.kind = .text
        #expect(counter.value > afterSearch)

        let before = counter.value
        let content = ClipboardContent.text("hai bốn")
        state.history.add(content, hash: ClipboardContent.hash(of: content), source: (nil, nil), at: .now)
        #expect(counter.value > before)
    }

    /// By the time it is told, the cards are already the new ones.
    @Test func whatTheObserverSeesIsAlreadyTheNewCards() {
        var seen: [Int] = []
        state.observeShown(owner) { seen.append(state.visibleItems.count) }
        state.query.text = "hai"
        #expect(seen.last == 1)
        state.query.text = ""
        #expect(seen.last == 3)
    }

    @Test func somethingTheTabDoesNotShowIsNotTold() {
        let counter = observe()
        state.needsAccessibility = true
        state.pasteboardDenied = true
        state.vaultNotice = "x"
        #expect(counter.value == 0)
    }

    @Test func anObserverThatStoppedIsNotTold() {
        let counter = observe()
        state.stopObservingShown(owner)
        state.selectedID = state.visibleItems.last?.id
        #expect(counter.value == 0)
    }

    @Test func anOwnerHasOneActionAndANewOneReplacesTheOld() {
        let first = observe()
        let second = Counter()
        state.observeShown(owner) { second.value += 1 }
        state.selectedID = state.visibleItems.last?.id
        #expect(first.value == 0)
        #expect(second.value == 1)
    }

    @Test func theTabsModelStopsObservingWhenItIsGone() {
        var model: ClipboardTabPreviewModel? = ClipboardTabPreviewModel(state: state)
        model?.togglePreview()
        #expect(model?.isPreviewOpen == true)
        model = nil
        // A change after it is gone has nobody to tell, and does not crash.
        state.selectedID = state.visibleItems.last?.id
        state.query.text = "ba"
        #expect(state.visibleItems.count == 1)
    }
}
