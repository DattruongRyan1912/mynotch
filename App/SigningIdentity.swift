import CryptoKit
import Foundation
import Security

/// What macOS keys the app's permissions by. Re-signing with another certificate changes it, and every permission
/// granted before is gone, so a changed value tells the app to ask for them again.
enum SigningIdentity {
    /// A fingerprint of the running app's designated requirement; nil when the system cannot read it.
    static func current() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement else { return nil }
        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text else { return nil }
        return SHA256.hash(data: Data((text as String).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
