import AppKit
import CoreAudio

/// `HardwareChangeSource` over the notifications that matter to the keys: the default output device (volume), the
/// displays (brightness) and waking from sleep, after which both the displays and the keyboard may be different.
final class HardwareChangeNotifier: HardwareChangeSource {
    private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []
    private var deviceListener: (address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)?

    init() {}

    isolated deinit { stop() }

    func start(_ onChange: @escaping @MainActor () -> Void) {
        stop()
        for (center, notification) in [
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
        ] {
            let token = center.addObserver(forName: notification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { onChange() }
            }
            observers.append((center, token))
        }
        let block: AudioObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated { onChange() } }
        var address = CoreAudioOutput.defaultDevice
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block) == noErr {
            deviceListener = (address, block)
        }
    }

    func stop() {
        observers.forEach { $0.center.removeObserver($0.token) }
        observers = []
        if var listener = deviceListener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &listener.address, .main, listener.block)
        }
        deviceListener = nil
    }
}
