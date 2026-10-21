import XCTest
@testable import ExposureCore

final class ExposureEngineTests: XCTestCase {
    private func bokeh(_ sceneEV100: Double, cameraISO: Int = 100,
                       ndStops: Double = 0, handheldSeconds: Double = 1.0 / 60) throws -> ExposureAssessment {
        try ExposureEngine.assess(
            sceneEV100: sceneEV100,
            configuration: ExposureConfiguration(cameraISO: cameraISO, exposureCompensationEV: 0, mode: .bokeh),
            ndStops: ndStops, handheldThresholdSeconds: handheldSeconds
        )
    }

    func testSunlightGoldenBokehExposures() throws {
        for (cameraISO, ndStops, minimumStops) in [(100, 3.0, 2.934079044052463), (400, 5.0, 4.934079044052463)] {
            let result = try bokeh(15, cameraISO: cameraISO, ndStops: ndStops)
            XCTAssertEqual(result.target.minimumNDStops, minimumStops, accuracy: 1e-12)
            XCTAssertEqual(result.modeledAperture, 3.5)
            // 12.25 / 4096, independently calculated at post-filter EV 12.
            XCTAssertEqual(try XCTUnwrap(result.modeledShutterSeconds), 0.00299072265625, accuracy: 1e-14)
            XCTAssertEqual(result.modeledRange, .withinPhysicalEnvelopeModeLimitUnverified)
        }
    }

    func testBokehStopsDownWithoutPretendingTargetWasAchieved() throws {
        // EV 14.451211... is the independent golden boundary for f/8 at 1/350.
        let result = try bokeh(14.451211111832329)
        XCTAssertEqual(try XCTUnwrap(result.modeledAperture), 8, accuracy: 1e-12)
        XCTAssertEqual(result.modeledShutterSeconds, 1.0 / 350)
        XCTAssertEqual(result.target.range, .fasterThanShutterLimit)
        XCTAssertEqual(result.modeledRange, .withinPhysicalEnvelopeModeLimitUnverified)
    }

    func testBokehApertureBoundariesAndPhysicalBrightFailure() throws {
        // Golden constants independently evaluated with 40-digit decimal logarithms.
        let wideOpenBoundary = 12.065920955947537
        XCTAssertEqual(try bokeh(wideOpenBoundary).modeledAperture, 3.5)
        XCTAssertEqual(try bokeh(wideOpenBoundary - 1e-8).modeledAperture, 3.5)
        XCTAssertGreaterThan(try XCTUnwrap(bokeh(wideOpenBoundary + 1e-8).modeledAperture), 3.5)
        let smallestOpeningBoundary = 16.451211111832329
        XCTAssertEqual(try XCTUnwrap(bokeh(smallestOpeningBoundary).modeledAperture), 16, accuracy: 1e-12)
        XCTAssertNotNil(try bokeh(smallestOpeningBoundary - 1e-8).modeledAperture)
        let tooBright = try bokeh(smallestOpeningBoundary + 1e-8)
        XCTAssertEqual(tooBright.modeledRange, .beyondBrightLimit)
        XCTAssertNil(tooBright.modeledAperture)
        XCTAssertNil(tooBright.modeledShutterSeconds)
    }

    func testDimBokehAdvisoryAndUnknownModePolicy() throws {
        let dim = try bokeh(8)
        XCTAssertEqual(dim.target.shutterSeconds, 0.0478515625, accuracy: 1e-14)
        XCTAssertTrue(dim.needsSteadySupport)
        XCTAssertFalse(try bokeh(8, handheldSeconds: 0.1).needsSteadySupport)
        XCTAssertEqual(dim.modeledRange, .withinPhysicalEnvelopeModeLimitUnverified)
        XCTAssertNil(Pentax17Profile.bokehSlowestShutterSeconds)
        XCTAssertNil(Pentax17Profile.programSlowestShutterSeconds)
        let tooDim = try bokeh(0)
        XCTAssertEqual(tooDim.target.shutterSeconds, 12.25, accuracy: 1e-12)
        XCTAssertEqual(tooDim.modeledRange, .beyondSlowLimit)
        XCTAssertNil(tooDim.modeledShutterSeconds)
    }

    func testProgramNeverInventsAStoppedDownExposure() throws {
        let configuration = try ExposureConfiguration(cameraISO: 400, exposureCompensationEV: 0,
                                                       mode: .program(targetAperture: 8))
        let bright = try ExposureEngine.assess(sceneEV100: 15, configuration: configuration, ndStops: 0)
        XCTAssertEqual(bright.modeledRange, .beyondBrightLimit)
        XCTAssertNil(bright.modeledAperture)
        let filtered = try ExposureEngine.assess(sceneEV100: 15, configuration: configuration, ndStops: 3)
        XCTAssertEqual(filtered.target.shutterSeconds, 1.0 / 256)
        XCTAssertEqual(filtered.mode, .program(targetAperture: 8))
    }

    func testInvalidHandheldThresholdsAreRejected() {
        for threshold in [0, -1, .infinity, .nan] {
            XCTAssertThrowsError(try bokeh(15, handheldSeconds: threshold)) {
                XCTAssertEqual($0 as? ExposureError, .invalidHandheldThreshold)
            }
        }
    }

    func testPhoneSamplesNormalizeISOAndApplyCalibrationOnce() throws {
        // f/2, 1/1024, ISO 100 = EV12; ISO400 normalization subtracts two stops.
        XCTAssertEqual(try SceneExposure.ev100(phoneAperture: 2, phoneExposureSeconds: 1.0 / 1024,
                                               phoneISO: 100), 12, accuracy: 1e-12)
        XCTAssertEqual(try SceneExposure.ev100(phoneAperture: 2, phoneExposureSeconds: 1.0 / 1024,
                                               phoneISO: 400, calibrationOffsetEV: 0.5), 10.5, accuracy: 1e-12)
        // Arbitrary valid phone ISO is accepted, unlike the PENTAX dial choices.
        XCTAssertNoThrow(try SceneExposure.ev100(phoneAperture: 1.8, phoneExposureSeconds: 0.01, phoneISO: 123))
    }

    func testInvalidPhoneSamplesAndCalibrationFailExplicitly() {
        for invalid in [0, -1, Double.nan, .infinity] {
            XCTAssertThrowsError(try SceneExposure.ev100(phoneAperture: invalid, phoneExposureSeconds: 1, phoneISO: 100))
            XCTAssertThrowsError(try SceneExposure.ev100(phoneAperture: 2, phoneExposureSeconds: invalid, phoneISO: 100))
            XCTAssertThrowsError(try SceneExposure.ev100(phoneAperture: 2, phoneExposureSeconds: 1, phoneISO: invalid))
        }
        XCTAssertThrowsError(try SceneExposure.ev100(phoneAperture: 2, phoneExposureSeconds: 1,
                                                     phoneISO: 100, calibrationOffsetEV: .nan)) {
            XCTAssertEqual($0 as? ExposureError, .invalidCalibrationOffset)
        }
    }

    func testExposureRoundTripAndMonotonicityAcrossRealisticScenes() throws {
        for sceneEV100 in stride(from: 0.0, through: 20, by: 0.5) {
            for cameraISO in Pentax17Profile.supportedCameraISO {
                let base = try ProgramExposure.assess(sceneEV100: sceneEV100, cameraISO: cameraISO,
                                                      exposureCompensationEV: 0, targetAperture: 8, ndStops: 0)
                let recoveredEV = try SceneExposure.ev100(phoneAperture: 8, phoneExposureSeconds: base.shutterSeconds,
                                                          phoneISO: Double(cameraISO))
                XCTAssertEqual(recoveredEV, sceneEV100, accuracy: 1e-12)
                let brighter = try ProgramExposure.assess(sceneEV100: sceneEV100 + 1, cameraISO: cameraISO,
                                                          exposureCompensationEV: 0, targetAperture: 8, ndStops: 0)
                let narrower = try ProgramExposure.assess(sceneEV100: sceneEV100, cameraISO: cameraISO,
                                                          exposureCompensationEV: 0, targetAperture: 16, ndStops: 0)
                XCTAssertGreaterThanOrEqual(brighter.minimumNDStops, base.minimumNDStops)
                XCTAssertLessThanOrEqual(narrower.minimumNDStops, base.minimumNDStops)
                XCTAssertEqual(brighter.shutterSeconds * 2, base.shutterSeconds, accuracy: 1e-10)
            }
        }
    }
}
