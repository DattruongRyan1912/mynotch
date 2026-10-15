import Foundation
import Observation

/// A file an action works on: its name for the messages, and where it is now (nil when it has gone).
struct ActionSource: Equatable, Sendable {
    let name: String
    let url: URL?
}

/// Runs one action over its sources, one run at a time, and keeps what the shelf shows of it: progress while it
/// works and a report when it is done. The work itself is the processor's, off the main actor.
@Observable
final class FileActionRunner {
    struct Progress: Equatable {
        let action: FileAction
        /// The sources finished; for a combined action, which has one step, always 0.
        let done: Int
        /// Nil for an action that combines its sources and so has nothing to count.
        let total: Int?
        let current: String?

        /// The file being worked on, and which one of how many it is.
        var detail: String {
            guard let current else { return "" }
            guard let total, total > 1 else { return current }
            return "\(current) · \(min(done + 1, total))/\(total)"
        }
    }

    struct Failure: Equatable {
        let name: String
        let message: String
    }

    struct Report: Equatable {
        let action: FileAction
        var created: [URL] = []
        var failures: [Failure] = []
        /// What a text recognition read, all files together.
        var text: String?
        var textCopied = false
        var wasCancelled = false

        /// One line for the top of the report.
        var summary: String {
            if wasCancelled { return created.isEmpty ? "Đã huỷ" : "Đã huỷ, đã tạo \(created.count) file" }
            var parts: [String] = []
            if let text { parts.append(textCopied ? "Đã chép \(text.count) ký tự" : "Đọc được chữ, nhưng không chép được") }
            if !created.isEmpty { parts.append("Đã tạo \(created.count) file") }
            if !failures.isEmpty { parts.append("\(failures.count) file lỗi") }
            return parts.joined(separator: " · ")
        }
    }

    enum Phase: Equatable {
        case idle
        case running(Progress)
        case finished(Report)
    }

    private(set) var phase = Phase.idle
    /// Changes with every run and every reset, so a run that was reset knows that it is no longer the current one.
    private var generation = 0
    /// The run in progress or the last one, for tests to wait for.
    private(set) var currentRun: Task<Void, Never>?

    var isRunning: Bool {
        if case .running = phase { true } else { false }
    }

    /// Starts the run in the background and returns at once. Ignored while another run is going. `deliver` hears the
    /// files made for each source as soon as they exist, on the main actor.
    func start(
        _ action: FileAction, sources: [ActionSource], processor: FileActionProcessor, pasteboard: any PasteboardWriting,
        deliver: @escaping ([URL]) -> Void
    ) {
        guard let token = begin(action, sources: sources) else { return }
        currentRun = Task { await perform(action, sources: sources, token: token, processor: processor, pasteboard: pasteboard, deliver: deliver) }
    }

    /// `start`, waiting for the end.
    func run(
        _ action: FileAction, sources: [ActionSource], processor: FileActionProcessor, pasteboard: any PasteboardWriting,
        deliver: @escaping ([URL]) -> Void
    ) async {
        guard let token = begin(action, sources: sources) else { return }
        await perform(action, sources: sources, token: token, processor: processor, pasteboard: pasteboard, deliver: deliver)
    }

    /// Asks the run to stop: the file in progress is dropped, the ones already made stay.
    func cancel() { currentRun?.cancel() }

    /// Stops the run and forgets it and its report, for when the shelf stops. What the run was doing may finish its
    /// current step, but it neither reports nor copies anything any more.
    func reset() {
        currentRun?.cancel()
        currentRun = nil
        generation += 1
        phase = .idle
    }

    /// Closes the report. A run that is still going is not closed.
    func dismiss() {
        if case .finished = phase { phase = .idle }
    }

    /// The token of the new run, nil when there is nothing to run or a run is going.
    private func begin(_ action: FileAction, sources: [ActionSource]) -> Int? {
        guard !isRunning, !sources.isEmpty else { return nil }
        generation += 1
        phase = .running(Progress(action: action, done: 0, total: action.combinesSources ? nil : sources.count, current: sources.first?.name))
        return generation
    }

    private func perform(
        _ action: FileAction, sources: [ActionSource], token: Int, processor: FileActionProcessor, pasteboard: any PasteboardWriting,
        deliver: ([URL]) -> Void
    ) async {
        var report = Report(action: action)
        var texts: [String] = []
        do {
            if action.combinesSources {
                try await combine(action, sources, processor, into: &report, deliver: deliver)
            } else {
                for (index, source) in sources.enumerated() {
                    try Task.checkCancellation()
                    if token == generation { phase = .running(Progress(action: action, done: index, total: sources.count, current: source.name)) }
                    guard let url = source.url else {
                        report.failures.append(Failure(name: source.name, message: FileActionError.missing.localizedDescription))
                        continue
                    }
                    do {
                        let output = try await processor.process(action, source: url)
                        if !output.files.isEmpty {
                            report.created += output.files
                            deliver(output.files)
                        }
                        if let text = output.text { texts.append(text) }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        report.failures.append(Failure(name: source.name, message: error.localizedDescription))
                    }
                }
            }
        } catch {
            report.wasCancelled = true
        }
        guard token == generation else { return }
        // What was read before a cancel is not all of it, so it is not copied over what the user had.
        if !report.wasCancelled, !texts.isEmpty {
            let text = texts.joined(separator: "\n\n")
            report.text = text
            report.textCopied = pasteboard.write(text)
        }
        phase = .finished(report)
    }

    /// Sources that are gone are reported by name and left out; when the action fails as a whole there is one error.
    private func combine(
        _ action: FileAction, _ sources: [ActionSource], _ processor: FileActionProcessor, into report: inout Report, deliver: ([URL]) -> Void
    ) async throws {
        let missing = sources.filter { $0.url == nil }
        report.failures = missing.map { Failure(name: $0.name, message: FileActionError.missing.localizedDescription) }
        let present = sources.compactMap(\.url)
        guard !present.isEmpty else { return }
        do {
            let combined = try await processor.combine(action, sources: present)
            report.created = combined.files
            deliver(combined.files)
            report.failures += combined.skipped.map { skipped in
                Failure(name: sources.first { $0.url == skipped.source }?.name ?? skipped.source.lastPathComponent, message: skipped.error.localizedDescription)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let name = present.count == 1 ? (sources.first { $0.url != nil }?.name ?? "") : "\(present.count) file"
            report.failures.append(Failure(name: name, message: error.localizedDescription))
        }
    }
}
