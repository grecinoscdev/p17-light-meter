import XCTest
@testable import ExposureCore

final class SlowSpeedTests: XCTestCase {
    func testSlowSpeedMatchesProgramAcrossTargetsAndExposureLimits() throws {
        for aperture in [3.5, 8, 11, 16] {
            for ev in [0.0, 8, 15, 20] {
                for nd in [0.0, 3, 8] {
                    let slow = try ExposureEngine.assess(sceneEV100: ev,
                        configuration: ExposureConfiguration(cameraISO: 400, exposureCompensationEV: 1,
                            mode: .slowSpeed(targetAperture: aperture)), ndStops: nd)
                    let program = try ExposureEngine.assess(sceneEV100: ev,
                        configuration: ExposureConfiguration(cameraISO: 400, exposureCompensationEV: 1,
                            mode: .program(targetAperture: aperture)), ndStops: nd)
                    XCTAssertEqual(slow.target, program.target)
                    XCTAssertEqual(slow.modeledAperture, program.modeledAperture)
                    XCTAssertEqual(slow.modeledShutterSeconds, program.modeledShutterSeconds)
                    XCTAssertEqual(slow.modeledRange, program.modeledRange)
                    XCTAssertEqual(slow.needsSteadySupport, program.needsSteadySupport)
                    XCTAssertEqual(slow.mode, .slowSpeed(targetAperture: aperture))
                }
            }
        }
    }

    func testReferenceRecommendationUsesEditableTarget() throws {
        // EV15 + ISO400 gives EV17: at f/8 with ND8, 64 / 2^14 = 1/256 s.
        let configuration = try ExposureConfiguration(cameraISO: 400, exposureCompensationEV: 0,
            mode: .slowSpeed(targetAperture: 8))
        let result = try NDRecommendationEngine.recommend(sceneEV100: 15, configuration: configuration, inventory: NDFilter.catalog)
        guard case let .candidate(candidate) = result.recommendation else { return XCTFail("Expected ND8") }
        XCTAssertEqual(candidate.filter.stops, 3)
        XCTAssertEqual(candidate.exposure.modeledAperture, 8)
        XCTAssertEqual(candidate.exposure.target.shutterSeconds, 1.0 / 256)
        XCTAssertEqual(result.exactMinimumStops, 2.54878888816767, accuracy: 1e-12)
    }

    func testSlowSpeedRejectsInvalidTargetsLikeProgram() {
        for aperture in [0, 3.4, 17, Double.nan, .infinity] {
            XCTAssertThrowsError(try ExposureConfiguration(cameraISO: 100, exposureCompensationEV: 0,
                mode: .slowSpeed(targetAperture: aperture))) {
                XCTAssertEqual($0 as? ExposureError, .invalidTargetAperture)
            }
        }
    }
}
