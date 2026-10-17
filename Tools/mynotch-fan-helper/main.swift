import FanHelperDaemon
import FanHelperKit
import Foundation
import os

// The privileged helper for the fans (see Performance's FanHelperManager). launchd starts it when the app connects to its mach
// service, as root. It answers who it is (ping), what the SMC says about the fans (readFans), and three ways of setting a fan
// (setFloor, setForced, setAuto), which the FanController holds to a lease, a heat guard and the fans' own range. Every way out of
// this process gives the fans back to Apple first.

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
        // Received, not served: the system turns the connection away on its own when the requirement is not met, and nothing
        // below is called for it; "served" lines are the proof that a request got through.
        log.info("connection received from pid \(connection.processIdentifier, privacy: .public), requirement applied")
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

// The writer exists only for a root process; the controller only if the fans and the die sensors can be read. Without it the helper
// still answers its two reads.
let controllerQueue = DispatchQueue(label: "io.lucasvu.mynotch.fanhelper.controller")
let otherFanTool = OtherFanTool()
let controller: FanController? = {
    guard let writer = AppleSMCWriter(), let reader = AppleSMCChannel(), let dieSensors = DieSensors(channel: reader),
          let keyWriter = try? FanKeyWriter(channel: writer, log: { log.info("\($0, privacy: .public)") })
    else {
        log.notice("fan control is not available: no writer, fans or die sensors")
        return nil
    }
    return FanController(
        writer: keyWriter, reader: reader, dieTemperature: { dieSensors.hottest(on: reader) },
        otherToolRunning: { otherFanTool.isRunning() }, log: { log.info("\($0, privacy: .public)") }, queue: controllerQueue
    )
}()

// Every way out gives the fans back: a signal, `exit()` (the idle exit included), the system going to sleep.
restoreBeforeExit = { controller?.restoreAutoForExit() }
installExitHandler()
var signalSources: [DispatchSourceSignal] = []
for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: controllerQueue)
    source.setEventHandler {
        log.info("signal \(signalNumber, privacy: .public), leaving")
        controller?.restoreAutoForExit()
        exit(EXIT_SUCCESS)
    }
    source.resume()
    signalSources.append(source)
}
let powerEvents = PowerEvents(
    queue: controllerQueue, onWillSleep: { controller?.systemWillSleep() }, onDidWake: { controller?.systemDidWake() }
)
if !powerEvents.start() { log.notice("no power notifications; the fans are not given back around sleep") }

let tick = DispatchSource.makeTimerSource(queue: controllerQueue)
tick.schedule(deadline: .now() + 1, repeating: 1)
tick.setEventHandler { controller?.tick() }
tick.resume()
controller?.startUp()

let idle = IdleExit(after: 20, isBusy: { controller?.isHoldingFans ?? false }, onExit: {
    log.info("idle, exiting")
    exit(EXIT_SUCCESS)
})
let service = FanHelperService(
    buildID: buildID, controller: controller, onRequest: { request in log.info("served \(request, privacy: .public)") }
)
let delegate = ListenerDelegate(service: service, idle: idle)
let listener = NSXPCListener(machServiceName: FanHelperIdentity.machServiceName)
listener.delegate = delegate
listener.resume()
idle.start()
RunLoop.main.run()
