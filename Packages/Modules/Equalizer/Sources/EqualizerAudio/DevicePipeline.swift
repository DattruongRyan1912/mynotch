import CoreAudio
import EqualizerDSP
import Foundation
import MyNotchCore
import os

/// One output device's EQ: a private tap of what other processes send to it (silenced at the device while tapped), an aggregate
/// device on that device plus the tap, and an IO proc that reads the tap, filters it with an `EQChain` and writes the device.
/// Never used by tests.
nonisolated final class DevicePipeline: PipelineHandle {
    private static let logger = Log.logger(category: "equalizer")

    private let tap: AudioHardwareTap
    private let undo: TeardownStack
    private let io: PipelineIO
    private let formatRate: Double

    private init(tap: AudioHardwareTap, io: PipelineIO, undo: TeardownStack, rate: Double) {
        self.tap = tap
        self.io = io
        self.undo = undo
        formatRate = rate
    }

    /// A dropped pipeline must not keep the device muted.
    deinit { undo.unwind() }

    var sampleRate: Double { (try? tap.format)?.mSampleRate ?? formatRate }

    func takePeak() -> Float { io.takePeak() }

    func tearDown() { undo.unwind() }

    /// Builds in this order, each step pushing its undo: tap, aggregate device, IO proc, start. A failure unwinds what exists.
    static func make(deviceUID: String, chain: EQChain) throws -> DevicePipeline {
        let hardware = AudioHardwareSystem.shared
        let undo = TeardownStack()
        do {
            // Looked up now, every time: MyNotch has a process object only while it has audio running.
            let ownAtStart = CoreAudioSystem.ownProcessID(hardware)
            let description = TapRecipe.tapDescription(deviceUID: deviceUID, excluding: ownAtStart.map { [$0] } ?? [])
            guard let tap = try hardware.makeProcessTap(description: description) else { throw AudioSystemError("no process tap") }
            undo.push { do { try hardware.destroyProcessTap(tap) } catch { logFailure("destroy the process tap", error) } }

            let format = try tap.format
            guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mBitsPerChannel == 32, format.mSampleRate > 0 else {
                throw AudioSystemError("unsupported tap format \(format.mFormatID) / \(format.mBitsPerChannel) bit")
            }

            guard let aggregate = try hardware.makeAggregateDevice(description: TapRecipe.aggregate(deviceUID: deviceUID, tapUID: try tap.uid))
            else { throw AudioSystemError("no aggregate device") }
            undo.push { do { try hardware.destroyAggregateDevice(aggregate) } catch { logFailure("destroy the aggregate device", error) } }

            let inputStreams = try aggregate.inputStreamConfiguration.map { Int($0.mNumberChannels) }
            let layout = try StreamLayout.resolve(
                tapChannels: Int(format.mChannelsPerFrame),
                isInterleaved: format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0,
                inputStreams: inputStreams,
                outputStreams: try aggregate.outputStreamConfiguration.map { Int($0.mNumberChannels) }
            )

            let io = PipelineIO(chain: chain, layout: layout)
            let block: AudioDeviceIOBlock = { _, input, _, output, _ in io.process(input: input, output: output) }
            var created: AudioDeviceIOProcID?
            try check(AudioDeviceCreateIOProcIDWithBlock(&created, aggregate.id, nil, block), "create the IO proc")
            guard let ioProc = created else { throw AudioSystemError("no IO proc") }
            undo.push { log(AudioDeviceDestroyIOProcID(aggregate.id, ioProc), "destroy the IO proc") }

            useOnlyTheTap(of: aggregate.id, ioProc: ioProc, inputStreams: inputStreams.count, layout: layout)
            try check(AudioDeviceStart(aggregate.id, ioProc), "start the aggregate device")
            // Pushed after the IO proc's, so it is undone before it.
            undo.push { log(AudioDeviceStop(aggregate.id, ioProc), "stop the aggregate device") }

            if ownAtStart == nil { try leaveMyselfOut(of: tap, hardware) }
            io.open()
            return DevicePipeline(tap: tap, io: io, undo: undo, rate: format.mSampleRate)
        } catch {
            undo.unwind()
            throw error
        }
    }

    /// The tap was made before MyNotch had a process object to leave out, so it could hear MyNotch. The IO proc has been
    /// running (silently, it is not open yet), which gives MyNotch one: add it to the tap's excluded processes now.
    private static func leaveMyselfOut(of tap: AudioHardwareTap, _ hardware: AudioHardwareSystem) throws {
        var own = CoreAudioSystem.ownProcessID(hardware)
        var tries = 0
        while own == nil, tries < 6 {
            Thread.sleep(forTimeInterval: 0.05)
            own = CoreAudioSystem.ownProcessID(hardware)
            tries += 1
        }
        guard let own else {
            throw AudioSystemError("MyNotch has no audio process to leave out of its own tap, so it would hear itself")
        }
        let description = try tap.description
        description.processes = [own]
        try tap.setDescription(description)
    }

    /// A headset's microphone is among the aggregate device's inputs; leave it switched off so it never starts (no microphone
    /// indicator, no switch to the call codec). Best effort: the IO proc reads only the tap's streams either way.
    private static func useOnlyTheTap(of device: AudioObjectID, ioProc: AudioDeviceIOProcID, inputStreams count: Int, layout: StreamLayout) {
        guard count > layout.streams else { return }
        // `AudioHardwareIOProcStreamUsage` is the IO proc, a stream count and one on/off flag per input stream, written by hand
        // because its flags are a C array of unknown length.
        let flagsOffset = MemoryLayout<UInt>.size + MemoryLayout<UInt32>.size
        let byteCount = flagsOffset + MemoryLayout<UInt32>.size * count
        let usage = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: MemoryLayout<UInt>.alignment)
        defer { usage.deallocate() }
        usage.storeBytes(of: unsafeBitCast(ioProc, to: UInt.self), as: UInt.self)
        usage.storeBytes(of: UInt32(count), toByteOffset: MemoryLayout<UInt>.size, as: UInt32.self)
        for stream in 0..<count {
            let isTap = stream >= layout.firstInput && stream < layout.firstInput + layout.streams
            usage.storeBytes(of: isTap ? 1 : 0, toByteOffset: flagsOffset + MemoryLayout<UInt32>.size * stream, as: UInt32.self)
        }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyIOProcStreamUsage, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain
        )
        log(AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(byteCount), usage), "switch off the other input streams")
    }

    private static func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else { throw AudioSystemError("could not \(step) (OSStatus \(status))") }
    }

    private static func log(_ status: OSStatus, _ step: String) {
        if status != noErr { logger.error("Could not \(step, privacy: .public) (OSStatus \(status))") }
    }

    private static func logFailure(_ step: String, _ error: any Error) {
        logger.error("Could not \(step, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
}
