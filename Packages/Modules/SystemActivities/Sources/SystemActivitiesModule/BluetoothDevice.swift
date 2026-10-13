import Foundation

nonisolated enum BluetoothDeviceKind: Equatable, Sendable {
    case headphones, keyboard, mouse, other

    /// Maps the Bluetooth class of device (`deviceClassMajor`/`deviceClassMinor`, the 6-bit minor value).
    init(major: UInt32, minor: UInt32) {
        switch major {
        case 4:  // audio/video: wearable headset, hands-free, headphones
            self = [1, 2, 6].contains(minor) ? .headphones : .other
        case 5:  // peripheral: the upper two minor bits tell keyboard / pointing device / combo
            switch minor >> 4 {
            case 1, 3: self = .keyboard
            case 2: self = .mouse
            default: self = .other
            }
        default:
            self = .other
        }
    }
}

/// Battery levels in percent, each 1...100.
nonisolated enum BluetoothBattery: Equatable, Sendable {
    case single(Int)
    case pods(left: Int?, right: Int?, case: Int?)

    /// Earbuds report left/right/case; other devices a single value. Out-of-range values (0 and 255
    /// mean "unknown") are dropped. A lone case value says nothing about the device, so it is no reading.
    static func select(single: Int?, left: Int?, right: Int?, case caseLevel: Int?) -> BluetoothBattery? {
        let valid = { (value: Int?) -> Int? in value.flatMap { (1...100).contains($0) ? $0 : nil } }
        if valid(left) != nil || valid(right) != nil {
            return .pods(left: valid(left), right: valid(right), case: valid(caseLevel))
        }
        return valid(single).map(BluetoothBattery.single)
    }

    /// The single number the activity shows: the weaker earbud, since that is the one that dies first.
    var displayPercent: Int {
        switch self {
        case .single(let level): level
        case .pods(let left, let right, _): min(left ?? 100, right ?? 100)
        }
    }

    /// Best effort: `IOBluetoothDevice` has no public battery API, so each private getter is used only if
    /// the object responds to it.
    static func read(from device: NSObject) -> BluetoothBattery? {
        func level(_ name: String) -> Int? {
            device.responds(to: Selector(name)) ? (device.value(forKey: name) as? NSNumber)?.intValue : nil
        }
        return select(
            single: level("batteryPercentSingle"), left: level("batteryPercentLeft"),
            right: level("batteryPercentRight"), case: level("batteryPercentCase"))
    }
}

nonisolated struct BluetoothEvent: Equatable, Sendable {
    var name: String
    var kind: BluetoothDeviceKind
    var connected: Bool
    var battery: BluetoothBattery?
}

/// Remembers which devices were already connected when watching started: IOBluetooth's connect notification can
/// report them too, and they are not news.
nonisolated struct BluetoothConnectionTracker {
    private var connected: Set<String>

    init(connectedAtStart: some Sequence<String>) {
        connected = Set(connectedAtStart)
    }

    func announcesConnection(of address: String) -> Bool { !connected.contains(address) }

    mutating func disconnected(_ address: String) { connected.remove(address) }
}
