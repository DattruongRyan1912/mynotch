/// How worrying a reading is: green, orange or red wherever the module marks one (a dot, a line, a number, a bar). A die
/// temperature takes its tone from round numbers a person can reason about, since Apple does not publish the temperatures at
/// which an M1 Pro slows down; the memory pressure maps one to one.
nonisolated enum Tone: Equatable, Sendable {
    case normal
    case caution
    case critical

    static let cautionFrom = 70.0
    static let criticalFrom = 90.0

    init(celsius: Double) {
        self = celsius >= Self.criticalFrom ? .critical : celsius >= Self.cautionFrom ? .caution : .normal
    }

    init(_ pressure: MemoryPressure) {
        switch pressure {
        case .normal: self = .normal
        case .warning: self = .caution
        case .critical: self = .critical
        }
    }
}
