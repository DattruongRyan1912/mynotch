import Foundation

extension FrogArt {
    /// Every move as its pictures, and how they are played. Built when asked for, a move at a time, as the cat's are.
    static func animation(for move: FrogMove) -> PixelAnimation {
        PixelAnimation(frames: frames(for: move), fps: move.fps, loops: move.loops, advance: move.advance)
    }

    private static func frames(for move: FrogMove) -> [PixelFrame] {
        let pad = move.stance == .pad && move != .hopOn
        switch move {
        case .hopOn: return hopOnFrames
        case .hopOff: return hopOffFrames
        default: break
        }
        switch move.onTheGround {
        case .sit: return (0..<4).map { picture(sitForm(breath: Double($0 / 2), eyes: .open).sacked(Double($0 / 2) * 1.1), pad: pad) }
        case .blink: return [Eyes.half, .shut, .shut, .half].map { picture(sitForm(eyes: $0), pad: pad) }
        case .puff: return puffFrames(pad: pad)
        case .hop: return hopFrames
        case .watch: return watchFrames(pad: pad)
        case .flick: return flickFrames(pad: pad)
        case .jump: return jumpFrames(pad: pad)
        case .snapOut: return snapOutFrames
        case .snapIn: return snapInFrames
        case .gulp: return gulpFrames
        case .sleep: return sleepFrames(pad: pad)
        default: return [picture(sitForm(), pad: pad)]
        }
    }

    /// The sitting frog with its eyes open and shut: what one that does not move at all (Reduce Motion) shows.
    static var restingFrames: [PixelFrame] { [picture(sitForm()), picture(sitForm(eyes: .shut))] }

    // MARK: Small tools

    /// A form as a finished picture, a few rows higher for the lily pad.
    static func picture(_ form: Form, pad: Bool = false, lift: Int = 0, extras: @escaping (inout CatCanvas) -> Void = { _ in }) -> PixelFrame {
        draw(rig(form.moved(originShift, 0), lift: lift + (pad ? padRise : 0), extras: extras))
    }

    /// Where the tongue comes out of the mouth, for a head as it is turned now: the front of it, on the line of the mouth.
    static func mouthOf(_ form: Form) -> Point {
        let head = form.head
        let (c, s) = (cos(head.angle), sin(head.angle))
        let reach = head.rx - 1.4
        return (head.cx + reach * c, head.cy + head.ry * 0.15 * c + reach * s)
    }

    /// The tongue from the mouth towards (`tx`, `ty`), `share` of the way there.
    static func tongue(of form: Form, to target: Point, share: Double) -> [Point] {
        let from = mouthOf(form)
        guard share > 0 else { return [] }
        return [from, (from.x + (target.x - from.x) * share, from.y + (target.y - from.y) * share)]
    }

    // MARK: Standing about

    /// Blowing its throat out and letting it go: the pale sac under the chin swells, and the body with it.
    static func puffFrames(pad: Bool) -> [PixelFrame] {
        [1.6, 2.6, 3.4, 3.4, 2.6, 1.6].enumerated().map { index, size in
            picture(sitForm(breath: index == 2 || index == 3 ? 1 : 0.5, eyes: index == 2 || index == 3 ? .half : .open).sacked(size), pad: pad)
        }
    }

    /// Sitting up with its eyes on something: the head up, the eyes up, the throat going.
    static func watchFrames(pad: Bool) -> [PixelFrame] {
        (0..<2).map { index in
            picture(sitForm(breath: Double(index), eyes: .up).headTurned(-0.2).sacked(Double(index) * 0.9), pad: pad)
        }
    }

    /// The tongue flicked out towards something up and in front of it and back: the mouth opens, the tongue goes up and out at an angle,
    /// and is gone again.
    static func flickFrames(pad: Bool) -> [PixelFrame] {
        let shares = [0.0, 0.35, 1.0, 0.55, 0.0]
        let mouths: [Mouth] = [.ajar, .wide, .wide, .wide, .ajar]
        return shares.enumerated().map { index, share in
            var form = sitForm(eyes: .up, mouth: mouths[index]).headTurned(-0.32)
            let tip = (x: mouthOf(form).x + 7.2, y: mouthOf(form).y - 6.4)
            form.tongue = tongue(of: form, to: tip, share: share)
            return picture(form, pad: pad)
        }
    }

    /// Asleep: low and round with its eyes shut and its head down, breathing, with z's going up.
    static func sleepFrames(pad: Bool) -> [PixelFrame] {
        let zeds: [[(x: Int, y: Int)]] = [[(22, 7)], [(22, 6), (26, 2)], [(26, 3)], [(22, 7), (26, 3)]]
        return (0..<4).map { index in
            picture(
                sitForm(breath: Double(index / 2), eyes: .shut).crouched(0.8).headTurned(0.12), pad: pad,
                extras: { canvas in for zed in zeds[index] { canvas.piece(CatArt.zed, x: zed.x, y: zed.y) } }
            )
        }
    }

    // MARK: Hopping

    /// Where the frog is in a hop, in six pictures that go round: the crouch, the push, the rise, the top of it with the legs trailing, the fall
    /// with the legs coming under it, and the landing. How high it is off the ground, and how far it is drawn from where its picture says it is:
    /// the layer moves a whole step every picture, which would have it slide while it crouches and lands, so the picture is drawn back a little
    /// then and forward in the air, and the frog is nearly still on the ground and quick in the air.
    static let hopShape: [(lift: Int, shift: Double)] = [(0, 0), (0, -2), (3, -1), (6, 0), (3, 1), (0, 2)]

    /// The six forms of a hop, facing right.
    static func hopForms() -> [Form] {
        let tuck: [Point] = [(13.6, 17.0), (15.6, 18.0)]
        let reach: [Point] = [(14.4, 17.0), (18.0, 19.2)]
        var push = sitForm(eyes: .open).turned(-0.5, about: feet)
        push.stretch = 1
        push.hind = [(6.0, 16.0), (2.6, 19.0), (1.6, 20.3)]
        push.arm = tuck
        var rise = sitForm(eyes: .open).turned(-0.28, about: feet)
        rise.stretch = 1
        rise.hind = [(6.0, 16.0), (3.0, 18.5), (1.6, 19.3)]
        rise.arm = tuck
        var top = sitForm(eyes: .open).turned(-0.06, about: feet)
        top.stretch = 1
        top.hind = [(6.0, 16.0), (3.0, 17.5), (1.6, 18.0)]
        top.arm = tuck
        var fall = sitForm(eyes: .open).turned(0.2, about: feet)
        fall.stretch = 1
        fall.hind = [(6.0, 16.0), (3.0, 18.0), (5.0, 19.5)]
        fall.arm = reach
        var land = sitForm(eyes: .open).crouched(0.7)
        land.arm = [(14.2, 17.5), (16.2, 20.0)]
        return [sitForm(eyes: .open).crouched(1.2).headTurned(0.08), push, rise, top, fall, land]
    }

    static var hopFrames: [PixelFrame] {
        zip(hopForms(), hopShape).map { form, shape in picture(form.moved(shape.shift, 0), lift: shape.lift) }
    }

    /// The hop from the bank to the lily pad: the crouch and the push on the ground, up and over, and down on the pad, a few rows higher.
    static var hopOnFrames: [PixelFrame] {
        let lifts = [0, 0, 4, 8, 6, padRise]
        return zip(hopForms(), lifts).map { form, lift in picture(form, lift: lift) }
    }

    /// The hop back off it: from the pad, over, and down on the ground.
    static var hopOffFrames: [PixelFrame] {
        let lifts = [padRise, padRise + 1, 8, 7, 3, 0]
        return zip(hopForms(), lifts).map { form, lift in picture(form, lift: lift) }
    }

    /// The happy hop in place of a stroke: up with a heart, down, and a smaller hop after it.
    static func jumpFrames(pad: Bool) -> [PixelFrame] {
        let forms = hopForms()
        let heart: (inout CatCanvas) -> Void = { canvas in canvas.outlinedPiece(CatArt.heart, x: 24, y: 0) }
        var up = forms[3]
        up.eyes = .happy
        var smaller = forms[2]
        smaller.eyes = .happy
        var down = forms[4]
        down.eyes = .happy
        return [
            picture(forms[0], pad: pad), picture(forms[1], pad: pad, lift: 1), picture(up, pad: pad, lift: 4, extras: heart),
            picture(down, pad: pad, lift: 2, extras: heart), picture(forms[5], pad: pad), picture(forms[0], pad: pad),
            picture(smaller, pad: pad, lift: 2), picture(forms[5], pad: pad),
        ]
    }

    // MARK: Catching a moth

    /// Where the tip of its tongue is when it has reached the moth, before the frog is moved to where it is drawn: the moth hovers here (`FrogMove.mothReach`).
    static let mothTip: Point = (28.4, 11.3)

    private static func snapForm(mouth: Mouth) -> Form {
        sitForm(eyes: .up, mouth: mouth).headTurned(-0.1)
    }

    /// The tongue shoots out to the moth: the mouth opens wide, and the tongue is out at the moth in three quick pictures.
    static var snapOutFrames: [PixelFrame] {
        [0.0, 0.4, 0.8, 1.0].enumerated().map { index, share in
            var form = snapForm(mouth: .wide)
            form.tongue = tongue(of: form, to: mothTip, share: share)
            return picture(form)
        }
    }

    /// The tongue comes back with the moth on it, and the mouth shuts on it.
    static var snapInFrames: [PixelFrame] {
        [0.55, 0.2, 0.0].enumerated().map { index, share in
            var form = snapForm(mouth: index == 2 ? .shut : .wide)
            form.tongue = tongue(of: form, to: mothTip, share: share)
            if index == 2 { form.eyes = .half }
            return picture(form.sacked(index == 2 ? 0.9 : 0))
        }
    }

    /// The gulp: the eyes shut and sink into the head, the throat swells and the lump goes down, and the eyes come up again, pleased.
    static var gulpFrames: [PixelFrame] {
        let steps: [(sink: Double, eyes: Eyes, sac: Double)] = [(0.6, .shut, 1.4), (1.2, .shut, 2.2), (1.2, .shut, 2.6), (1.0, .shut, 1.6), (0.4, .half, 0.8), (0, .happy, 0)]
        return steps.map { step in
            var form = sitForm(breath: step.sac > 2 ? 1 : 0, eyes: step.eyes).sacked(step.sac)
            form.sink = step.sink
            return picture(form)
        }
    }
}

extension FrogArt.Form {
    /// The same with its throat puffed to a radius of `size`.
    func sacked(_ size: Double) -> FrogArt.Form {
        var form = self
        form.sac = size
        return form
    }
}
