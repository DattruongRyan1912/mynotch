import Foundation
import Security

/// The build id: the hash of a program's code directory, which changes with every build and with every change of the signature.
/// The helper reports the one of the image that is running, and the app computes the one of the helper inside its own bundle, so
/// an app that was replaced on disk finds a helper that is still the old one.
public enum CodeIdentity {
    /// The hash of the code of the process that asks, from the kernel's own record of it, so it is the running image's even
    /// after the file it was started from was replaced. Nil when the process is not signed.
    public static func runningBuildID() -> String? {
        typealias Csops = @convention(c) (Int32, UInt32, UnsafeMutableRawPointer?, Int) -> Int32
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "csops") else { return nil }   // RTLD_DEFAULT
        let csops = unsafeBitCast(symbol, to: Csops.self)
        var hash = [UInt8](repeating: 0, count: 20)
        let status = hash.withUnsafeMutableBytes { csops(getpid(), 5, $0.baseAddress, $0.count) }   // CS_OPS_CDHASH
        return status == 0 ? hex(hash) : nil
    }

    /// The hash of the code directory of the signed program at `url`; nil when it does not exist or is not signed.
    public static func buildID(ofFileAt url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any], let hash = dictionary[kSecCodeInfoUnique as String] as? Data
        else { return nil }
        return hex(Array(hash))
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
