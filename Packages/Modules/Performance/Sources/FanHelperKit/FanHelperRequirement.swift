import Foundation
import Security

/// The code-signing requirements each end of the connection puts on the other. Both say: this identifier, signed by a certificate
/// Apple issued (`anchor apple generic`, which covers Apple Development and Developer ID alike), whose leaf names the team in its
/// organizational unit. An ad-hoc signed or differently-signed process fails them.
public enum FanHelperRequirement {
    /// What the helper requires of whoever connects: MyNotch itself.
    public static let app = format(identifier: FanHelperIdentity.appIdentifier, team: FanHelperIdentity.teamIdentifier)
    /// What the app requires of what it connects to: the helper.
    public static let helper = format(identifier: FanHelperIdentity.helperIdentifier, team: FanHelperIdentity.teamIdentifier)

    /// The requirement for `identifier` and `team`, or nil when either holds anything that could change what the requirement means
    /// (a quote, a space, an operator): identifiers are letters, digits, dots, dashes and underscores; a team is ten capital
    /// letters and digits.
    public static func make(identifier: String, team: String) -> String? {
        guard isIdentifier(identifier), isTeam(team) else { return nil }
        return format(identifier: identifier, team: team)
    }

    /// Whether the Security framework accepts the text; handing `NSXPCConnection` one it does not accept raises an exception, so the
    /// helper checks before it listens.
    public static func isValid(_ requirement: String) -> Bool {
        var compiled: SecRequirement?
        return SecRequirementCreateWithString(requirement as CFString, [], &compiled) == errSecSuccess && compiled != nil
    }

    private static func format(identifier: String, team: String) -> String {
        "identifier \"\(identifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
    }

    private static func isIdentifier(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) || "._-".utf8.contains($0) }
    }

    private static func isTeam(_ text: String) -> Bool {
        text.utf8.count == 10 && text.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) }
    }
}
