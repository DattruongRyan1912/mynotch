import AppKit
import CoreAudio
import CoreGraphics
import Darwin
import Foundation

/// Everything the cat reads from the Mac. Each is read only while the cat is on the notch, and each is a protocol so that a test never
/// touches the real thing.
protocol IdleTimeSource {
    /// Seconds since the user last used the keyboard or the pointer.
    func secondsSinceLastInput() -> TimeInterval
}

protocol CPULoadSource {
    /// How busy the processors have been since the last call, 0 to 1; nil for the first call, which has nothing to compare with.
    func load() -> Double?
}

protocol PointerSource {
    /// Where the pointer is, in screen coordinates.
    func location() -> CGPoint
}

protocol AudioPlaybackSource {
    /// Whether the Mac is playing sound.
    func isPlaying() -> Bool
}

/// How long since the user's last input, as the window server counts it: any event of the session, so the pointer moving counts.
struct SystemIdleTime: IdleTimeSource {
    func secondsSinceLastInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}

/// The processors' load from the kernel's tick counters: the share of ticks that were not idle since the last read.
final class HostCPULoad: CPULoadSource {
    /// One send right for the life of the process; `mach_host_self()` adds a reference to it at every call.
    private static let host = mach_host_self()
    private var previous: host_cpu_load_info?

    func load() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(Self.host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }
        defer { previous = info }
        guard let previous else { return nil }
        func ticks(_ info: host_cpu_load_info) -> (busy: UInt64, total: UInt64) {
            let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
            let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
            return (user + system + nice, user + system + nice + idle)
        }
        let (now, before) = (ticks(info), ticks(previous))
        let total = now.total &- before.total
        guard total > 0 else { return nil }
        return min(max(Double(now.busy &- before.busy) / Double(total), 0), 1)
    }
}

struct SystemPointer: PointerSource {
    func location() -> CGPoint { NSEvent.mouseLocation }
}

/// Whether the default output device is running for anyone: any app's music, a video, a call. It is not the music alone, which only
/// the Media module can tell, and a module may not read another's state; the cat dances to what it hears.
struct AudioOutputProbe: AudioPlaybackSource {
    func isPlaying() -> Bool {
        var defaultDevice = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultDevice, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return false }
        var running = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &running, 0, nil, &size, &value) == noErr && value != 0
    }
}

/// How near the pointer is to the notch.
nonisolated enum PointerProximity {
    /// How far from the notch counts as near, in points.
    static let margin: CGFloat = 40

    /// Whether `point` is inside any of `rects` (the cat's views, in screen coordinates) or within `margin` of one.
    static func isNear(_ point: CGPoint, to rects: [CGRect], margin: CGFloat = PointerProximity.margin) -> Bool {
        rects.contains { $0.insetBy(dx: -margin, dy: -margin).contains(point) }
    }
}
