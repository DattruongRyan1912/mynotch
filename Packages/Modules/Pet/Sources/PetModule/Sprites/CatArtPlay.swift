import Foundation

// MARK: Crouching, pouncing, stretching, batting

extension CatArt {
    static let standingLegs: [Leg] = [
        Leg(hip: (6.5, 15), foot: (6.5, 20), far: true), Leg(hip: (18, 15), foot: (18, 20), far: true),
        Leg(hip: (9, 15), foot: (9, 20)), Leg(hip: (20.5, 15), foot: (20.5, 20)),
    ]

    /// The body with its back end higher or lower than its front end: two ellipses that overlap.
    static func tilted(rear: Double, front: Double) -> [Body] {
        [Body(cx: 8.5, cy: rear, rx: 5.6, ry: 4.4), Body(cx: 15.5, cy: front, rx: 6.4, ry: 4)]
    }

    // MARK: Pounce

    /// Eight frames, once through: down, rear up, a wiggle of the tail end, the spring, the flight, the landing. The cat only moves in
    /// the last three.
    static var pounceFrames: [PixelFrame] {
        func crouch(rear: Double, wiggle: Double, tail: [Point]) -> PixelFrame {
            let legs = [
                Leg(hip: (7 + wiggle, 16), foot: (6 + wiggle, 20), far: true), Leg(hip: (17, 17), foot: (22, 20), far: true),
                Leg(hip: (9.5 + wiggle, 16), foot: (8 + wiggle, 20)), Leg(hip: (19.5, 17), foot: (25, 20)),
            ]
            var bodies = tilted(rear: rear, front: 15.5)
            bodies[0].cx += wiggle
            return side(legs: legs, bodies: bodies, tail: tail, face: .open, head: (17, 8))
        }
        let tailUp: [Point] = [(4, 11), (2, 9), (1.5, 6), (3, 4)]
        let tailLeft: [Point] = [(4, 11), (1.5, 10), (1, 7), (1.5, 4.5)]
        let tailRight: [Point] = [(4, 11), (3, 8.5), (4, 6), (6.5, 4.5)]
        let launch = side(
            legs: [
                Leg(hip: (7, 15), foot: (3, 19.5), far: true), Leg(hip: (18, 15), foot: (23, 18), far: true),
                Leg(hip: (9, 15), foot: (5, 20)), Leg(hip: (20.5, 15), foot: (25, 17)),
            ],
            bodies: [Body(cx: 13.5, cy: 12.5, rx: 9.5, ry: 4.2)], tail: tailLow, face: .wide, head: (16, 4)
        )
        let flight = side(
            legs: [
                Leg(hip: (7, 14), foot: (1.5, 16), far: true), Leg(hip: (18, 14), foot: (26.5, 13), far: true),
                Leg(hip: (9, 14), foot: (3.5, 17)), Leg(hip: (20.5, 14), foot: (27.5, 15)),
            ],
            bodies: [Body(cx: 13.5, cy: 11, rx: 10.2, ry: 3.9)], tail: tailLow, face: .wide, head: (16, 2), lift: 1
        )
        let landing = side(
            legs: [
                Leg(hip: (7, 16), foot: (5, 20), far: true), Leg(hip: (17, 17), foot: (24, 20), far: true),
                Leg(hip: (9.5, 16), foot: (8, 20)), Leg(hip: (19.5, 17), foot: (27, 20)),
            ],
            bodies: tilted(rear: 12.5, front: 15.5), tail: tailUp, face: .open, head: (17, 8)
        )
        return [
            crouch(rear: 14, wiggle: 0, tail: tailRight), crouch(rear: 12.5, wiggle: 0, tail: tailUp),
            crouch(rear: 12, wiggle: -1, tail: tailLeft), crouch(rear: 12, wiggle: 1, tail: tailRight), crouch(rear: 11.5, wiggle: -1.6, tail: tailUp),
            launch, flight, landing,
        ]
    }

    // MARK: Stretch

    /// A cat's bow: the front end down with the paws out in front, the rear end up, held, and up again.
    static func bow(_ t: Double, face: Face) -> PixelFrame {
        let legs = [
            Leg(hip: (7, 15 - 2.5 * t), foot: (6, 20), far: true), Leg(hip: (18, 15 + 2 * t), foot: (23 + 3 * t, 20), far: true),
            Leg(hip: (9.5, 15 - 2.5 * t), foot: (8, 20)), Leg(hip: (20, 15 + 2 * t), foot: (24 + 3 * t, 20)),
        ]
        let bodies = tilted(rear: 12 - 2.5 * t, front: 13 + 2.5 * t)
        let tail: [Point] = [(4, 11 - 2.5 * t), (2.5, 8 - 2.5 * t), (2, 5 - 2 * t)]
        return side(legs: legs, bodies: bodies, tail: tail, face: face, head: (17 + Int((2 * t).rounded()), 3 + Int((6 * t).rounded())))
    }

    static var stretchFrames: [PixelFrame] {
        [bow(0.2, face: .open), bow(0.55, face: .squint), bow(1, face: .blink), bow(1, face: .yawn), bow(0.8, face: .blink), bow(0.3, face: .open)]
    }

    // MARK: Yarn

    /// Batting at a ball with the near front paw, head down after it.
    static var yarnFrames: [PixelFrame] {
        let paws: [Point] = [(22, 20), (24.5, 17.5), (27.5, 17), (26, 18.5), (23.5, 19.5), (22, 20)]
        return paws.enumerated().map { index, paw in
            var legs = standingLegs
            legs[3] = Leg(hip: (20.5, 15), foot: paw)
            return side(legs: legs, tail: [(5.5, 11), (3, 10), (1.5, 8 + (index % 2 == 0 ? 0.5 : -0.5)), (2, 5.5)], face: index == 2 ? .wide : .open,
                        head: (16, 4), lift: index == 2 || index == 3 ? -0.5 : 0)
        }
    }

    // MARK: Startled

    /// An arched back, a puffed tail, a bang: a jump on the spot.
    static var startledFrames: [PixelFrame] {
        let lifts: [Double] = [0, 2, 3, 1]
        return lifts.enumerated().map { index, lift in
            let crouched = index == 0
            let body = Body(cx: 13.5, cy: crouched ? 14.5 : 13.5, rx: 7, ry: crouched ? 4.4 : 5)
            let legs = [
                Leg(hip: (8, 16), foot: (6, 20), far: true), Leg(hip: (18, 16), foot: (20, 20), far: true),
                Leg(hip: (10, 16), foot: (8.5, 20)), Leg(hip: (20, 16), foot: (22.5, 20)),
            ]
            let tail: [Point] = [(6.5, 13), (3.5, 11), (2.5, 8)]
            return side(legs: legs, bodies: [body], tail: tail, tailWidth: 3, face: .wide, head: (16, crouched ? 8 : 7), lift: lift) { canvas in
                if index > 0 { canvas.piece(bang, x: 11, y: 0) }
            }
        }
    }

    // MARK: Peek

    /// Only the head, coming up from below the edge of the strip: ears, eyes, a look to one side and the other.
    static var peekFrames: [PixelFrame] {
        [(Face.open, 19), (.open, 15), (.lookLeft, 12), (.lookRight, 12)].map { face, y in
            var c = CatCanvas()
            c.piece(head(face), x: 8, y: y)
            return finish(c, head: (8, y))
        }
    }

    // MARK: Between standing and sitting

    /// Sitting in profile, the rump on the ground: the last thing before it turns to face the viewer.
    static var profileSit: PixelFrame {
        side(
            legs: [Leg(hip: (17, 14), foot: (17, 20)), Leg(hip: (15, 14), foot: (15, 20), far: true, paw: true)],
            bodies: [Body(cx: 9.5, cy: 15.5, rx: 6, ry: 5), Body(cx: 14, cy: 12.5, rx: 4.6, ry: 6)],
            tail: [(4.5, 19.5), (2, 19), (1, 16)], head: (15, 2)
        )
    }

    static var sitDownFrames: [PixelFrame] {
        let rear = side(
            legs: [
                Leg(hip: (7, 17), foot: (5, 20), far: true), Leg(hip: (18, 15), foot: (18, 20), far: true),
                Leg(hip: (9.5, 17), foot: (8.5, 20)), Leg(hip: (20.5, 15), foot: (20.5, 20)),
            ],
            bodies: tilted(rear: 14.5, front: 12), tail: [(4, 14), (2, 16), (1.5, 19)], head: (16, 3)
        )
        return [side(legs: standingLegs), rear, profileSit, sit()]
    }

    static var standUpFrames: [PixelFrame] { Array(sitDownFrames.reversed()) }
}
