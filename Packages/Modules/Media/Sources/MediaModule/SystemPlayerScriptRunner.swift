import AppKit
import ApplicationServices

/// Runs the player scripts with `NSAppleScript`, one at a time on a queue of its own: asking an app, or macOS asking the user for
/// permission, takes time the notch must not wait through, and `NSAppleScript` is not for several threads. A script is compiled
/// the first time it runs, which is only ever for an app that is running (compiling reads the app's scripting terms, and an app
/// that is not installed would make macOS ask where it is).
nonisolated struct SystemPlayerScriptRunner: PlayerScriptRunner {
    private static let queue = DispatchQueue(label: "io.lucasvu.mynotch.media.applescript", qos: .utility)
    /// The scripts compiled so far, by their text; touched only on `queue`. Seeks differ in their number, so it is emptied when it grows.
    nonisolated(unsafe) private static var compiled: [String: NSAppleScript] = [:]
    private static let maxCompiled = 32

    func run(_ source: String) async -> PlayerScriptResult {
        await withCheckedContinuation { continuation in
            Self.queue.async { continuation.resume(returning: Self.execute(source)) }
        }
    }

    private static func execute(_ source: String) -> PlayerScriptResult {
        var error: NSDictionary?
        let script: NSAppleScript
        if let known = compiled[source] {
            script = known
        } else {
            guard let made = NSAppleScript(source: source) else { return .failed }
            guard made.compileAndReturnError(&error) else { return result(forErrorNumber: error?[NSAppleScript.errorNumber] as? Int) }
            if compiled.count >= maxCompiled { compiled.removeAll() }
            compiled[source] = made
            script = made
        }
        let descriptor = script.executeAndReturnError(&error)
        if error != nil { return result(forErrorNumber: error?[NSAppleScript.errorNumber] as? Int) }
        return .value(value(of: descriptor))
    }

    /// -1743: macOS did not let MyNotch control the app (the user said no, or the permission was removed). -600 and -609: the app is
    /// not there (it quit between the check and the event).
    static func result(forErrorNumber number: Int?) -> PlayerScriptResult {
        switch number {
        case -1743: .notAllowed
        case -600, -609: .notRunning
        default: .failed
        }
    }

    /// The descriptor as plain values: lists, numbers, text, and the bytes of a picture.
    static func value(of descriptor: NSAppleEventDescriptor) -> PlayerScriptValue {
        let type = descriptor.descriptorType
        switch type {
        case DescType(typeAEList):
            guard descriptor.numberOfItems > 0 else { return .list([]) }
            return .list((1...descriptor.numberOfItems).map { descriptor.atIndex($0).map(value(of:)) ?? .missing })
        case DescType(typeNull):
            return .missing
        case DescType(typeType):
            // `missing value` is the type code 'msng'.
            return descriptor.typeCodeValue == OSType(fourCharCode("msng")) ? .missing : .text(descriptor.stringValue ?? "")
        case DescType(typeSInt16), DescType(typeSInt32), DescType(typeSInt64), DescType(typeUInt32), DescType(typeIEEE32BitFloatingPoint),
             DescType(typeIEEE64BitFloatingPoint):
            guard let coerced = descriptor.coerce(toDescriptorType: DescType(typeIEEE64BitFloatingPoint)), coerced.data.count == MemoryLayout<Double>.size
            else { return .missing }
            return .number(coerced.data.withUnsafeBytes { $0.loadUnaligned(as: Double.self) })
        case DescType(typeUnicodeText), DescType(typeUTF8Text), DescType(typeChar):
            return .text(descriptor.stringValue ?? "")
        default:
            // A picture (PNG, TIFF, JPEG, ...) or any other data: the bytes, which `NSImage(data:)` reads.
            return descriptor.data.isEmpty ? .missing : .data(descriptor.data)
        }
    }

    private static func fourCharCode(_ text: String) -> UInt32 {
        text.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }
}
