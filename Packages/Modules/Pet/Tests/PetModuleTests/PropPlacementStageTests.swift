import AppKit
import MyNotchCore
import NotchUI
import Testing
@testable import PetModule

/// What a character puts up in a crowded lane (the tub, the wheel, the hole in the ice): it is put where nobody else rests or will, and
/// where its owner hops or stands from is kept clear too. Three characters in a tall pill are the crowd: each one's room is about a third of
/// the lane, so a place that is "not in any room" is hard to find, and a lane that has none must give no prop at all and not one in somebody's
/// room.
@Suite(.serialized) @MainActor struct PropPlacementStageTests {
    struct Report {
        var inTheWay: [String] = []
        var tubs = 0
        var wheels = 0
        var holes = 0
    }

    /// Looks at the characters after every waking for `minutes` of made-up time: nobody at rest within a picture of the room a prop takes up
    /// (the place it is at, and the place its owner hops or stands from), but the pair that is playing.
    func watch(_ geometry: NotchGeometry, kinds: [CharacterKind], seed: UInt64, minutes: Int) throws -> Report {
        let rig = BodyRig(geometry: geometry, seed: seed)
        rig.show()
        defer { rig.hide() }
        let stage = rig.stage
        stage.characters = kinds
        let field = try #require(rig.hosts.first?.field)
        let (travel, width) = (Double(field.lane.travel), Double(field.spriteWidth))
        var report = Report()
        for tick in 0..<(4 * 60 * minutes) {
            // The Mac now busy and now quiet, so that the hamster runs and the others change what they do.
            rig.cpu.value = tick % 3000 < 1500 ? 0.05 : 0.8
            rig.advance(0.25)
            let now = rig.scheduler.seconds
            let poses = stage.poses
            let playing = stage.jointExempt
            func rests(_ pose: Pose) -> Bool { pose.from == pose.to || now >= pose.end }
            for (owner, pose) in poses.enumerated() {
                guard let prop = pose.prop, prop.look.occupies else { continue }
                switch kinds[owner] {
                case .capybara: report.tubs += 1
                case .hamster: report.wheels += 1
                case .penguin: report.holes += 1
                default: break
                }
                for (other, otherPose) in poses.enumerated() where other != owner && rests(otherPose) {
                    // (The pair that is playing, or only just done and still getting out of each other's way, owes nothing.)
                    if playing.contains(owner), playing.contains(other) { continue }
                    for place in [prop.to] + prop.alsoAt {
                        let apart = abs(otherPose.position(at: now) - place) * travel
                        if apart < width {
                            report.inTheWay.append("\(kinds.map(\.rawValue)), seed \(seed) at \(now): \(kinds[other].rawValue) \(Int(apart)) points from the room \(kinds[owner].rawValue)'s prop takes")
                        }
                    }
                }
            }
        }
        return report
    }

    @Test func threeInATallPillNeverHaveATubAWheelOrAHoleInSomebodysRoomOrWhereItsOwnerStandsFrom() throws {
        var report = Report()
        let rows: [[CharacterKind]] = [
            [.capybara, .hamster, .penguin], [.penguin, .capybara, .hamster], [.hamster, .penguin, .capybara],
            [.capybara, .hamster, .corgi], [.penguin, .capybara, .frog], [.hamster, .corgi, .capybara],
        ]
        for kinds in rows {
            for seed: UInt64 in [3, 8, 21, 34] {
                let one = try watch(Screens.tallPill, kinds: kinds, seed: seed, minutes: 40)
                report.inTheWay += one.inTheWay
                report.tubs += one.tubs
                report.wheels += one.wheels
                report.holes += one.holes
            }
        }
        #expect(report.inTheWay.isEmpty, "\(report.inTheWay.count): \(report.inTheWay.prefix(3))")
        // Not a quiet run that proves nothing: every kind of prop was seen out.
        #expect(report.tubs > 0 && report.wheels > 0 && report.holes > 0, "\(report.tubs) with a tub out, \(report.wheels) with a wheel, \(report.holes) with a hole")
    }

    @Test func theSameInThePillAndOnTheMacsWingsWithTheTubTheWheelAndTheHoleKeptToBothOfTheirPlaces() throws {
        var report = Report()
        for geometry in [Screens.pill, Screens.hardware] {
            for kinds in [[CharacterKind.capybara, .hamster, .penguin], [.penguin, .capybara, .hamster], [.hamster, .penguin, .capybara]] {
                for seed: UInt64 in [3, 8, 21] {
                    let one = try watch(geometry, kinds: kinds, seed: seed, minutes: 30)
                    report.inTheWay += one.inTheWay
                    report.tubs += one.tubs
                    report.wheels += one.wheels
                    report.holes += one.holes
                }
            }
        }
        #expect(report.inTheWay.isEmpty, "\(report.inTheWay.count): \(report.inTheWay.prefix(3))")
        #expect(report.tubs > 100 && report.wheels > 100 && report.holes > 100, "\(report.tubs) tub, \(report.wheels) wheel, \(report.holes) hole")
    }
}
