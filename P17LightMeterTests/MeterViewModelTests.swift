import XCTest
import ExposureCore
@testable import P17LightMeter

@MainActor
final class MeterViewModelTests: XCTestCase {
    private func model(reference: Bool = true, ev: Double = 15) -> MeterViewModel {
        MeterViewModel(lightMeter: FakeLightMeter(sample: ExposureReading(sceneEV100: ev,
            timestamp: Date(timeIntervalSince1970: 0), source: .simulated)),
            now: { Date(timeIntervalSince1970: 123) }, referenceScenario: reference)
    }
    private func result(_ model: MeterViewModel) throws -> NDRecommendation {
        try XCTUnwrap(model.calculation).get()
    }
    private func recommended(_ model: MeterViewModel) throws -> FilterAssessment {
        try XCTUnwrap(model.recommendedAssessment)
    }
    func testProgramPortraitDefaultsAndExplicitReferenceReading() async throws {
        let reference = model()
        XCTAssertNil(reference.reading)
        reference.readScene(); await reference.load()
        XCTAssertEqual(try recommended(reference).filter.stops, 3)
        XCTAssertEqual(try recommended(reference).exposure.target.shutterSeconds, 1.0 / 256)
        let firstLaunch = model(reference: false)
        XCTAssertEqual(firstLaunch.cameraMode, .program)
        XCTAssertEqual(firstLaunch.guideOrientation, .portrait)
        XCTAssertEqual(firstLaunch.cameraISO, 100)
        firstLaunch.readScene(); await firstLaunch.load()
        XCTAssertEqual(try recommended(firstLaunch).filter.stops, 1)
    }
    func testSettingsRecalculateSnapshotWithoutChangingTimestamp() async throws {
        let model = model(); model.readScene(); await model.load()
        let measured = model.reading
        model.cameraMode = .bokeh
        XCTAssertEqual(try recommended(model).filter.stops, 5)
        model.compensationThirds = 3
        XCTAssertEqual(try recommended(model).filter.stops, 4)
        model.cameraISO = 100
        XCTAssertEqual(try recommended(model).filter.stops, 2)
        model.toggleGuideOrientation()
        XCTAssertEqual(model.guideOrientation, .landscape)
        XCTAssertEqual(model.reading, measured)
        model.toggleGuideOrientation()
        XCTAssertEqual(model.guideOrientation, .portrait)
    }
    func testSlowSpeedSharesProgramTargetAndPreservesSnapshotAndFilter() async throws {
        let model = model(); model.readScene(); await model.load()
        model.programAperture = 11
        model.selectedFilter = NDFilter.catalog.first { $0.stops == 3 }
        let measured = model.reading
        let program = try result(model)
        model.cameraMode = .slowSpeed
        XCTAssertEqual(try result(model).exactMinimumStops, program.exactMinimumStops)
        XCTAssertEqual(try result(model).selected?.exposure.target, program.selected?.exposure.target)
        model.programAperture = 8
        XCTAssertEqual(try recommended(model).filter.stops, 3)
        XCTAssertEqual(model.reading, measured)
        model.cameraMode = .bokeh
        XCTAssertEqual(model.targetAperture, 3.5)
        model.cameraMode = .program
        XCTAssertEqual(model.targetAperture, 8)
        XCTAssertEqual(model.selectedFilter?.stops, 3)
    }
    func testSelectedAndRecommendedFiltersRemainSeparate() async throws {
        let model = model(); model.readScene(); await model.load()
        model.selectedFilter = NDFilter.catalog[0]
        XCTAssertEqual(try result(model).selected?.exposure.target.range, .fasterThanShutterLimit)
        XCTAssertEqual(try recommended(model).filter.stops, 3)
        model.selectedFilter = nil
        XCTAssertNil(try result(model).selected)
        model.programAperture = 16
        XCTAssertEqual(try recommended(model).filter.stops, 1)
    }
    func testManualValidationAndExplicitReread() async {
        let model = model(); model.readScene(); await model.load()
        let original = model.state
        for input in ["", "nan", "inf", "31", "-21", "hello"] {
            XCTAssertFalse(model.enterManualEV(input)); XCTAssertEqual(model.state, original)
        }
        XCTAssertTrue(model.enterManualEV("8,5"))
        XCTAssertEqual(model.kind, .manual)
        XCTAssertEqual(model.reading?.timestamp, Date(timeIntervalSince1970: 123))
        model.becameInactive(); XCTAssertEqual(model.kind, .manual)
        model.becameActive()
        XCTAssertEqual(model.reading?.sceneEV100, 8.5)
        model.readScene(); await model.load()
        XCTAssertEqual(model.kind, .simulated)
        XCTAssertEqual(model.reading?.sceneEV100, 15)
    }
    func testInvalidRequestedReadingShowsFailure() async {
        let invalid = model(ev: .nan); invalid.readScene(); await invalid.load()
        guard case .failed = invalid.state else { return XCTFail("Expected failure") }
        XCTAssertNil(invalid.calculation)
        XCTAssertFalse(invalid.isReadingScene)
    }
    func testSlowManualBokehSceneHasNoCandidate() throws {
        let model = model(reference: false)
        model.cameraMode = .bokeh
        XCTAssertTrue(model.enterManualEV("0"))
        XCTAssertEqual(try result(model).recommendation, .noMatch(.exposuresTooSlow))
        model.selectedFilter = NDFilter.catalog[0]
        XCTAssertEqual(try XCTUnwrap(result(model).selected).exposure.target.shutterSeconds, 12.25, accuracy: 1e-12)
    }
    func testFormattingDoesNotOverflowForExtremeManualExposures() {
        XCTAssertEqual(ExposureFormatting.shutter(1.0 / 256), "≈ 1/256 s")
        XCTAssertFalse(ExposureFormatting.shutter(1e-30).isEmpty)
    }
}
