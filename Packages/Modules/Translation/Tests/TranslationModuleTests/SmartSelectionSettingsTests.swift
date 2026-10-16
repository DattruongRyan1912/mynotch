import AppKit
import SwiftUI
import Testing
@testable import TranslationModule

@Suite struct SmartSelectionSettingsTests {
    @Test func addingAnAppKeepsTheOrderAndNeverRepeatsIt() {
        #expect(SelectionDenyList.adding("com.apple.Safari", to: []) == ["com.apple.Safari"])
        #expect(SelectionDenyList.adding("com.apple.Notes", to: ["com.apple.Safari"]) == ["com.apple.Safari", "com.apple.Notes"])
        #expect(SelectionDenyList.adding("com.apple.Safari", to: ["com.apple.Safari", "com.apple.Notes"]) == ["com.apple.Safari", "com.apple.Notes"])
    }

    @Test func aBlankIDIsNotAnApp() {
        #expect(SelectionDenyList.adding("", to: ["a"]) == ["a"])
        #expect(SelectionDenyList.adding("  ", to: ["a"]) == ["a"])
    }

    @Test func removingAnAppLeavesTheOthers() {
        #expect(SelectionDenyList.removing("b", from: ["a", "b", "c"]) == ["a", "c"])
        #expect(SelectionDenyList.removing("x", from: ["a"]) == ["a"])
    }

    @Test func theRunningAppsOfferedExcludeTheOnesAlreadyDenied() {
        let apps = RunningApplications(name: { $0 }, running: { [("com.a", "A"), ("com.b", "B"), ("com.c", "C")] })
        #expect(apps.candidates(excluding: ["com.b"]).map(\.id) == ["com.a", "com.c"])
        #expect(apps.candidates(excluding: []).count == 3)
    }

    @Test func anAppIsNamedByItsBundleIDWhenItIsNotInstalled() {
        #expect(RunningApplications.system.name("no.such.app.exists.anywhere") == "no.such.app.exists.anywhere")
    }

    @Test func theRowsLayOutWithAndWithoutADenyList() {
        let apps = RunningApplications(name: { $0 == "com.a" ? "Ứng dụng A" : $0 }, running: { [("com.b", "B")] })
        for list in [[], ["com.a", "com.zzz"]] {
            let view = Form {
                SmartSelectionSettingsView(
                    smartSelection: .constant(true), showChip: .constant(true), showButton: .constant(true), showActivity: .constant(false),
                    denyList: .constant(list),
                    applications: apps
                )
            }
            .formStyle(.grouped)
            #expect(NSHostingView(rootView: view.frame(width: 560)).fittingSize.height > 100)
        }
    }

    @Test func theOptionsAreGreyedWhenTheFeatureIsOff() {
        #expect(SmartSelectionSettingsView.optionsEnabled(smartSelection: true))
        #expect(!SmartSelectionSettingsView.optionsEnabled(smartSelection: false))
    }

    @Test func theSmallButtonIsOnByDefaultAndItsRowIsGreyedWithTheFeature() async {
        let fixture = ModuleFixture()
        await fixture.start()
        #expect(fixture.harness.settingsEnvironment(for: "translation")!.settings.value(fixture.keys.selectionButton))
        #expect(SmartSelectionSettingsView.optionsEnabled(smartSelection: true))
    }

    @Test func theSmallButtonRowSaysWhatItIsFor() {
        #expect(SmartSelectionSettingsView.buttonTitle == "Hiện nút dịch nhỏ khi không tự dịch")
    }
}
