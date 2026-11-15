import AppKit
import FanHelperKit
import Foundation
@preconcurrency import ServiceManagement

if CommandLine.arguments.contains("--reset-helper") {
    let service = SMAppService.daemon(plistName: FanHelperIdentity.plistName)
    print("[MyNotch] Resetting helper daemon: \(FanHelperIdentity.plistName)...")
    print("[MyNotch] Initial status: \(service.status.rawValue)")
    do {
        try service.unregister()
        print("[MyNotch] service.unregister() succeeded.")
    } catch {
        print("[MyNotch] service.unregister() note: \(error)")
    }
    print("[MyNotch] Pausing 1.5s for launchd and smd to release Mach ports...")
    Thread.sleep(forTimeInterval: 1.5)
    do {
        try service.register()
        print("[MyNotch] service.register() succeeded. New status: \(service.status.rawValue)")
        exit(EXIT_SUCCESS)
    } catch {
        print("[MyNotch] service.register() failed: \(error)")
        exit(EXIT_FAILURE)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

