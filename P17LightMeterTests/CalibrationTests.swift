import XCTest
import Observation
@testable import P17LightMeter

@MainActor
final class CalibrationTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 100)
    private let context = CameraContext(deviceIdentifier: "phone", cameraIdentifier: "wide", configurationIdentifier: "v1")
    private func deliver(_ reading: ExposureReading, meter: CalibrationMeter, model: MeterViewModel) async {
        let changed = expectation(description: "Reading accepted")
        withObservationTracking { _ = model.state } onChange: { changed.fulfill() }
        meter.continuation.yield(.reading(reading))
        await fulfillment(of: [changed], timeout: 2)
    }
    func testCorrectionSignExactlyOnceReloadMismatchAndReset() async throws {
        let store = TestSettingsStore()
        let meter = CalibrationMeter()
        let timestamp = date
        let model = MeterViewModel(lightMeter: meter, now: { timestamp }, settingsStore: store)
        await model.restoreSettings()
        let task = Task { await model.load() }
        defer { task.cancel() }
        // Wait for startup via an explicit stream event rather than an arbitrary sleep.
        await meter.started()
        let raw = ExposureReading(sceneEV100: 12, timestamp: date, source: .camera, cameraContext: context)
        await deliver(raw, meter: meter, model: model)
        XCTAssertTrue(model.saveCalibration(sample: raw, referenceEV100: 13.25))
        XCTAssertEqual(model.reading?.sceneEV100, 13.25)
        XCTAssertEqual(model.rawReading?.sceneEV100, 12)
        XCTAssertTrue(model.saveCalibration(sample: raw, referenceEV100: 11.5))
        XCTAssertEqual(model.calibration?.offsetEV, -0.5)
        XCTAssertEqual(model.reading?.sceneEV100, 11.5)
        await model.flushPendingSaves()
        let reloaded = MeterViewModel(lightMeter: meter, settingsStore: store)
        await reloaded.restoreSettings()
        XCTAssertEqual(reloaded.calibration, model.calibration)
        for differentContext in [
            CameraContext(deviceIdentifier: "other phone", cameraIdentifier: "wide", configurationIdentifier: "v1"),
            CameraContext(deviceIdentifier: "phone", cameraIdentifier: "other camera", configurationIdentifier: "v1"),
            CameraContext(deviceIdentifier: "phone", cameraIdentifier: "wide", configurationIdentifier: "v2")
        ] {
            var changed = raw
            changed.cameraContext = differentContext
            await deliver(changed, meter: meter, model: model)
            XCTAssertEqual(model.reading?.sceneEV100, 12)
            XCTAssertFalse(model.saveCalibration(sample: raw, referenceEV100: 13))
            XCTAssertTrue(model.calibrationStatus.contains("inactive"))
        }
        model.resetCalibration(); await model.flushPendingSaves()
        let saved = await store.settings
        XCTAssertNil(saved?.calibration)
    }
    func testCalibrationCaptureRejectsMissingIdentityAndAReadingThatAges() async {
        let meter = CalibrationMeter()
        let clock = CalibrationClock(date)
        let model = MeterViewModel(lightMeter: meter, now: { clock.date })
        let task = Task { await model.load() }
        defer { task.cancel() }
        await meter.started()
        let unidentified = ExposureReading(sceneEV100: 12, timestamp: date, source: .camera)
        await deliver(unidentified, meter: meter, model: model)
        XCTAssertNil(model.calibrationSample())
        let identified = ExposureReading(sceneEV100: 12, timestamp: date, source: .camera, cameraContext: context)
        await deliver(identified, meter: meter, model: model)
        XCTAssertNotNil(model.calibrationSample())
        clock.date = date.addingTimeInterval(1.01)
        XCTAssertNil(model.calibrationSample())
        XCTAssertFalse(model.saveCalibration(sample: identified, referenceEV100: 13))
    }
    func testOnlyFreshLiveCameraSamplesCanCalibrateAndManualNeverReceivesCorrection() async throws {
        let meter = CalibrationMeter()
        let timestamp = date
        let model = MeterViewModel(lightMeter: meter, now: { timestamp })
        let task = Task { await model.load() }
        defer { task.cancel() }
        await meter.started()
        let raw = ExposureReading(sceneEV100: 12, timestamp: date, source: .camera, cameraContext: context)
        await deliver(raw, meter: meter, model: model)
        XCTAssertNotNil(model.calibrationSample())
        XCTAssertFalse(model.saveCalibration(sample: raw, referenceEV100: .infinity))
        let old = ExposureReading(sceneEV100: 12, timestamp: date.addingTimeInterval(-301), source: .camera, cameraContext: context)
        XCTAssertFalse(model.saveCalibration(sample: old, referenceEV100: 13))
        XCTAssertTrue(model.saveCalibration(sample: raw, referenceEV100: 13))
        model.hold()
        XCTAssertEqual(model.reading?.sceneEV100, 13)
        XCTAssertNil(model.calibrationSample())
        XCTAssertFalse(model.saveCalibration(sample: raw, referenceEV100: 14))
        XCTAssertTrue(model.enterManualEV("12"))
        XCTAssertEqual(model.reading?.sceneEV100, 12)
        XCTAssertNil(model.calibrationSample())
        let demo = MeterViewModel(lightMeter: FakeLightMeter(sample: ExposureReading(sceneEV100: 12, timestamp: date, source: .simulated)))
        await demo.load()
        XCTAssertNil(demo.calibrationSample())
        XCTAssertFalse(demo.saveCalibration(sample: raw, referenceEV100: 13))
    }
}

/// Explicit subscription handshake keeps tests deterministic across slow simulators.
private actor CalibrationMeter: LightMeter {
    nonisolated let stream: AsyncThrowingStream<MeterEvent, Error>
    nonisolated let continuation: AsyncThrowingStream<MeterEvent, Error>.Continuation
    private var subscribed = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init() { (stream, continuation) = AsyncThrowingStream.makeStream() }
    func events() -> AsyncThrowingStream<MeterEvent, Error> {
        subscribed = true
        for waiter in waiters { waiter.resume() }; waiters.removeAll()
        return stream
    }
    func started() async {
        if subscribed { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

@MainActor
private final class CalibrationClock {
    var date: Date
    init(_ date: Date) { self.date = date }
}
