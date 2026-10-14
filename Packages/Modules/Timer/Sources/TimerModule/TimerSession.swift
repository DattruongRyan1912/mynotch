import Foundation

/// What the countdown on screen is: its type and, for a reminder, what it reminds of. Kept apart from `TimerModel`,
/// which is only about time, so the model and its tests stay as they were.
nonisolated struct TimerSession: Codable, Equatable, Sendable {
    /// A countdown started without a type (the old quick timer): a reminder with nothing to say.
    static let plain = TimerSession(kind: .reminder, label: "")
    /// The label sits in a strip under the notch, so it is kept to a line's worth.
    static let maxLabelLength = 60

    let kind: TimerKind
    /// Trimmed and cut; empty for everything but a reminder.
    let label: String

    init(kind: TimerKind, label: String) {
        self.kind = kind
        self.label = kind == .reminder ? String(label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxLabelLength)) : ""
    }

    private enum CodingKeys: String, CodingKey { case kind, label }

    /// Goes through `init(kind:label:)`, so a file edited by hand cannot give a task a label. A label that cannot be
    /// read is dropped rather than failing the whole session, so the type survives it.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let label = (try? container.decodeIfPresent(String.self, forKey: .label)) ?? nil
        self.init(kind: try container.decode(TimerKind.self, forKey: .kind), label: label ?? "")
    }

    /// One line saying what is running, for the live activity's list row and VoiceOver.
    var summary: String {
        label.isEmpty ? kind.title : "\(kind.title): \(label)"
    }

    /// The same once it is over.
    var finishedSummary: String {
        switch kind {
        case .reminder: label.isEmpty ? "Hết giờ" : "Hết giờ: \(label)"
        case .task, .rest: "Hết giờ \(kind.title.lowercased())"
        }
    }

    /// What the collapsed notch says beside the glyph once it is over.
    var finishedText: String {
        label.isEmpty ? "Hết giờ" : label
    }
}

/// What `timer.json` holds: the model plus its session. A file written before the types existed holds the bare model
/// and loads as a plain timer, so a countdown running through the update is not lost. A session that cannot be read (a
/// type from a later version, a hand edit) costs the type, never the timer.
nonisolated struct StoredTimer: Codable, Equatable {
    var model: TimerModel
    var session: TimerSession

    init(model: TimerModel, session: TimerSession) {
        self.model = model
        self.session = session
    }

    private enum CodingKeys: String, CodingKey { case model, session }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.model) {
            model = try container.decode(TimerModel.self, forKey: .model)
            session = (try? container.decodeIfPresent(TimerSession.self, forKey: .session)) ?? nil ?? .plain
        } else {
            model = try TimerModel(from: decoder)
            session = .plain
        }
    }
}
