import FanHelperKit
import Foundation
import os

// The privileged helper for the fans (see Performance's FanHelperManager). launchd starts it when the app connects to its mach
// service, as root. For now it answers two questions and does nothing else: who it is (ping) and what the SMC says about the
// fans (readFans). It has no operation that writes. It leaves when nobody has been connected for a while.

let log = Logger(subsystem: "io.lucasvu.mynotch.fanhelper", category: "xpc")

/// Accepts a connection only from MyNotch signed by the team: the requirement is set on each connection before it is resumed,
/// and a connection that does not satisfy it is invalidated by the system without a message being delivered.
nonisolated final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service: FanHelperService
    private let idle: IdleExit

    init(service: FanHelperService, idle: IdleExit) {
        self.service = service
        self.idle = idle
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(FanHelperRequirement.app)
        connection.exportedInterface = FanHelperInterface.make()
        connection.exportedObject = service
        idle.connectionOpened()
        connection.invalidationHandler = { [idle] in
            log.info("connection closed")
            idle.connectionClosed()
        }
        connection.resume()
        log.info("connection accepted from pid \(connection.processIdentifier, privacy: .public)")
        return true
    }
}

// Handing the system a requirement it cannot parse raises an exception on the first connection; refuse to start instead.
guard FanHelperRequirement.isValid(FanHelperRequirement.app) else {
    log.fault("the code-signing requirement is not valid; not listening")
    exit(EXIT_FAILURE)
}

let buildID = CodeIdentity.runningBuildID() ?? "unknown"
log.info("starting: version \(FanHelperIdentity.version, privacy: .public), build \(buildID, privacy: .public), euid \(geteuid(), privacy: .public)")

let idle = IdleExit(after: 20) {
    log.info("idle, exiting")
    exit(EXIT_SUCCESS)
}
let delegate = ListenerDelegate(service: FanHelperService(buildID: buildID), idle: idle)
let listener = NSXPCListener(machServiceName: FanHelperIdentity.machServiceName)
listener.delegate = delegate
listener.resume()
idle.start()
RunLoop.main.run()
