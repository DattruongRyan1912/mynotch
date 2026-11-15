import Foundation
import Testing
@testable import SystemActivitiesModule

@Suite struct UnifiedDisplayBrightnessTests {
    @Test func prefersBuiltInWhenBuiltInAvailable() {
        let builtIn = FakeLevelControl(level: 0.75)
        let external = FakeLevelControl(level: 0.40)

        let controller = UnifiedDisplayBrightnessController(builtIn: builtIn, external: external)

        #expect(controller.read() == 0.75)
        #expect(controller.write(0.80))
        #expect(builtIn.level == 0.80)
        #expect(external.level == 0.40)
    }

    @Test func fallsBackToExternalWhenBuiltInUnavailable() {
        let builtIn = FakeLevelControl(level: nil)
        let external = FakeLevelControl(level: 0.50)

        let controller = UnifiedDisplayBrightnessController(builtIn: builtIn, external: external)

        #expect(controller.read() == 0.50)
        #expect(controller.write(0.65))
        #expect(external.level == 0.65)
    }

    @Test func explicitTargetChooserOverridesPriority() {
        let builtIn = FakeLevelControl(level: 0.90)
        let external = FakeLevelControl(level: 0.30)

        let controller = UnifiedDisplayBrightnessController(
            builtIn: builtIn,
            external: external,
            kindChooser: { .external }
        )

        #expect(controller.read() == 0.30)
        #expect(controller.write(0.45))
        #expect(external.level == 0.45)
    }

    @Test func refreshTouchesBothControllers() {
        let builtIn = FakeLevelControl(level: 0.5)
        let external = FakeLevelControl(level: 0.5)

        let controller = UnifiedDisplayBrightnessController(builtIn: builtIn, external: external)
        controller.refresh()

        #expect(builtIn.refreshCount == 1)
        #expect(external.refreshCount == 1)
    }
}
