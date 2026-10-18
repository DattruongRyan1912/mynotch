import Foundation

extension CapybaraArt {
    /// Every move as its pictures, and how they are played. Built when asked for, a move at a time, as the cat's are.
    static func animation(for move: CapybaraMove) -> PixelAnimation {
        PixelAnimation(frames: frames(for: move), fps: move.fps, loops: move.loops, advance: move.advance)
    }

    private static func frames(for move: CapybaraMove) -> [PixelFrame] {
        switch move {
        case .sit: [sit(), sit(), sit(breath: 1), sit(breath: 1)]
        case .blink: [sit(face: .blink)]
        case .doze: dozeFrames
        case .hold: holdFrames
        case .peel: peelFrames
        case .chew: chewFrames
        case .happy: happyFrames
        case .sweat: sweatFrames
        case .turn: turnFrames
        case .watch: [turnFrames[2]]
        case .turnBack: Array(turnFrames.reversed())
        case .lie: [lying(), lying(breath: 1)]
        case .sleep: sleepFrames
        case .lieDown: lieDownFrames
        case .sitUp: Array(lieDownFrames.reversed())
        case .walk: walkFrames
        case .sitDown: sitDownFrames
        case .standUp: Array(sitDownFrames.reversed())
        case .climbIn: climbInFrames
        case .climbOut: Array(climbInFrames.reversed())
        case .soak: [soak(), soak(), soak(), soak(face: .blink)]
        case .soakOrange: (0..<4).map { soak(face: $0 == 3 ? .blink : .half, withOrange: true, breath: $0 >= 2 ? 1 : 0) }
        case .soakHappy: soakHappyFrames
        case .soakSink: soakSinkFrames
        case .soakDeep: soakDeepFrames
        case .soakRise: Array(soakSinkFrames.reversed())
        }
    }

    /// The capybara sitting with its eyes open, then shut: what one that does not move at all (Reduce Motion) shows.
    static var restingFrames: [PixelFrame] { [sit(), sit(face: .blink)] }

    /// The sitting capybara in profile, its head up over its shoulders. `sunk` is how many rows lower the whole of it is drawn, which in the
    /// tub is how far down in the water it is.
    static func sit(breath: Int = 0, face: Face = .open, sunk: Int = 0, extras: (inout CatCanvas) -> Void = { _ in }) -> PixelFrame {
        capybara(body: seated, legs: [], sitting: true, head: (16, 4 + breath), face: face, joined: 5, lift: -sunk, extras: extras)
    }

    /// Lying down, its chin on the floor.
    static func lying(breath: Int = 0, face: Face = .open, extras: (inout CatCanvas) -> Void = { _ in }) -> PixelFrame {
        let body = [Barrel(left: 1.5, right: 21, top: 14.5 - Double(breath) * 0.8, bottom: 20.5, radius: 3)]
        return capybara(body: body, legs: [], head: (16, 10 - breath), face: face, joined: 4, extras: extras)
    }

    // MARK: Walking

    static var walkFrames: [PixelFrame] {
        (0..<6).map { index in
            capybara(legs: legs(phase: Double(index) / 6), head: (16, index % 2 == 1 ? 7 : 6))
        }
    }

    // MARK: Between standing, sitting and lying

    /// Down on its haunches, about to sit or to spring.
    static var crouch: PixelFrame {
        capybara(
            body: [Barrel(left: 1.5, right: 20, top: 9.5, bottom: 18.5, radius: 4.5)],
            legs: [
                CatArt.Leg(hip: (5, 17.5), foot: (4, 20), far: true), CatArt.Leg(hip: (15.5, 17.5), foot: (16.5, 20), far: true),
                CatArt.Leg(hip: (7.5, 17.5), foot: (6.5, 20)), CatArt.Leg(hip: (18, 17.5), foot: (19, 20)),
            ],
            head: (16, 7)
        )
    }

    static var sitDownFrames: [PixelFrame] {
        let rear = capybara(
            body: [
                Barrel(left: 1.5, right: 16, top: 13.5, bottom: 20.5, radius: 3.6),
                Barrel(left: 13.5, right: 20.5, top: 9, bottom: 19, radius: 3),
            ],
            legs: [CatArt.Leg(hip: (16.5, 17), foot: (16.5, 20), far: true), CatArt.Leg(hip: (19, 17), foot: (19, 20))],
            head: (16, 5), joined: 5
        )
        return [capybara(), crouch, rear, sit()]
    }

    static var lieDownFrames: [PixelFrame] {
        let low = capybara(
            body: [
                Barrel(left: 1.5, right: 16, top: 13.5, bottom: 20.5, radius: 3.6),
                Barrel(left: 13.5, right: 20.5, top: 11.5, bottom: 20.5, radius: 3),
            ],
            legs: [], sitting: true, head: (16, 6), joined: 5
        )
        let lower = capybara(
            body: [Barrel(left: 1.5, right: 21, top: 14, bottom: 20.5, radius: 3)], legs: [], head: (16, 8), face: .half, joined: 4
        )
        return [sit(), low, lower, lying()]
    }

    // MARK: Faces and small things

    /// Eyes half shut, the head nodding down and coming up with a start, a bubble growing at the nose and bursting.
    static var dozeFrames: [PixelFrame] {
        let bubbles: [[String]?] = [
            nil, ["QQ", "QQ"], [".Q.", "QIQ", ".Q."], [".QQ.", "QIIQ", "QIIQ", ".QQ."], ["Q.Q", ".Q.", "Q.Q"], nil, nil, nil,
        ]
        let nods = [0, 1, 2, 3, 0, 0, 1, 1]
        let faces: [Face] = [.half, .half, .half, .half, .open, .half, .half, .half]
        return (0..<8).map { index in
            capybara(body: seated, legs: [], sitting: true, head: (16, 4 + nods[index]), face: faces[index], joined: 5) { canvas in
                if let bubble = bubbles[index] { canvas.piece(bubble, x: bubble.count == 4 ? 26 : 27, y: 7 + nods[index] - bubble.count / 2) }
            }
        }
    }

    static func zeds(_ index: Int) -> [(x: Int, y: Int)] {
        [[(23, 7)], [(23, 6), (26, 2)], [(26, 3)], [(23, 7), (26, 4)]][index]
    }

    static var sleepFrames: [PixelFrame] {
        (0..<4).map { index in
            lying(breath: index % 2, face: .sleep) { canvas in
                for zed in zeds(index) { canvas.piece(CatArt.zed, x: zed.x, y: zed.y) }
            }
        }
    }

    static var happyFrames: [PixelFrame] {
        (0..<4).map { index in
            sit(breath: index % 2, face: .happy) { canvas in canvas.piece(CatArt.heart, x: 9 + index % 2, y: 9 - index * 2) }
        }
    }

    static var sweatFrames: [PixelFrame] {
        let drops = [2, 4, 6, 8]
        return (0..<4).map { index in
            sit(breath: index % 2, face: index == 3 ? .blink : .squint) { canvas in canvas.piece(CatArt.sweat, x: 13, y: drops[index]) }
        }
    }

    // MARK: Turning its head

    /// The head seen from the front, from the three quarters, and in profile: the neck turns slowly towards whoever is there.
    static func frontHead(_ turn: Double) -> [String] {
        let front = [
            ".KK.....KK.",
            "KPPKKKKKPPK",
            "KKDDDDDDDKK",
            "KDDDDDDDDDK",
            "KODEOOOEODK",
            "KOOOOOOOOOK",
            "KOONOOONOOK",
            "KOWWWWWWWOK",
            ".KOOWWWOOK.",
            "..KKKKKKK..",
        ]
        let quarter = [
            "..KK.....KK",
            ".KPPKKKKKPK",
            ".KKDDDDDDKK",
            "KDDDDDDDDDK",
            "KOODEOOOEOK",
            "KOOOOOOOOOK",
            "KOOONOOONOK",
            ".KOWWWWWWOK",
            "..KOOWWWOK.",
            "...KKKKKK..",
        ]
        return turn >= 1 ? front : quarter
    }

    static var turnFrames: [PixelFrame] {
        func faced(_ rows: [String]) -> PixelFrame {
            capybara(body: seated, legs: [], sitting: true, head: (16, 4), headRows: rows)
        }
        return [sit(), faced(frontHead(0.5)), faced(frontHead(1))]
    }

    // MARK: Oranges

    static let orange = [
        "..YY..",
        ".GGGG.",
        "GXGGGG",
        "GGGGGF",
        "GGGGFF",
        ".FFFF.",
    ]

    /// An orange with a dark line round it, for the one the capybara holds or wears: it is on the capybara's own picture, and the rim
    /// goes round both.
    static let outlinedOrange: [String] = {
        let rows = orange.map { "." + $0 + "." }
        let padded = [String(repeating: ".", count: rows[0].count)] + rows + [String(repeating: ".", count: rows[0].count)]
        let cells = padded.map { Array($0) }
        return cells.indices.map { y in
            String(cells[y].indices.map { x in
                guard cells[y][x] == "." else { return cells[y][x] }
                let touches = (-1...1).contains { dy in
                    (-1...1).contains { dx in
                        (dx != 0 || dy != 0) && cells.indices.contains(y + dy) && cells[y + dy].indices.contains(x + dx) && cells[y + dy][x + dx] != "."
                    }
                }
                return touches ? "K" : "."
            })
        }
    }()

    /// An orange held in the two front paws below the snout.
    static func holding(_ canvas: inout CatCanvas, dy: Int = 0, parts: Int = 0) {
        canvas.piece(outlinedOrange, x: 20, y: 13 + dy)
        canvas.piece(["DD", "DD"], x: 19, y: 16 + dy)
        canvas.piece(["DD"], x: 24, y: 19 + dy)
        // The peel that came off, hanging below it in a curl.
        for part in 0..<parts { canvas.piece(["GF"], x: 21 + part % 2, y: 20 + part / 2) }
    }

    static var holdFrames: [PixelFrame] {
        (0..<2).map { index in sit(breath: index) { holding(&$0, dy: index) } }
    }

    static var peelFrames: [PixelFrame] {
        (0..<4).map { index in sit(breath: index % 2, face: .half) { holding(&$0, dy: index % 2, parts: index + 1) } }
    }

    static var chewFrames: [PixelFrame] {
        (0..<4).map { index in
            sit(breath: index % 2, face: index % 2 == 0 ? .chewA : .chewB) { canvas in
                canvas.piece(["GG", "FF"], x: 22, y: 17)
                canvas.piece(["DD"], x: 20, y: 17)
            }
        }
    }
}

extension CapybaraArt {
    // MARK: In the tub

    /// In the tub, with only its back and its head above the water, and an orange on its head if `withOrange`: it rides the head up and
    /// down. The tub itself is the prop drawn over it, which hides what is below the water line.
    static func soak(face: Face = .open, withOrange: Bool = false, breath: Int = 0, extras: (inout CatCanvas) -> Void = { _ in }) -> PixelFrame {
        sit(breath: breath, face: face) { canvas in
            if withOrange { canvas.piece(Self.outlinedOrange, x: 20, y: breath) }
            extras(&canvas)
        }
    }

    /// How far down it goes for a frog to sit on its head: the picture is drawn this many rows lower and the water of the tub, which is drawn
    /// over it, is over all of it but the top of its head, so that its eyes are the last of it above the water and the crown of its head,
    /// where the frog sits, is `deepest` rows lower than it is when it soaks (and `backTop` is nothing any more: its back is under the water).
    static let deepest = 5

    /// Sinking: the whole of it a row lower at a time, until it is where it is for the frog.
    static var soakSinkFrames: [PixelFrame] { (1..<deepest).map { sit(sunk: $0) } }

    /// Sunk to its eyes, still, with its eyes open and now and then shut.
    static var soakDeepFrames: [PixelFrame] { [sit(sunk: deepest), sit(sunk: deepest), sit(face: .half, sunk: deepest), sit(face: .blink, sunk: deepest)] }

    static var soakHappyFrames: [PixelFrame] {
        (0..<4).map { index in
            soak(face: .happy, breath: index % 2) { canvas in canvas.piece(CatArt.heart, x: 9 + index % 2, y: 9 - index * 2) }
        }
    }

    /// Tucked legs: the feet up under the body.
    static var tucked: [CatArt.Leg] {
        [
            CatArt.Leg(hip: (5, 16.5), foot: (3.5, 18.5), far: true), CatArt.Leg(hip: (15.5, 16.5), foot: (17.5, 18.5), far: true),
            CatArt.Leg(hip: (7.5, 16.5), foot: (6, 18.5)), CatArt.Leg(hip: (18, 16.5), foot: (20, 18.5)),
        ]
    }

    /// Reaching down with the front legs, the hind ones trailing.
    static var reaching: [CatArt.Leg] {
        [
            CatArt.Leg(hip: (5, 16.5), foot: (3, 19), far: true), CatArt.Leg(hip: (15.5, 16.5), foot: (18.5, 20), far: true),
            CatArt.Leg(hip: (7.5, 16.5), foot: (5.5, 19.5)), CatArt.Leg(hip: (18, 16.5), foot: (21, 20)),
        ]
    }

    /// The hop into the tub, six pictures: up from standing, over the rim, down into the water. The way out is the same pictures backwards.
    static var climbInFrames: [PixelFrame] {
        [
            capybara(),
            crouch,
            capybara(legs: tucked, head: (16, 6), lift: 3),
            capybara(legs: tucked, head: (16, 5), lift: 5),
            capybara(legs: reaching, head: (16, 6), lift: 2),
            sit(breath: 1),
        ]
    }
}
