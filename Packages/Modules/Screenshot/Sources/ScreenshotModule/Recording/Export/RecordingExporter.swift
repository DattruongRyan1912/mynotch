import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import os

/// Why an export did not give a file. Whatever the reason, no half-written file is left behind.
nonisolated enum RecordingExportError: Error, Equatable, Sendable {
    /// The person cancelled.
    case cancelled
    /// The folder for the file could not be made or written to.
    case cannotWrite(String)
    case composition(RecordingCompositionError)
    /// The reader or the encoder gave up; the text is the system's.
    case failed(String)

    /// One line for the editor, in Vietnamese.
    var message: String {
        switch self {
        case .cancelled: "Đã huỷ xuất video"
        case .cannotWrite: "Không ghi được file vào thư mục Movies/MyNotch"
        case .composition(let error): error.message
        case .failed: "Không xuất được video. Thử mức xuất khác hoặc kiểm tra dung lượng ổ đĩa"
        }
    }
}

/// An exported file.
nonisolated struct RecordingExportResult: Equatable, Sendable {
    var url: URL
    var plan: ExportPlan
    /// Seconds, of the edited video.
    var duration: TimeInterval
}

/// Writes a recording as an MP4: the composition (cuts, zoom, click rings) read frame by frame at a constant frame rate and
/// encoded with the level's settings, with the sound mixed down to one AAC track. The file is written under a hidden name and
/// moved into place only when it is whole, so a cancel, a failure or a crash never leaves something that looks finished.
nonisolated enum RecordingExporter {
    /// `~/Movies/MyNotch/`, where exports go unless the caller says otherwise.
    static var defaultDirectory: URL {
        (FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser)
            .appending(path: "MyNotch", directoryHint: .isDirectory)
    }

    /// "Bản quay MyNotch 2026-10-18 14.30.00.mp4", from when the recording was made.
    static func fileName(for project: RecordingProject, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Bản quay MyNotch \(formatter.string(from: project.createdAt)).mp4"
    }

    /// What the sound of each track is played at: the voice on top of what the computer plays when both were recorded, and
    /// at full level when there is only one, so two tracks added together cannot clip a loud voice.
    static func volumes(for kinds: [AudioTrackKind]) -> [Float] {
        let both = kinds.contains(.microphone) && kinds.contains(.system)
        return kinds.map { both && $0 == .system ? 0.6 : 1 }
    }

    /// Exports `project` at `level` into `directory` (made when missing) and returns the file. `progress` is told how far the
    /// export is, from 0 to 1, on a background queue. Cancelling the task cancels the export and throws `.cancelled`.
    @MainActor
    static func export(
        project: RecordingProject, folder: URL, activity: ActivityTrack, level: ExportLevel, into directory: URL,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> RecordingExportResult {
        let plan = level.plan(
            forVideoOfSize: CGSize(width: project.region.pixelWidth, height: project.region.pixelHeight), fps: project.fps
        )
        let built: RecordingComposition
        do {
            built = try await RecordingComposition.make(
                project: project, folder: folder, activity: activity, options: .init(renderSize: plan.size, frameRate: plan.frameRate)
            )
        } catch {
            throw RecordingExportError.composition(error)
        }
        if Task.isCancelled { throw RecordingExportError.cancelled }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw RecordingExportError.cannotWrite(error.localizedDescription)
        }
        removeAbandonedWork(in: directory)
        // A folder of its own: the encoder makes helper files beside the one it writes, and removing the folder removes them all,
        // however late it makes them.
        let work = directory.appending(path: "\(workPrefix)\(UUID().uuidString)", directoryHint: .isDirectory)
        let partial = work.appending(path: "export.mp4")
        let kinds = soundKinds(of: project)
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: work) }
            let job = try ExportJob(
                composition: built.composition, videoComposition: built.videoComposition, videoTrack: built.videoTrack,
                audioTracks: built.audioTracks, volumes: kinds.count == built.audioTracks.count ? volumes(for: kinds) : [],
                plan: plan, duration: built.duration, destination: partial, progress: progress
            )
            try await withTaskCancellationHandler { try await job.run() } onCancel: { job.cancel() }
            if Task.isCancelled { throw RecordingExportError.cancelled }
            let final = try move(partial, into: directory, named: fileName(for: project))
            return RecordingExportResult(url: final, plan: plan, duration: built.duration)
        } catch let error as RecordingExportError {
            throw error
        } catch {
            throw RecordingExportError.failed(error.localizedDescription)
        }
    }

    /// A hidden folder in the destination, where a file is written until it is whole.
    static let workPrefix = ".MyNotch-export-"

    /// What an export that was killed halfway (a crash, a power cut) leaves: a hidden folder nobody will look in, with a big
    /// half-written file in it. Folders of ours that nothing has touched for an hour are removed; one that is being written
    /// is touched all the time.
    static func removeAbandonedWork(in directory: URL, now: Date = Date(), olderThan age: TimeInterval = 3_600) {
        let manager = FileManager.default
        for url in (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] where url.lastPathComponent.hasPrefix(workPrefix) {
            // The newest of the folder and what is in it: a file being written does not change the folder's own date.
            let touched = [url] + ((try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
            let newest = touched.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }.max()
            if let newest, now.timeIntervalSince(newest) > age { try? manager.removeItem(at: url) }
        }
    }

    /// The sound sources in the order the segments' tracks are laid out: the microphone, then the system's sound.
    private static func soundKinds(of project: RecordingProject) -> [AudioTrackKind] {
        (project.hasMicrophone ? [AudioTrackKind.microphone] : []) + (project.hasSystemAudio ? [.system] : [])
    }

    /// Puts the finished file where it belongs. A file already there is the person's, so the new one takes the next free name:
    /// "… 2.mp4", "… 3.mp4".
    private static func move(_ partial: URL, into directory: URL, named name: String) throws -> URL {
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var number = 1
        while true {
            let candidate = directory.appending(path: number == 1 ? name : "\(base) \(number).\(ext)")
            do {
                // Moving onto an existing file fails, so a file is never replaced, not even by a race.
                try FileManager.default.moveItem(at: partial, to: candidate)
                return candidate
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                number += 1
            } catch {
                throw RecordingExportError.cannotWrite(error.localizedDescription)
            }
        }
    }
}

/// One export: a reader that pulls the composition's frames and sound, and a writer that encodes them. Everything happens on
/// one serial queue, which is the only place its state is touched.
private nonisolated final class ExportJob: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MyNotch.RecordingExport")
    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private let videoOutput: AVAssetReaderVideoCompositionOutput
    private let videoInput: AVAssetWriterInput
    private var audio: (output: AVAssetReaderAudioMixOutput, input: AVAssetWriterInput)?
    private let duration: TimeInterval
    private let progress: @Sendable (Double) -> Void

    private var continuation: CheckedContinuation<Void, any Error>?
    /// Set the moment `cancel` is called, from any thread, so the copying notices before the next frame instead of when its
    /// batch of frames ends.
    private let cancelRequested = OSAllocatedUnfairLock(initialState: false)
    private var hasBegun = false
    private var unfinishedInputs = 0
    private var reported = 0.0

    init(
        composition: AVComposition, videoComposition: AVVideoComposition, videoTrack: AVCompositionTrack,
        audioTracks: [AVCompositionTrack], volumes: [Float], plan: ExportPlan, duration: TimeInterval, destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        self.duration = duration
        self.progress = progress
        let reader = try AVAssetReader(asset: composition), writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        self.reader = reader
        self.writer = writer

        videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [videoTrack], videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        videoOutput.videoComposition = videoComposition
        videoOutput.alwaysCopiesSampleData = false
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: plan.videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        if reader.canAdd(videoOutput), writer.canAdd(videoInput) {
            reader.add(videoOutput)
            writer.add(videoInput)
        }

        if !audioTracks.isEmpty {
            let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
                AVSampleRateKey: RecordingMedia.sampleRate, AVNumberOfChannelsKey: 2,
            ])
            if volumes.count == audioTracks.count {
                let mix = AVMutableAudioMix()
                mix.inputParameters = zip(audioTracks, volumes).map { track, volume in
                    let parameters = AVMutableAudioMixInputParameters(track: track)
                    parameters.setVolume(volume, at: .zero)
                    return parameters
                }
                output.audioMix = mix
            }
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: plan.audioSettings)
            input.expectsMediaDataInRealTime = false
            if reader.canAdd(output), writer.canAdd(input) {
                reader.add(output)
                writer.add(input)
                audio = (output, input)
            }
        }
        // Players start streaming before the whole file is there, which is what a chat app does with it too.
        writer.shouldOptimizeForNetworkUse = true
    }

    func run() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue.async { self.begin(continuation) }
        }
    }

    /// May be called from any thread, at any time, any number of times.
    func cancel() {
        cancelRequested.withLock { $0 = true }
        queue.async { if self.hasBegun { self.stop(with: RecordingExportError.cancelled) } }
    }

    // MARK: On the queue

    private func begin(_ continuation: CheckedContinuation<Void, any Error>) {
        self.continuation = continuation
        hasBegun = true
        if cancelRequested.withLock({ $0 }) { return stop(with: RecordingExportError.cancelled) }
        guard reader.startReading() else {
            return stop(with: RecordingExportError.failed(reader.error?.localizedDescription ?? "reader"))
        }
        guard writer.startWriting() else {
            return stop(with: RecordingExportError.failed(writer.error?.localizedDescription ?? "writer"))
        }
        writer.startSession(atSourceTime: .zero)
        unfinishedInputs = audio == nil ? 1 : 2
        videoInput.requestMediaDataWhenReady(on: queue) { [self] in copy(from: videoOutput, to: videoInput, isVideo: true) }
        audio?.input.requestMediaDataWhenReady(on: queue) { [self] in
            if let audio { copy(from: audio.output, to: audio.input, isVideo: false) }
        }
    }

    private func copy(from output: AVAssetReaderOutput, to input: AVAssetWriterInput, isVideo: Bool) {
        while continuation != nil, input.isReadyForMoreMediaData {
            if cancelRequested.withLock({ $0 }) { return stop(with: RecordingExportError.cancelled) }
            guard let sample = output.copyNextSampleBuffer() else {
                // The end of what there is, or the reader failed or was cancelled: `reader.status` says which.
                input.markAsFinished()
                unfinishedInputs -= 1
                if reader.status == .failed {
                    stop(with: RecordingExportError.failed(reader.error?.localizedDescription ?? "reader"))
                } else if unfinishedInputs == 0, reader.status == .completed {
                    finish()
                }
                return
            }
            guard input.append(sample) else {
                stop(with: RecordingExportError.failed(writer.error?.localizedDescription ?? "writer"))
                return
            }
            if isVideo { report(upTo: sample.presentationTimeStamp.seconds) }
        }
    }

    private func report(upTo time: TimeInterval) {
        guard duration > 0 else { return }
        let fraction = min(max(time / duration, 0), 1)
        // A hundred reports are plenty for a bar.
        guard fraction - reported >= 0.01 else { return }
        reported = fraction
        progress(fraction)
    }

    private func finish() {
        writer.finishWriting { [self] in
            queue.async {
                guard self.continuation != nil else { return }
                if self.writer.status == .completed {
                    self.progress(1)
                    self.resolve(nil)
                } else {
                    self.resolve(RecordingExportError.failed(self.writer.error?.localizedDescription ?? "writer"))
                }
            }
        }
    }

    /// Ends the job with `error`, stopping what is running. The first ending wins.
    private func stop(with error: any Error) {
        guard continuation != nil else { return }
        if reader.status == .reading { reader.cancelReading() }
        if writer.status == .writing || writer.status == .unknown { writer.cancelWriting() }
        resolve(error)
    }

    private func resolve(_ error: (any Error)?) {
        guard let continuation else { return }
        self.continuation = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }
}
