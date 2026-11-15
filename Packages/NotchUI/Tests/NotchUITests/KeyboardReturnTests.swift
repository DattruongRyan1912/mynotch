import Testing
@testable import NotchUI

@Suite struct KeyboardReturnTests {
    typealias Step = KeyboardReturn.Step

    @Test func theDefaultHandsKeyStatusToAHiddenPanelAndNeverTouchesTheNotchPanel() {
        #expect(KeyboardReturn.sinkPanel.steps(frontIsOtherApp: true) == [.showSink, .makeSinkKey, .hideSink])
        #expect(KeyboardReturn.sinkPanel.steps(frontIsOtherApp: false) == [.showSink, .makeSinkKey, .hideSink])
    }

    @Test func onlyTheOriginalStrategyOrdersTheNotchPanelOutAndIn() {
        for strategy in KeyboardReturn.allCases {
            for other in [true, false] {
                let steps = strategy.steps(frontIsOtherApp: other)
                let touchesNotch = steps.contains(.orderNotchOut) || steps.contains(.orderNotchIn)
                #expect(touchesNotch == (strategy == .orderOutIn), "\(strategy) other=\(other)")
            }
        }
        #expect(KeyboardReturn.orderOutIn.steps(frontIsOtherApp: true) == [.orderNotchOut, .orderNotchIn])
    }

    @Test func theHiddenPanelIsShownBeforeItTakesKeyAndLeavesAfterwards() {
        for strategy in [KeyboardReturn.sinkPanel, .sinkAndActivate] {
            let steps = strategy.steps(frontIsOtherApp: true)
            let show = steps.firstIndex(of: .showSink)
            let key = steps.firstIndex(of: .makeSinkKey)
            let hide = steps.firstIndex(of: .hideSink)
            #expect(show != nil && key != nil && hide != nil)
            #expect(show! < key! && key! < hide!, "\(strategy)")
            #expect(steps.filter { $0 == .showSink }.count == 1)
        }
    }

    @Test func reactivatingTheAppInFrontComesLastAndOnlyForAnotherApp() {
        #expect(KeyboardReturn.sinkAndActivate.steps(frontIsOtherApp: true) == [.showSink, .makeSinkKey, .hideSink, .activateFrontApp])
        #expect(KeyboardReturn.sinkAndActivate.steps(frontIsOtherApp: false) == [.showSink, .makeSinkKey, .hideSink])
    }

    @Test func theStrategyComesFromADefaultsValueAndFallsBackToTheHiddenPanel() {
        #expect(KeyboardReturn(defaultsValue: nil) == .sinkPanel)
        #expect(KeyboardReturn(defaultsValue: "") == .sinkPanel)
        #expect(KeyboardReturn(defaultsValue: "nonsense") == .sinkPanel)
        #expect(KeyboardReturn(defaultsValue: "orderOutIn") == .orderOutIn)
        #expect(KeyboardReturn(defaultsValue: "sinkAndActivate") == .sinkAndActivate)
        #expect(KeyboardReturn(defaultsValue: "sinkPanel") == .sinkPanel)
    }

    @Test func stepsAreNamedForTheLog() {
        #expect(KeyboardReturn.sinkPanel.steps(frontIsOtherApp: true).map(\.rawValue) == ["showSink", "makeSinkKey", "hideSink"])
    }
}
