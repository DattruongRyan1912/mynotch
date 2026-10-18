import Foundation
import Testing
@testable import PetModule

/// A lane so crowded that there is nowhere free to stand: two characters' zones that touch, and so are joined, and cover the whole of it.
/// `LaneKeeper.settled` has nowhere to send a place and gives it back, which is no place for a prop that takes up room: the tub, the wheel
/// and the hole in the ice ask whether a place is free, and with none there is no prop and the day goes on all the same.
struct CrowdedLaneBrainTests {
    static let crowded = LaneContext(zones: [-0.01...0.61, 0.6...1.2])
    static let senses = CatSenses(idleSeconds: 5, hour: 14)

    @Test func theLaneKeeperSaysNothingIsFreeWhereSettledGivesTheAskedForPlaceBack() {
        let keeper = LaneKeeper(Self.crowded)
        for place in stride(from: 0.0, through: 1.0, by: 0.05) {
            #expect(!keeper.isFree(place), "\(place)")
            #expect(keeper.settled(place) == place, "settled has nowhere to send \(place)")
        }
        let open = LaneKeeper(LaneContext(crossing: [0.4...0.5], zones: [0.7...0.9]))
        #expect(open.isFree(0.1) && open.isFree(0.6) && !open.isFree(0.45) && !open.isFree(0.8))
        #expect(open.isFree(0.7) && open.isFree(0.9), "the edge of a stretch is outside it")
    }

    @Test func aCapybaraInACrowdedLaneHasNoTubAndNoOrangeAndADayAllTheSame() {
        var tubs = 0, scenes = 0
        for seed in 1...6 as ClosedRange<UInt64> {
            var drive = CapyDrive(seed: seed, position: 0.3, senses: Self.senses, travel: 237)
            drive.lane = Self.crowded
            drive.run(3 * 3600)
            tubs += drive.every.filter { $0.prop != nil }.count
            scenes += drive.scenes.count
            #expect(drive.brain.strayProps == 0)
        }
        #expect(tubs == 0 && scenes > 100, "\(tubs) poses with a prop in \(scenes) scenes")
        var free = CapyDrive(seed: 3, position: 0.3, senses: Self.senses, travel: 237)
        free.lane = LaneContext(zones: [0.8...1.2])
        free.run(3 * 3600)
        #expect(free.every.contains { $0.prop?.look.occupies == true }, "with a stretch that is free, there is a tub")
    }

    @Test func aHamsterInACrowdedLaneHasNoWheelAndNoSeedsAndADayAllTheSame() {
        var props = 0, scenes = 0
        for seed in 1...6 as ClosedRange<UInt64> {
            var drive = HamDrive(seed: seed, position: 0.3, senses: Self.senses, travel: 237)
            drive.lane = Self.crowded
            drive.run(3 * 3600)
            props += drive.every.filter { $0.prop != nil }.count
            scenes += drive.scenes.count
            #expect(drive.brain.strayProps == 0)
        }
        #expect(props == 0 && scenes > 100, "\(props) poses with a prop in \(scenes) scenes")
        var free = HamDrive(seed: 3, position: 0.3, senses: Self.senses, travel: 237)
        free.lane = LaneContext(zones: [0.8...1.2])
        free.run(3 * 3600)
        #expect(free.every.contains { $0.prop?.look.occupies == true }, "with a stretch that is free, there is a wheel")
    }

    @Test func aPenguinInACrowdedLaneHasNoHoleAndADayAllTheSame() {
        var holes = 0, scenes = 0
        for seed in 1...6 as ClosedRange<UInt64> {
            var drive = PenDrive(seed: seed, position: 0.3, senses: Self.senses, travel: 237)
            drive.lane = Self.crowded
            drive.run(3 * 3600)
            holes += drive.every.filter { $0.prop != nil }.count
            scenes += drive.scenes.count
            #expect(drive.brain.strayProps == 0)
        }
        #expect(holes == 0 && scenes > 100, "\(holes) poses with a hole in \(scenes) scenes")
        var free = PenDrive(seed: 3, position: 0.3, senses: Self.senses, travel: 237)
        free.lane = LaneContext(zones: [0.8...1.2])
        free.run(3 * 3600)
        #expect(free.every.contains { $0.prop != nil }, "with a stretch that is free, there is a hole")
    }
}
