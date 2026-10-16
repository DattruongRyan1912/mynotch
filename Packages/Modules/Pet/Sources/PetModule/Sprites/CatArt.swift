import Foundation

/// What the cat does, as pictures. Each frame is 20 x 16 pixels, drawn by hand as text and put together from a few pieces (a head, a
/// body, a tail, a paw), so that the head of the walking cat is the head of the sitting one. They face right; the cat that walks left is
/// the same frames mirrored.
nonisolated enum CatArt {
    static let width = 20
    static let height = 16

    /// A cat the colour of marmalade with a dark brown line round it, so it reads on black, on light glass, and on a wallpaper.
    static let palette = PixelPalette(colors: [
        "K": 0x4A2A17,  // outline
        "O": 0xF0A14E,  // coat
        "D": 0xC4702A,  // stripes, the legs on the far side
        "W": 0xFDECD2,  // chest, paws, muzzle
        "P": 0xF590B0,  // nose, ears, tongue
        "E": 0x161212,  // eyes
        "Z": 0xA8D6FF,  // sleep
        "H": 0xFF5C8A,  // hearts
        "N": 0xFFD23F,  // music
        "S": 0xCFD8E3,  // a run's streaks
    ])

    // MARK: Pieces

    private static let headOpen = [
        ".K....K.",
        "KPK..KPK",
        "KOOOOOOK",
        "KOEOOEOK",
        "KOEOOEOK",
        "KOWPPWOK",
        ".KKKKKK.",
    ]
    private static let headBlink = [
        ".K....K.",
        "KPK..KPK",
        "KOOOOOOK",
        "KOOOOOOK",
        "KOKOOKOK",
        "KOWPPWOK",
        ".KKKKKK.",
    ]
    private static let headHappy = [
        ".K....K.",
        "KPK..KPK",
        "KOOOOOOK",
        "KOKOOKOK",
        "KPOOOOPK",
        "KOWPPWOK",
        ".KKKKKK.",
    ]
    private static let headYawn = [
        ".K....K.",
        "KPK..KPK",
        "KOOOOOOK",
        "KOKOOKOK",
        "KOOKKOOK",
        "KOOPPOOK",
        ".KKKKKK.",
    ]
    private static let headStartled = [
        ".K....K.",
        "KPK..KPK",
        "KOOOOOOK",
        "KEEOOEEK",
        "KEEOOEEK",
        "KOOPPOOK",
        ".KKKKKK.",
    ]

    private static let torsoWalk = [
        ".KKKKKKKKKK.",
        "KOODOODOOOOK",
        "KOOOOOOOOOOK",
        "KOOOOOOOOWWK",
        ".KOOOOOOOOK.",
    ]
    /// Legs under `torsoWalk`: the last row has a paw only on the legs that are down.
    private static let legsTop = ["DDOO....DDOO", "DDOO....DDOO"]
    private static let pawsStep0 = "WW........WW"
    private static let pawsStep1 = "WWWW....WWWW"
    private static let pawsStep2 = "..WW....WW.."

    private static let tailUp = [
        "DD..",
        "OD..",
        ".OO.",
        ".OO.",
        "..OO",
        "..OO",
        "..OO",
        "..OO",
    ]
    private static let tailMid = [
        "....",
        "....",
        "DD..",
        "OO..",
        "OO..",
        ".OO.",
        "..OO",
        "..OO",
    ]
    private static let tailLow = [
        "....",
        "....",
        "....",
        "....",
        "....",
        "....",
        "DD..",
        "OOOO",
    ]

    private static let torsoSit = [
        "....KKKK...",
        "...KOOODK..",
        "..KOODOOOK.",
        ".KOOOOOOOWK",
        "KODOOOOOWWK",
        "KOOOOOOOWWK",
        "KOOOOOOOWWK",
        "KOOOOOOKWWK",
        "KKKKKKKKKKK",
    ]
    private static let tailSitDown = [
        "........",
        "........",
        "........",
        "........",
        "........",
        "........",
        "........",
        "KOOOOO..",
        "DDDDDD..",
    ]

    private static let pawLifted = [
        "WW",
        "WW",
        "KK",
    ]
    private static let tongue = [
        "P",
    ]

    private static let loaf = [
        "..KKKKKKKK..",
        ".KOODOODOOK.",
        "KODOOOOOOOOK",
        "KOOOOOOOOOOK",
        ".KKKKKKKKKK.",
    ]
    private static let tailLoaf = [
        "KKKK",
        "DOOK",
        "DDDD",
    ]

    private static let zed = [
        "ZZZZ",
        "..Z.",
        ".Z..",
        "ZZZZ",
    ]
    private static let heart = [
        ".H.H.",
        "HHHHH",
        ".HHH.",
        "..H..",
    ]
    private static let note = [
        ".NN",
        ".N.",
        "NN.",
        "NN.",
    ]
    private static let streak = [
        "SSS",
    ]

    // MARK: Building

    private static func piece(_ rows: [String]) -> PixelFrame {
        do { return try PixelFrame(rows: rows, palette: palette) } catch { fatalError("The cat's art is malformed: \(error)") }
    }

    private static var blank: PixelFrame { PixelFrame(width: width, height: height) }

    private struct Placed {
        let rows: [String]
        let x: Int
        let y: Int
    }

    /// The pieces drawn from the back to the front, on a clear frame.
    private static func frame(_ pieces: [Placed]) -> PixelFrame {
        pieces.reduce(blank) { $0.drawing(piece($1.rows), atX: $1.x, y: $1.y) }
    }

    /// A walking cat: its tail, its body with the legs of this step, its head, all `lift` pixels higher than the ground.
    private static func walking(paws: String, tail: [String], head: [String], lift: Int = 0, streaks: Bool = false) -> PixelFrame {
        var pieces = [
            Placed(rows: tail, x: 0, y: 3 - lift),
            Placed(rows: torsoWalk + legsTop + [paws], x: 2, y: 8 - lift),
            Placed(rows: head, x: 12, y: 3 - lift),
        ]
        if streaks {
            pieces.append(Placed(rows: streak, x: 0, y: 11 - lift))
            pieces.append(Placed(rows: streak, x: 1, y: 14 - lift))
        }
        return frame(pieces)
    }

    private static func sitting(tail: [String], head: [String], dy: Int = 0, extras: [Placed] = []) -> PixelFrame {
        frame([
            Placed(rows: tail, x: 0, y: 7 + dy),
            Placed(rows: torsoSit, x: 4, y: 7 + dy),
            Placed(rows: head, x: 12, y: 3 + dy),
        ] + extras)
    }

    private static func curled(breath: Int, extras: [Placed]) -> PixelFrame {
        frame([
            Placed(rows: loaf, x: 0, y: 10 + breath),
            Placed(rows: tailLoaf, x: 0, y: 13),
            Placed(rows: headBlink, x: 12, y: 8 + breath),
        ] + extras)
    }

    // MARK: Animations

    /// The cat sitting with its tail down, flicking it now and then.
    static let sit = PixelAnimation(
        frames: [
            sitting(tail: tailSitDown, head: headOpen), sitting(tail: tailSitDown, head: headOpen),
            sitting(tail: tailSitDown, head: headOpen), sitting(tail: tailSitDown, head: headOpen),
            sitting(tail: tailUp, head: headOpen), sitting(tail: tailSitDown, head: headOpen),
        ],
        fps: 4
    )

    /// Eyes shut for a moment: held while it lasts.
    static let blink = PixelAnimation(frames: [sitting(tail: tailSitDown, head: headBlink)], fps: 4)

    static let walk = PixelAnimation(
        frames: [
            walking(paws: pawsStep0, tail: tailUp, head: headOpen),
            walking(paws: pawsStep1, tail: tailMid, head: headOpen),
            walking(paws: pawsStep2, tail: tailUp, head: headOpen),
            walking(paws: pawsStep1, tail: tailMid, head: headOpen),
        ],
        fps: 8
    )

    /// Legs gathered, then all out of the ground, with streaks behind it.
    static let run = PixelAnimation(
        frames: [
            walking(paws: pawsStep0, tail: tailLow, head: headOpen, streaks: true),
            walking(paws: "............", tail: tailLow, head: headOpen, lift: 1, streaks: true),
            walking(paws: pawsStep2, tail: tailLow, head: headOpen, streaks: true),
            walking(paws: "............", tail: tailLow, head: headOpen, lift: 1, streaks: true),
        ],
        fps: 12
    )

    static let lick = PixelAnimation(
        frames: [
            sitting(tail: tailSitDown, head: headBlink),
            sitting(tail: tailSitDown, head: headBlink, extras: [Placed(rows: pawLifted, x: 16, y: 10)]),
            sitting(tail: tailSitDown, head: headBlink, extras: [Placed(rows: pawLifted, x: 16, y: 8)]),
            sitting(tail: tailSitDown, head: headBlink, extras: [Placed(rows: pawLifted, x: 16, y: 9)]),
        ],
        fps: 6
    )

    static let yawn = PixelAnimation(
        frames: [
            sitting(tail: tailSitDown, head: headOpen),
            sitting(tail: tailSitDown, head: headBlink),
            sitting(tail: tailSitDown, head: headYawn),
            sitting(tail: tailSitDown, head: headYawn),
            sitting(tail: tailSitDown, head: headBlink),
        ],
        fps: 4
    )

    /// Curled up, breathing, a z rising over it and another after it.
    static let sleep = PixelAnimation(
        frames: [
            curled(breath: 0, extras: [Placed(rows: zed, x: 14, y: 4)]),
            curled(breath: 0, extras: [Placed(rows: zed, x: 15, y: 3), Placed(rows: zed, x: 11, y: 5)]),
            curled(breath: 1, extras: [Placed(rows: zed, x: 16, y: 1), Placed(rows: zed, x: 12, y: 3)]),
            curled(breath: 1, extras: [Placed(rows: zed, x: 13, y: 1)]),
        ],
        fps: 2
    )

    /// Down to crouch, up, at the top of the jump with the tail up, down again.
    static let startled = PixelAnimation(
        frames: [
            sitting(tail: tailSitDown, head: headStartled, dy: 1),
            sitting(tail: tailUp, head: headStartled, dy: -2),
            sitting(tail: tailUp, head: headStartled, dy: -3),
            sitting(tail: tailSitDown, head: headStartled, dy: 0),
        ],
        fps: 8
    )

    /// Bobbing, with a note drifting up behind its head.
    static let dance = PixelAnimation(
        frames: [
            sitting(tail: tailUp, head: headHappy, extras: [Placed(rows: note, x: 7, y: 3)]),
            sitting(tail: tailMid, head: headHappy, dy: -1, extras: [Placed(rows: note, x: 8, y: 2)]),
            sitting(tail: tailUp, head: headHappy, extras: [Placed(rows: note, x: 6, y: 1)]),
            sitting(tail: tailMid, head: headHappy, dy: -1, extras: [Placed(rows: note, x: 7, y: 0)]),
        ],
        fps: 6
    )

    /// Eyes shut with pleasure, a heart drifting up behind its head.
    static let purr = PixelAnimation(
        frames: [
            sitting(tail: tailUp, head: headHappy, extras: [Placed(rows: heart, x: 7, y: 3)]),
            sitting(tail: tailMid, head: headHappy, extras: [Placed(rows: heart, x: 8, y: 2)]),
            sitting(tail: tailUp, head: headHappy, extras: [Placed(rows: heart, x: 6, y: 1)]),
            sitting(tail: tailMid, head: headHappy, extras: [Placed(rows: heart, x: 7, y: 0)]),
        ],
        fps: 6
    )

    /// The sitting cat with its eyes open, then shut: what a cat that does not move at all (Reduce Motion) shows.
    static let restingFrames = [sit.frames[0], blink.frames[0]]

    /// Every animation by what the cat is doing.
    static func animation(for pose: CatPose) -> PixelAnimation {
        switch pose {
        case .sit: sit
        case .blink: blink
        case .walk: walk
        case .run: run
        case .lick: lick
        case .yawn: yawn
        case .sleep: sleep
        case .startled: startled
        case .dance: dance
        case .purr: purr
        }
    }
}
