import Darwin
import Foundation
import Testing
@testable import PortsModule

@Suite struct StopPolicyTests {
    let policy = StopPolicy(currentUID: 501, ownPID: 700, ownBundlePath: "/Applications/MyNotch.app")

    @Test func aProcessOfTheUserIsAllowed() {
        #expect(policy.refusal(for: .make()) == nil)
        #expect(policy.refusal(for: .make(path: "/usr/local/bin/ruby")) == nil)
        #expect(policy.refusal(for: .make(path: "/Applications/Docker.app/Contents/MacOS/com.docker.backend")) == nil)
    }

    @Test func toolsInUsrBinAreAllowedBecauseSshTunnelsAndPythonServersLiveThere() {
        for tool in ["ssh", "python3", "ruby", "nc", "php"] {
            #expect(policy.refusal(for: .make(path: "/usr/bin/\(tool)")) == nil, Comment(rawValue: tool))
        }
    }

    @Test func pidOneAndTheKernelAreRefusedWhoeverOwnsThem() {
        #expect(policy.refusal(for: .make(pid: 1, uid: 501)) == .launchd)
        #expect(policy.refusal(for: .make(pid: 0, uid: 501)) == .launchd)
        #expect(policy.refusal(for: .make(pid: -1, uid: 501)) == .launchd)
        #expect(policy.refusal(for: .make(pid: 1, uid: 0)) == .launchd)
    }

    @Test func aRootProcessIsRefused() {
        #expect(policy.refusal(for: .make(pid: 300, uid: 0, path: "/opt/tool/daemon")) == .root)
        #expect(policy.refusal(for: .make(pid: 300, uid: 501, realUID: 0)) == .root, "a setuid root program is root's")
        let asRoot = StopPolicy(currentUID: 0, ownPID: 700, ownBundlePath: nil)
        #expect(asRoot.refusal(for: .make(pid: 300, uid: 0, path: "/opt/tool/daemon")) == .root, "even for a user who is root")
    }

    @Test func anotherUsersProcessIsRefused() {
        #expect(policy.refusal(for: .make(pid: 300, uid: 502)) == .otherUser)
        #expect(policy.refusal(for: .make(pid: 300, uid: 501, realUID: 502)) == .otherUser)
        #expect(policy.refusal(for: .make(pid: 300, uid: 502, realUID: 501)) == .otherUser)
    }

    @Test func myNotchItselfAndWhatIsInsideItIsRefused() {
        #expect(policy.refusal(for: .make(pid: 700, path: "/Applications/MyNotch.app/Contents/MacOS/MyNotch")) == .ownApp)
        #expect(policy.refusal(for: .make(pid: 700, path: nil)) == .ownApp, "by pid, whatever the path says")
        #expect(policy.refusal(for: .make(pid: 701, path: "/Applications/MyNotch.app/Contents/MacOS/mynotch-hook")) == .ownApp)
        #expect(policy.refusal(for: .make(pid: 702, path: "/Applications/MyNotch.app")) == .ownApp)
        #expect(policy.refusal(for: .make(pid: 703, path: "/Applications/MyNotch.app.backup/x")) == nil, "another folder with the same start")
    }

    @Test func whatMacOSRunsForItselfIsRefused() {
        for path in [
            "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter", "/usr/libexec/rapportd", "/usr/sbin/cupsd",
            "/sbin/launchd", "/bin/sh", "/Library/Apple/System/Library/CoreServices/X",
        ] {
            #expect(policy.refusal(for: .make(pid: 300, path: path)) == .system, Comment(rawValue: path))
        }
    }

    @Test func aProcessWhoseExecutableIsUnknownIsRefusedRatherThanGuessed() {
        #expect(policy.refusal(for: .make(pid: 300, path: nil)) == .unreadable)
    }

    @Test func everyRefusalSaysWhy() {
        for refusal in [StopRefusal.launchd, .ownApp, .root, .otherUser, .unreadable, .system] {
            #expect(!refusal.message.isEmpty)
        }
    }

    @Test func theRealPolicyKnowsThisProcessAndTheUser() {
        let current = StopPolicy.current
        #expect(current.currentUID == getuid())
        #expect(current.ownPID == getpid())
        #expect(current.refusal(for: .make(pid: getpid(), uid: getuid())) == .ownApp)
    }
}

@Suite struct ProcessControlTests {
    @Test func onlyRealPidsAboveLaunchdCanEverBeSignalled() {
        // `kill(0, …)` is the whole process group and `kill(-1, …)` every process of the user: the guard in front of `kill` is the
        // line that keeps a bad pid from doing that, so it is tested as a plain function and never by sending.
        #expect(!LibprocProcessControl.isSignalable(pid: 0))
        #expect(!LibprocProcessControl.isSignalable(pid: -1))
        #expect(!LibprocProcessControl.isSignalable(pid: Int32.min))
        #expect(!LibprocProcessControl.isSignalable(pid: 1))
        #expect(LibprocProcessControl.isSignalable(pid: 2))
        #expect(LibprocProcessControl.isSignalable(pid: 70_000))
    }

    @Test func theSignalNumbersAreTermAndKill() {
        #expect(StopSignal.terminate.number == SIGTERM)
        #expect(StopSignal.kill.number == SIGKILL)
    }
}
