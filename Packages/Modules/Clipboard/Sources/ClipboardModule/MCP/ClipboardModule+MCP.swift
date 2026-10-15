import ClipboardMCPKit
import Foundation
import MyNotchCore

/// The feature for AI agents: a socket the `mynotch-clipboard-mcp` helper connects to, open only while the user has it on and
/// the module runs. What the helper may read is `ClipboardMCPAnswerer`'s; what is said around it is `ClipboardMCPController`'s.
extension ClipboardModule {
    /// Whether the socket is open.
    var mcpListening: Bool { mcpServer?.isListening == true }

    /// The socket sits in the module's own folder, which `ClipboardMCPServer` closes to everyone but the user.
    nonisolated static func defaultMCPSocketPath(_ storage: URL) -> String {
        ClipboardMCPSocket.path(inStorageDirectory: storage)
    }

    /// Follows the setting: on opens the socket (and puts the helper where the agents' configuration points), off closes it.
    func applyMCP(enabled: Bool) {
        guard let context, store != nil else { return }
        if enabled { startMCP(context) } else { stopMCP() }
    }

    /// "Tắt ngay": the setting goes off and the socket closes before this returns, without waiting for the setting to be noticed.
    func turnOffMCPNow(settings: ModuleSettings) {
        settings.set(false, for: ClipboardSettingKeys(settings).mcpEnabled)
        stopMCP()
    }

    func stopMCP() {
        mcpServer?.stop()
        mcpServer = nil
        mcp.isListening = false
    }

    private func startMCP(_ context: ModuleContext) {
        guard mcpServer == nil, let keys else { return }
        do {
            try installMCPHelper(ClipboardMCPHelperFile.destination(in: context.storage.directory))
            mcp.helperFailure = nil
        } catch {
            // The agents cannot start the helper, but what is already configured with an older copy still works.
            mcp.helperFailure = error.localizedDescription
        }
        let settings = context.settings
        let controller = ClipboardMCPController(
            state: mcp, history: { [weak self] in self?.state.history ?? ClipboardHistory() }, index: state.searchIndex,
            // Boards cannot be locked yet; when they can, this names the locked ones and their items stay out.
            lockedBoardIDs: { [] },
            // Asked on every call: turning the feature off stops the next call, even on a connection that is already open.
            isEnabled: { [weak self] in self?.store != nil && settings.value(keys.mcpEnabled) },
            now: now, uptime: ClipboardMCPHelper.ToolRunner.uptime
        )
        let server = ClipboardMCPServer(socketPath: mcpSocketPath(context.storage.directory)) { line in controller.answer(line) }
        do {
            try server.start()
            mcpServer = server
            mcp.isListening = true
            mcp.listenFailure = nil
        } catch {
            mcp.isListening = false
            mcp.listenFailure = "Không mở được cổng cho AI agent (\(error))."
        }
    }
}
