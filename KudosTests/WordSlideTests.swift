import CoreGraphics
import Testing
@testable import Kudos

struct WordSlideTests {
    @Test func oneWordIsTwentyTwoPoints() {
        #expect(KeysBarWordSlide.pointsPerWord == 22)
        let one = KeysBarWordSlide.resolve(travel: 22, direction: 1)
        #expect(one.wordSteps == 1)
        #expect(one.remainder == 0)
    }

    @Test func shortOfAWordCarriesTheRemainder() {
        let short = KeysBarWordSlide.resolve(travel: 21, direction: 1)
        #expect(short.wordSteps == 0)
        #expect(short.remainder == 21)

        let continued = KeysBarWordSlide.resolve(travel: 21, direction: 1, carried: short.remainder)
        #expect(continued.wordSteps == 1)
        #expect(continued.remainder == 20)
    }

    @Test func oneSampleCanCrossSeveralWords() {
        let burst = KeysBarWordSlide.resolve(travel: 50, direction: 1)
        #expect(burst.wordSteps == 2)
        #expect(burst.remainder == 6)

        let twoBack = KeysBarWordSlide.resolve(travel: 44, direction: -1)
        #expect(twoBack.wordSteps == -2)
        #expect(twoBack.remainder == 0)
    }

    @Test func remainderCarriesIntoTheNextSample() {
        let first = KeysBarWordSlide.resolve(travel: 30, direction: 1)
        #expect(first.wordSteps == 1)
        #expect(first.remainder == 8)

        let second = KeysBarWordSlide.resolve(travel: 20, direction: 1, carried: first.remainder)
        #expect(second.wordSteps == 1)
        #expect(second.remainder == 6)
    }

    @Test func reversingDirectionSpendsTheCarriedRemainder() {
        let back = KeysBarWordSlide.resolve(travel: 30, direction: -1, carried: 8)
        #expect(back.wordSteps == -1)
        #expect(back.remainder == 0)
    }

    @Test func noTravelOrNoDirectionKeepsTheRemainder() {
        let still = KeysBarWordSlide.resolve(travel: 0, direction: 1, carried: 8)
        #expect(still.wordSteps == 0)
        #expect(still.remainder == 8)

        let noDirection = KeysBarWordSlide.resolve(travel: 30, direction: 0, carried: 8)
        #expect(noDirection.wordSteps == 0)
        #expect(noDirection.remainder == 8)
    }

    @Test func negativeTravelIsADistance() {
        let forward = KeysBarWordSlide.resolve(travel: -22, direction: 1)
        #expect(forward.wordSteps == 1)
        #expect(forward.remainder == 0)
    }
}
