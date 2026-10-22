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
        guard case let .candidate(candidate) = try result(model).recommendation else {
            throw ExposureError.unrepresentableExposure
        }
        return candidate
    }
    func testReferenceScenarioAndDefaults() async throws {
        let reference = model(); await reference.load()
        XCTAssertEqual(try recommended(reference).filter.stops, 3)
        XCTAssertEqual(try recommended(reference).exposure.target.shutterSeconds, 1.0 / 256)
        let firstLaunch = model(reference: false); await firstLaunch.load()
        XCTAssertEqual(firstLaunch.cameraMode, .bokeh)
        XCTAssertEqual(firstLaunch.cameraISO, 100)
        XCTAssertEqual(try recommended(firstLaunch).filter.stops, 3)
    }
    func testSettingsRecalculateHeldReadingWithoutChangingTimestamp() async throws {
        let model = model(); await model.load(); model.hold()
        let held = model.reading
        model.cameraMode = .bokeh
        XCTAssertEqual(try recommended(model).filter.stops, 5)
        model.compensationThirds = 3
        XCTAssertEqual(try recommended(model).filter.stops, 4)
        model.cameraISO = 100
        XCTAssertEqual(try recommended(model).filter.stops, 2)
        XCTAssertEqual(model.reading, held)
        XCTAssertEqual(model.kind, .held)
    }
    func testSlowSpeedSharesProgramTargetAndPreservesHeldReadingAndFilter() async throws {
        let model = model(); await model.load(); model.hold()
        model.programAperture = 11
        model.selectedFilter = NDFilter.catalog.first { $0.stops == 3 }
        let held = model.reading
        let program = try result(model)
        model.cameraMode = .slowSpeed
        XCTAssertEqual(model.targetAperture, 11)
        XCTAssertEqual(try result(model).exactMinimumStops, program.exactMinimumStops)
        XCTAssertEqual(try result(model).selected?.exposure.target, program.selected?.exposure.target)
        model.programAperture = 8
        XCTAssertEqual(try recommended(model).filter.stops, 3)
        XCTAssertEqual(try recommended(model).exposure.target.shutterSeconds, 1.0 / 256)
        XCTAssertEqual(model.reading, held)
        XCTAssertEqual(model.kind, .held)
        model.cameraMode = .bokeh
        XCTAssertEqual(model.targetAperture, 3.5)
        model.cameraMode = .program
        XCTAssertEqual(model.targetAperture, 8)
        XCTAssertEqual(model.selectedFilter?.stops, 3)
    }

    func testManualSelectionAndAutomaticRestoreRemainSeparate() async throws {
        let model = model(); await model.load()
        model.selectedFilter = NDFilter.catalog[0]
        XCTAssertEqual(try result(model).selected?.exposure.target.range, .fasterThanShutterLimit)
        XCTAssertEqual(try recommended(model).filter.stops, 3)
        model.selectedFilter = nil
        XCTAssertNil(try result(model).selected)
        model.programAperture = 16
        XCTAssertEqual(try recommended(model).filter.stops, 1)
    }
    func testManualValidationAndResume() async throws {
        let model = model(); await model.load()
        let original = model.state
        for input in ["", "nan", "inf", "31", "-21", "hello"] {
            XCTAssertFalse(model.enterManualEV(input)); XCTAssertEqual(model.state, original)
        }
        XCTAssertTrue(model.enterManualEV("8,5"))
        XCTAssertEqual(model.kind, .manual)
        XCTAssertEqual(model.reading?.timestamp, Date(timeIntervalSince1970: 123))
        model.becameInactive(); XCTAssertEqual(model.kind, .manual)
        model.resume(); XCTAssertNil(model.calculation)
        await model.load(); XCTAssertEqual(model.kind, .simulated)
        XCTAssertEqual(model.reading?.sceneEV100, 15)
    }
    func testStaleAndHeldLifecycle() async {
        let model = model(); await model.load()
        model.becameInactive(); XCTAssertEqual(model.state, .stale); XCTAssertNil(model.calculation)
        model.becameActive(); await model.load(); model.hold()
        model.becameInactive(); XCTAssertEqual(model.kind, .held)
    }
    func testInvalidReadingAndCancellation() async {
        let invalid = model(ev: .nan); await invalid.load()
        guard case .failed = invalid.state else { return XCTFail("Expected failure") }
        XCTAssertNil(invalid.calculation)
        let cancelled = MeterViewModel(lightMeter: CancelledMeter()); await cancelled.load()
        XCTAssertEqual(cancelled.state, .idle)
    }
    func testSlowManualSceneHasNoAutomaticCandidate() async throws {
        let model = model(reference: false)
        XCTAssertTrue(model.enterManualEV("0"))
        XCTAssertEqual(try result(model).recommendation, .noMatch(.exposuresTooSlow))
        model.selectedFilter = NDFilter.catalog[0]
        XCTAssertEqual(try XCTUnwrap(result(model).selected).exposure.target.shutterSeconds, 12.25, accuracy: 1e-12)
    }
    func testPendingSampleCannotOverwriteManualInput() async {
        let meter = ControlledMeter()
        let model = MeterViewModel(lightMeter: meter)
        let task = Task { await model.load() }
        await meter.waitUntilRequested()
        XCTAssertEqual(model.state, .settling)
        XCTAssertNil(model.calculation)
        XCTAssertTrue(model.enterManualEV("10"))
        await meter.complete()
        await task.value
        XCTAssertEqual(model.kind, .manual)
        XCTAssertEqual(model.reading?.sceneEV100, 10)
    }
    func testBackgroundInvalidatesPendingSample() async {
        let meter = ControlledMeter()
        let model = MeterViewModel(lightMeter: meter)
        let task = Task { await model.load() }
        await meter.waitUntilRequested()
        model.becameInactive()
        await meter.complete()
        await task.value
        XCTAssertEqual(model.state, .stale)
        XCTAssertNil(model.calculation)
    }
    func testFormattingDoesNotOverflowForExtremeManualExposures() {
        XCTAssertEqual(ExposureFormatting.shutter(1.0 / 256), "≈ 1/256 s")
        XCTAssertFalse(ExposureFormatting.shutter(1e-30).isEmpty)
    }
}
private struct CancelledMeter: SingleReadingLightMeter {
    func reading() async throws -> ExposureReading { throw CancellationError() }
}

/// Explicit test handshake exercises superseded asynchronous completions without sleeps.
private actor ControlledMeter: SingleReadingLightMeter {
    private var pending: CheckedContinuation<ExposureReading, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func reading() async throws -> ExposureReading {
        await withCheckedContinuation { continuation in
            pending = continuation
            started?.resume()
            started = nil
        }
    }
    func waitUntilRequested() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func complete() {
        pending?.resume(returning: ExposureReading(sceneEV100: 15,
            timestamp: Date(timeIntervalSince1970: 0), source: .simulated))
        pending = nil
    }
}
