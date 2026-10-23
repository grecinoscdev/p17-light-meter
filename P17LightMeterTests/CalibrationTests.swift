import XCTest
@testable import P17LightMeter

@MainActor
final class CalibrationTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 100)
    private let context = CameraContext(deviceIdentifier: "phone", cameraIdentifier: "wide", configurationIdentifier: "v1")
    func testCorrectionSignExactlyOnceReloadMismatchAndReset() async throws {
        let store = TestSettingsStore(); let meter = SceneTestMeter(); let timestamp = date
        let model = MeterViewModel(lightMeter: meter, now: { timestamp }, settingsStore: store)
        await model.restoreSettings()
        let task = await startPreview(model, meter: meter)
        defer { task.cancel() }
        let raw = ExposureReading(sceneEV100: 12, timestamp: date, source: .camera, cameraContext: context)
        model.readScene()
        await sendMeasurement(raw, model: model, meter: meter)
        let sample = try XCTUnwrap(model.calibrationSample())
        XCTAssertTrue(model.saveCalibration(sample: sample, referenceEV100: 13.25))
        XCTAssertEqual(model.reading?.sceneEV100, 13.25)
        XCTAssertEqual(model.rawReading?.sceneEV100, 12)
        XCTAssertTrue(model.saveCalibration(sample: sample, referenceEV100: 11.5))
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
            var changed = raw; changed.cameraContext = differentContext
            model.readScene()
            await sendMeasurement(changed, model: model, meter: meter)
            XCTAssertEqual(model.reading?.sceneEV100, 12)
            XCTAssertFalse(model.saveCalibration(sample: sample, referenceEV100: 13))
            XCTAssertTrue(model.calibrationStatus.contains("inactive"))
        }
        model.resetCalibration(); await model.flushPendingSaves()
        let saved = await store.settings
        XCTAssertNil(saved?.calibration)
    }
    func testCalibrationRejectsMissingIdentityAndExpiredMeasuredSnapshot() async {
        let meter = SceneTestMeter(); let clock = CalibrationClock(date)
        let model = MeterViewModel(lightMeter: meter, now: { clock.date })
        let task = await startPreview(model, meter: meter)
        defer { task.cancel() }
        model.readScene()
        await sendMeasurement(ExposureReading(sceneEV100: 12, timestamp: date, source: .camera), model: model, meter: meter)
        XCTAssertNil(model.calibrationSample())
        model.readScene()
        await sendMeasurement(ExposureReading(sceneEV100: 12, timestamp: date, source: .camera, cameraContext: context), model: model, meter: meter)
        XCTAssertNotNil(model.calibrationSample())
        clock.date = date.addingTimeInterval(301)
        XCTAssertNil(model.calibrationSample())
    }
    func testPendingManualAndSimulatedReadingsCannotCalibrate() async throws {
        let meter = SceneTestMeter(); let timestamp = date
        let model = MeterViewModel(lightMeter: meter, now: { timestamp })
        let task = await startPreview(model, meter: meter)
        defer { task.cancel() }
        model.readScene()
        await sendMeasurement(ExposureReading(sceneEV100: 12, timestamp: date, source: .camera, cameraContext: context), model: model, meter: meter)
        let sample = try XCTUnwrap(model.calibrationSample())
        XCTAssertFalse(model.saveCalibration(sample: sample, referenceEV100: .infinity))
        XCTAssertTrue(model.saveCalibration(sample: sample, referenceEV100: 13))
        XCTAssertEqual(model.reading?.sceneEV100, 13)
        model.readScene()
        XCTAssertNil(model.calibrationSample())
        XCTAssertFalse(model.saveCalibration(sample: sample, referenceEV100: 14))
        XCTAssertTrue(model.enterManualEV("12"))
        XCTAssertEqual(model.reading?.sceneEV100, 12)
        XCTAssertNil(model.calibrationSample())
        let demo = MeterViewModel(lightMeter: FakeLightMeter(sample: ExposureReading(sceneEV100: 12, timestamp: date, source: .simulated)))
        demo.readScene(); await demo.load()
        XCTAssertNil(demo.calibrationSample())
        XCTAssertFalse(demo.saveCalibration(sample: sample, referenceEV100: 13))
    }
}

@MainActor
private final class CalibrationClock {
    var date: Date
    init(_ date: Date) { self.date = date }
}
