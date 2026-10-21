import XCTest
@testable import ExposureCore

final class ProgramExposureTests: XCTestCase {
    private func assess(ev: Double = 15, iso: Int = 400, ec: Double = 0,
                        aperture: Double = 8, nd: Double = 3) throws -> ProgramAssessment {
        try ProgramExposure.assess(sceneEV100: ev, cameraISO: iso,
                                   exposureCompensationEV: ec, targetAperture: aperture, ndStops: nd)
    }

    func testReferenceScenarioIsExactlyOneOver256() throws {
        let result = try assess()
        XCTAssertEqual(result.shutterSeconds, 1.0 / 256.0, accuracy: 1e-12)
        XCTAssertEqual(result.minimumNDStops, 2.548788888, accuracy: 1e-8)
        XCTAssertEqual(result.range, .withinPhysicalEnvelopeModeLimitUnverified)
    }

    func testCameraISOAndCompensationHaveOppositeSigns() throws {
        let base = try assess(iso: 100, nd: 0)
        let higherISO = try assess(nd: 0)
        let positiveEC = try assess(iso: 100, ec: 1, nd: 0)
        XCTAssertEqual(higherISO.minimumNDStops - base.minimumNDStops, 2, accuracy: 1e-12)
        XCTAssertEqual(positiveEC.shutterSeconds, base.shutterSeconds * 2, accuracy: 1e-12)
        XCTAssertEqual(try assess(ec: 1).minimumNDStops, higherISO.minimumNDStops - 1, accuracy: 1e-12)
    }

    func testSelectedNDAppliesOnceAndCanCauseSlowExposure() throws {
        XCTAssertEqual(try assess(nd: 4).shutterSeconds, 1.0 / 128.0, accuracy: 1e-12)
        XCTAssertEqual(try assess(ev: 0, iso: 100, nd: 0).range, .slowerThanAutomaticEnvelope)
        XCTAssertEqual(try assess(nd: 0).range, .fasterThanShutterLimit)
        XCTAssertEqual(try assess(ev: 8, iso: 100, nd: 0).minimumNDStops, 0)
    }

    func testFastAndSlowBoundaries() throws {
        // Independent golden EV from PLAN.md; enough digits to exercise the boundary.
        let fastBoundaryEV = 14.451211111832329
        XCTAssertEqual(try assess(ev: fastBoundaryEV, iso: 100, nd: 0).range,
                       .withinPhysicalEnvelopeModeLimitUnverified)
        XCTAssertEqual(try assess(ev: fastBoundaryEV + 1e-8, iso: 100, nd: 0).range,
                       .fasterThanShutterLimit)
        XCTAssertEqual(try assess(ev: fastBoundaryEV - 1e-8, iso: 100, nd: 0).range,
                       .withinPhysicalEnvelopeModeLimitUnverified)
        XCTAssertEqual(try assess(ev: 4, iso: 100, nd: 0).shutterSeconds, 4, accuracy: 1e-12)
        XCTAssertEqual(try assess(ev: 4, iso: 100, nd: 0).range,
                       .withinPhysicalEnvelopeModeLimitUnverified)
        XCTAssertEqual(try assess(ev: 4 - 1e-8, iso: 100, nd: 0).range,
                       .slowerThanAutomaticEnvelope)
    }

    func testInvalidInputsNeverProducePlausibleReadings() {
        let cases: [(Double, Int, Double, Double, Double, ExposureError)] = [
            (.nan, 400, 0, 8, 3, .invalidSceneEV),
            (.infinity, 400, 0, 8, 3, .invalidSceneEV),
            (15, 0, 0, 8, 3, .unsupportedCameraISO),
            (15, 101, 0, 8, 3, .unsupportedCameraISO),
            (15, 400, 0.5, 8, 3, .invalidCompensation),
            (15, 400, 3, 8, 3, .invalidCompensation),
            (15, 400, .nan, 8, 3, .invalidCompensation),
            (15, 400, 0, 2, 3, .invalidTargetAperture),
            (15, 400, 0, .infinity, 3, .invalidTargetAperture),
            (15, 400, 0, 8, -1, .invalidNDStops),
            (15, 400, 0, 8, .nan, .invalidNDStops),
            (10000, 400, 0, 8, 3, .unrepresentableExposure)
        ]
        for (ev, iso, ec, aperture, nd, error) in cases {
            XCTAssertThrowsError(try assess(ev: ev, iso: iso, ec: ec, aperture: aperture, nd: nd)) {
                XCTAssertEqual($0 as? ExposureError, error)
            }
        }
    }
}
