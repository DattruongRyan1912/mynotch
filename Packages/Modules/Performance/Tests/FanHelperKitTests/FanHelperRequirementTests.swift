import Foundation
import Security
import Testing
@testable import FanHelperKit

/// A unit test cannot check these against a signed MyNotch (that needs the team's certificate), so it checks the strings the
/// builders make: exactly what was asked for, valid to the Security framework, and refusing what is not an app of the team.
/// Against the real signed app and a sibling tool they were checked by hand with `codesign --verify -R` (TH2 report).
@Suite struct FanHelperRequirementTests {
    @Test func theHelperOnlyTalksToTheAppOfTheTeam() {
        #expect(
            FanHelperRequirement.app
                == #"identifier "io.lucasvu.mynotch" and anchor apple generic and certificate leaf[subject.OU] = "B394MAY4QN""#
        )
    }

    @Test func theAppOnlyTalksToTheHelperOfTheTeam() {
        #expect(
            FanHelperRequirement.helper
                == #"identifier "mynotch-fan-helper" and anchor apple generic and certificate leaf[subject.OU] = "B394MAY4QN""#
        )
    }

    @Test func bothAreValidRequirements() {
        for requirement in [FanHelperRequirement.app, FanHelperRequirement.helper] {
            #expect(FanHelperRequirement.isValid(requirement), "\(requirement)")
        }
    }

    @Test func anInvalidRequirementIsNotValid() {
        #expect(FanHelperRequirement.isValid("identifier and") == false)
        #expect(FanHelperRequirement.isValid("") == false)
    }

    @Test func theBuilderTakesTheIdentifierAndTheTeam() {
        #expect(
            FanHelperRequirement.make(identifier: "a.b-c_d", team: "ABCDE12345")
                == #"identifier "a.b-c_d" and anchor apple generic and certificate leaf[subject.OU] = "ABCDE12345""#
        )
    }

    @Test func theBuilderRefusesAnythingThatCouldChangeWhatTheRequirementMeans() {
        for identifier in [#"x" or anchor apple or identifier "y"#, "a b", "", "a\"b", "a/b", "é"] {
            #expect(FanHelperRequirement.make(identifier: identifier, team: "B394MAY4QN") == nil, "\(identifier)")
        }
        for team in [#"X" or true or "Y"#, "", "b394may4qn", "B394MAY4Q", "B394MAY4QNN", "B394 AY4QN"] {
            #expect(FanHelperRequirement.make(identifier: "io.lucasvu.mynotch", team: team) == nil, "\(team)")
        }
    }

    /// `/bin/ls` is signed by Apple, so `anchor apple generic` holds for it; the identifier and the team are what turn it away.
    @Test func aBinaryOfAnotherSignerIsRejected() throws {
        for requirement in [FanHelperRequirement.app, FanHelperRequirement.helper] {
            var compiled: SecRequirement?
            #expect(SecRequirementCreateWithString(requirement as CFString, [], &compiled) == errSecSuccess)
            var code: SecStaticCode?
            #expect(SecStaticCodeCreateWithPath(URL(fileURLWithPath: "/bin/ls") as CFURL, [], &code) == errSecSuccess)
            let status = SecStaticCodeCheckValidity(try #require(code), [], compiled)
            #expect(status == errSecCSReqFailed, "\(requirement) -> \(status)")
        }
    }

    @Test func theSignerOfTheTeamIsTheOneInTheTeamField() {
        #expect(FanHelperIdentity.teamIdentifier == "B394MAY4QN")
        #expect(FanHelperIdentity.appIdentifier == "io.lucasvu.mynotch")
    }
}
