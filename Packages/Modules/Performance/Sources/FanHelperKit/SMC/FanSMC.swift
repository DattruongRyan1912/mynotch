/// The fan keys of the SMC, read-only: `FNum` and, for each fan, `F<N>Ac` (actual RPM), `F<N>Mn`, `F<N>Mx`, and when it has them
/// `F<N>Md` (mode) and `F<N>Tg` (target).
public enum FanSMC {
    /// Fans beyond this many are not looked for; no Mac has them, and a corrupt count must not make the helper ask for hundreds.
    static let mostFans = 8

    /// A fan missing its speed or limits is left out; one missing only its mode or target is kept with them unknown.
    public static func readFans(on channel: any SMCChannel) -> [FanHelperFan] {
        guard let count = number("FNum", on: channel) else { return [] }
        return (0..<min(Int(count), mostFans)).compactMap { index in
            guard let rpm = float("F\(index)Ac", on: channel), let minRPM = float("F\(index)Mn", on: channel),
                  let maxRPM = float("F\(index)Mx", on: channel)
            else { return nil }
            return FanHelperFan(
                index: index, rpm: rpm, minRPM: minRPM, maxRPM: maxRPM,
                mode: number("F\(index)Md", on: channel) ?? FanHelperFan.unknown,
                target: float("F\(index)Tg", on: channel) ?? FanHelperFan.unknown
            )
        }
    }

    private static func number(_ key: String, on channel: any SMCChannel) -> Double? {
        guard let info = channel.info(of: key), let bytes = channel.bytes(of: key, info: info) else { return nil }
        return SMCValue.number(type: info.type, bytes: bytes)
    }

    private static func float(_ key: String, on channel: any SMCChannel) -> Double? {
        guard let info = channel.info(of: key), info.type == "flt " else { return nil }
        return number(key, on: channel)
    }
}
