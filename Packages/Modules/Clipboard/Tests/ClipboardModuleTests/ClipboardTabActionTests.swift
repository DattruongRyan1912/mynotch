import Foundation
import Testing
@testable import ClipboardModule

/// Module actions only the tab uses, on the same fixture as `ClipboardModuleTests`.
extension ClipboardModuleTests {
    @Test func aToastFromTheTabShowsOverTheOpenNotchWithoutClosingIt() async {
        module.showToast("Không áp dụng được", systemImage: "wand.and.stars")
        #expect(harness.presenter.toastCount == 0)

        await start()
        module.showToast("Không áp dụng được", systemImage: "wand.and.stars")

        #expect(harness.presenter.toastCount == 1)
        #expect(harness.presenter.closeCount == 0)
    }
}
