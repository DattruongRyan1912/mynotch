import Foundation

/// Polyphase FIR filter coefficients specified by ITU-R BS.1770-5 (Annex 2)
/// for 4x oversampling True-Peak continuous peak estimation.
/// 48-tap prototype filter decomposed into 4 polyphase phases of 12 taps each.
public enum TruePeakFIRCoefficients {
    public static let tapsPerPhase: Int = 12
    public static let phaseCount: Int = 4

    /// Phase 0 coefficients (Tap 1 to 12)
    public static let phase0: [Double] = [
        0.0017089843750,
        0.0109863281250,
       -0.0196533203125,
        0.0332031250000,
       -0.0594482421875,
        0.1373291015625,
        0.9721679687500,
       -0.1022949218750,
        0.0476074218750,
       -0.0266113281250,
        0.0148925781250,
       -0.0083007812500
    ]

    /// Phase 1 coefficients (Tap 1 to 12)
    public static let phase1: [Double] = [
       -0.0291748046875,
        0.0292968750000,
       -0.0517578125000,
        0.0891113281250,
       -0.1665039062500,
        0.4650878906250,
        0.7797851562500,
       -0.2003173828125,
        0.1015625000000,
       -0.0582275390625,
        0.0330810546875,
       -0.0189208984375
    ]

    /// Phase 2 coefficients (Tap 1 to 12, exact reversal of Phase 1)
    public static let phase2: [Double] = [
       -0.0189208984375,
        0.0330810546875,
       -0.0582275390625,
        0.1015625000000,
       -0.2003173828125,
        0.7797851562500,
        0.4650878906250,
       -0.1665039062500,
        0.0891113281250,
       -0.0517578125000,
        0.0292968750000,
       -0.0291748046875
    ]

    /// Phase 3 coefficients (Tap 1 to 12, exact reversal of Phase 0)
    public static let phase3: [Double] = [
       -0.0083007812500,
        0.0148925781250,
       -0.0266113281250,
        0.0476074218750,
       -0.1022949218750,
        0.9721679687500,
        0.1373291015625,
       -0.0594482421875,
        0.0332031250000,
       -0.0196533203125,
        0.0109863281250,
        0.0017089843750
    ]

    public static let allPhases: [[Double]] = [phase0, phase1, phase2, phase3]
}
