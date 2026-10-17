import Foundation

/// What the probe says before it runs and about what it found, in words.
nonisolated enum FanProbePresentation {
    static let buttonTitle = "Thử điều khiển quạt (10 giây)"

    static let confirmationTitle = "Thử điều khiển quạt?"

    /// Exactly what is about to happen: the numbers, the time, the noise, and that it ends with the fans back to Apple.
    static let confirmationMessage = """
        MyNotch nhờ helper (quyền root) đổi tốc độ quạt trong khoảng 10 giây, hai lần, mỗi lần khoảng 5 giây. Lần 1 đặt một "sàn" tốc \
        độ cho quạt 1, lần 2 đặt tốc độ thủ công cho mọi quạt, cùng mức cao hơn tốc độ hiện tại của quạt 1 khoảng 1500 vòng/phút (hoặc \
        60% tốc độ tối đa của quạt).

        Quạt có thể ồn hơn trong vài giây. Sau mỗi lần helper trả quạt về chế độ tự động của Apple, và nếu một cảm biến nóng quá 95 °C \
        helper đưa quạt lên tối đa. Không chạy khi Macs Fan Control đang mở.
        """

    static let confirmButton = "Thử trong 10 giây"

    static func verdict(_ outcome: FanProbeOutcome) -> String {
        switch outcome.verdict {
        case .notRun: "Chưa thử."
        case .floor: "Dùng sàn tốc độ: Apple vẫn giữ chế độ tự động, MyNotch chỉ nâng mức tối thiểu."
        case .forced: "Dùng tốc độ thủ công, không bao giờ thấp hơn tốc độ của Apple."
        case .none: "Không cách nào dùng được trên máy này."
        case .inconclusive: outcome.note.isEmpty ? "Chưa kết luận được." : outcome.note
        }
    }

    /// How long the SMC took to apply the mode of a manual speed, as the helper measured it.
    static func modeLatency(_ milliseconds: Int) -> String { "chế độ nhận sau \(milliseconds) ms" }

    /// One line for each way that was tried.
    static func lines(_ outcome: FanProbeOutcome) -> [String] {
        outcome.trials.map { trial in
            let name = trial.mechanism == .floor ? "Sàn tốc độ" : "Tốc độ thủ công"
            guard trial.accepted else {
                return "\(name): helper không nhận lệnh\(trial.detail.isEmpty ? "" : " (\(trial.detail))")."
            }
            let change = trial.changed
                ? "tốc độ lên \(Int(trial.peakRPM)) từ \(Int(trial.baselineRPM))" : "tốc độ không đổi (\(Int(trial.peakRPM)) từ \(Int(trial.baselineRPM)))"
            return "\(name): yêu cầu \(Int(trial.requestedRPM)), \(change); giữ đúng mức đã đặt: \(trial.heldAsAsked ? "có" : "không"); trả về tự động: \(trial.restored ? "được" : "không rõ")\(trial.detail.isEmpty ? "" : "; \(trial.detail)")."
        }
    }
}
