#if os(iOS)
import CoreMotion
import Testing
@testable import Kudos

struct ShakeDetectorTests {
    @Test func opposingSwingsAboveFloorCountAsReversed() {
        let left = CMAcceleration(x: -1.0, y: 0, z: 0)
        let right = CMAcceleration(x: 1.0, y: 0, z: 0)
        #expect(shakeSamplesReversed(left, right, magnitudeFloor: 0.3))
    }

    @Test func sameDirectionSwingsAreNotReversed() {
        let a = CMAcceleration(x: 1.0, y: 0, z: 0)
        let b = CMAcceleration(x: 0.8, y: 0.1, z: 0)
        #expect(!shakeSamplesReversed(a, b, magnitudeFloor: 0.3))
    }

    @Test func belowNoiseFloorNeverCountsEvenIfOpposed() {
        let tinyLeft = CMAcceleration(x: -0.1, y: 0, z: 0)
        let tinyRight = CMAcceleration(x: 0.1, y: 0, z: 0)
        #expect(!shakeSamplesReversed(tinyLeft, tinyRight, magnitudeFloor: 0.3))
    }
}
#endif
