import FanHelperKit
@preconcurrency import ServiceManagement

/// Registers and removes the helper with the system; faked in tests, which never register anything.
protocol FanHelperRegistering {
    var status: FanHelperRegistrationStatus { get }
    func register() throws
    /// Returns once the system has stopped the helper, if it was running.
    func unregister() async throws
    /// Opens System Settings at Login Items, where the user allows the helper.
    func openSystemSettings()
}

/// The real thing: `SMAppService.daemon` for the plist in the app's bundle (`Contents/Library/LaunchDaemons`).
final class SMAppServiceRegistration: FanHelperRegistering {
    private let service = SMAppService.daemon(plistName: FanHelperIdentity.plistName)

    var status: FanHelperRegistrationStatus { FanHelperRegistrationStatus(service.status) }

    func register() throws { try service.register() }

    func unregister() async throws { try await service.unregister() }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
