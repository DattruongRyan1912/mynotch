import Foundation

extension CatArt {
    /// Every move as its pictures, and how they are played. Built when asked for, a move at a time: the first appearance of the cat does not
    /// draw a hundred frames at once on the main thread, and a move that is never asked for is never drawn.
    static func animation(for move: CatMove) -> PixelAnimation {
        PixelAnimation(frames: frames(for: move), fps: move.fps, loops: move.loops, advance: move.advance)
    }

    private static func frames(for move: CatMove) -> [PixelFrame] {
        switch move {
        case .sit: sitFrames
        case .blink: blinkFrames
        case .tailSwish: tailSwishFrames
        case .groom: groomFrames
        case .scratch: scratchFrames
        case .lookLeft: [sitting(face: .lookLeft, headDX: -1)]
        case .lookRight: [sitting(face: .lookRight, headDX: 1)]
        case .lookUp: [sitting(face: .lookUp, headDY: -1)]
        case .yawn: yawnFrames
        case .purr: purrFrames
        case .dance: danceFrames
        case .sleep: sleepFrames
        case .loaf: loafFrames
        case .sweat: sweatFrames
        case .lieDown: lieDownFrames
        case .sitDown: sitDownFrames
        case .standUp: standUpFrames
        case .walk: walkFrames
        case .trot: trotFrames
        case .frantic: franticFrames
        case .chase: chaseFrames
        case .pounce: pounceFrames
        case .stretch: stretchFrames
        case .yarn: yarnFrames
        case .peek: peekFrames
        case .startled: startledFrames
        }
    }

    /// The sitting cat with its eyes open, then shut: what a cat that does not move at all (Reduce Motion) shows.
    static let restingFrames = [sit(), sit(face: .blink)]
}
