import AppKit
import Foundation
import MyNotchCore
import SwiftUI

/// Record of battery drain during sleep.
public struct SleepDrainRecord: Equatable, Sendable {
    public let drainPercent: Int
    public let duration: TimeInterval
    public let date: Date

    public init(drainPercent: Int, duration: TimeInterval, date: Date = Date()) {
        self.drainPercent = drainPercent
        self.duration = duration
        self.date = date
    }
}

/// Monitors battery discharge during macOS sleep and alerts the user on wake if significant drain occurred.
///
/// Excess drain during sleep indicates background processes or peripheral wake-locks preventing deep sleep.
@MainActor
public final class BatterySleepGuard {
    public typealias BatteryLevelProvider = @MainActor () -> Int?
    public typealias DrainAlertHandler = @MainActor (_ drainPercent: Int, _ sleepDuration: TimeInterval) -> Void

    public private(set) var lastSleepRecord: SleepDrainRecord?
    public var onWillSleep: (@MainActor () -> Void)?
    public var onDidWake: (@MainActor () -> Void)?

    private let readPercent: BatteryLevelProvider
    private let onDrainAlert: DrainAlertHandler
    private let thresholdPercent: Int
    private let notificationCenter: NotificationCenter

    private var sleepPercent: Int?
    private var sleepDate: Date?
    private var observers: [Any] = []

    public init(
        thresholdPercent: Int = 3,
        readPercent: @escaping BatteryLevelProvider,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        onDrainAlert: @escaping DrainAlertHandler
    ) {
        self.thresholdPercent = thresholdPercent
        self.readPercent = readPercent
        self.notificationCenter = notificationCenter
        self.onDrainAlert = onDrainAlert
    }

    public func start() {
        stop()
        let obs1 = notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleWillSleep()
            }
        }

        let obs2 = notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleDidWake()
            }
        }

        observers = [obs1, obs2]
    }

    public func stop() {
        for obs in observers {
            notificationCenter.removeObserver(obs)
        }
        observers.removeAll()
        sleepPercent = nil
        sleepDate = nil
    }

    public func handleWillSleep(at date: Date = Date()) {
        onWillSleep?()
        sleepPercent = readPercent()
        sleepDate = date
    }

    public func handleDidWake(at date: Date = Date()) {
        onDidWake?()
        guard let sPercent = sleepPercent, let sDate = sleepDate else { return }
        sleepPercent = nil
        sleepDate = nil

        guard let wakePercent = readPercent() else { return }

        let drain = sPercent - wakePercent
        let duration = date.timeIntervalSince(sDate)
        lastSleepRecord = SleepDrainRecord(drainPercent: max(0, drain), duration: duration, date: date)

        if drain >= thresholdPercent {
            onDrainAlert(drain, duration)
        }
    }
}
