import CoreAudio
import Synchronization

/// Calls `onChange` (on a Core Audio notification thread) whenever one property of an audio object changes,
/// until `remove()`. Uses the function-pointer API: a Swift closure given to the block API is bridged to a new
/// block on every call, so `AudioObjectRemovePropertyListenerBlock` never finds it and the listener stays.
/// The client data is a token rather than a pointer, so a notification arriving after `remove()` finds nothing.
nonisolated final class AudioPropertyListener: Sendable {
    private struct Registry {
        var nextToken = 1
        var handlers: [Int: @Sendable () -> Void] = [:]
    }

    private static let registry = Mutex(Registry())

    private static let notify: AudioObjectPropertyListenerProc = { _, _, _, clientData in
        let token = Int(bitPattern: clientData)
        let handler = AudioPropertyListener.registry.withLock { $0.handlers[token] }
        handler?()
        return noErr
    }

    private let object: AudioObjectID
    private let address: AudioObjectPropertyAddress
    private let token: Int

    init(object: AudioObjectID, selector: AudioObjectPropertySelector, onChange: @escaping @Sendable () -> Void) throws(AudioHardwareError) {
        self.object = object
        address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        token = Self.registry.withLock { registry in
            let token = registry.nextToken
            registry.nextToken += 1
            registry.handlers[token] = onChange
            return token
        }
        var address = address
        let status = AudioObjectAddPropertyListener(object, &address, Self.notify, UnsafeMutableRawPointer(bitPattern: token))
        guard status == noErr else {
            Self.registry.withLock { _ = $0.handlers.removeValue(forKey: token) }
            throw AudioHardwareError(status)
        }
    }

    func remove() {
        Self.registry.withLock { _ = $0.handlers.removeValue(forKey: token) }
        var address = address
        AudioObjectRemovePropertyListener(object, &address, Self.notify, UnsafeMutableRawPointer(bitPattern: token))
    }
}
