import XCTest
@testable import P17LightMeter

@MainActor
final class LiveMeterStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 100)
    private func reading(_ ev: Double = 15) -> ExposureReading {
        ExposureReading(sceneEV100: ev, timestamp: now, source: .camera)
    }
    private func model(_ meter: SceneTestMeter) -> MeterViewModel {
        let date = now
        return MeterViewModel(lightMeter: meter, now: { date })
    }
    func testStartupAndUnsolicitedFramesNeverTakeReading() async {
        let meter = SceneTestMeter(); let model = model(meter)
        let task = await startPreview(model, meter: meter)
        XCTAssertEqual(model.state, .awaitingReading)
        XCTAssertNil(model.reading)
        meter.continuation.yield(.reading(reading()))
        meter.continuation.finish(); await task.value
        XCTAssertNil(model.reading)
        XCTAssertNil(model.calculation)
    }
    func testOnePressAcceptsOnlyOneStableResultAndNextPressReplacesIt() async {
        let meter = SceneTestMeter(); let model = model(meter)
        let task = await startPreview(model, meter: meter)
        model.readScene()
        XCTAssertTrue(model.isReadingScene)
        XCTAssertFalse(model.canReadScene)
        let firstID = model.measurementRequestID
        model.readScene()
        XCTAssertEqual(model.measurementRequestID, firstID)
        await sendMeasurement(reading(), model: model, meter: meter)
        XCTAssertEqual(model.kind, .measured)
        XCTAssertFalse(model.isReadingScene)
        model.readScene()
        XCTAssertNotEqual(model.measurementRequestID, firstID)
        var late = reading(18); late.requestID = firstID
        meter.continuation.yield(.reading(late))
        await sendMeasurement(reading(12), model: model, meter: meter)
        var unsolicited = reading(20); unsolicited.requestID = model.measurementRequestID
        meter.continuation.yield(.reading(unsolicited))
        meter.continuation.finish(); await task.value
        XCTAssertEqual(model.reading?.sceneEV100, 12)
    }
    func testOldAndFutureCameraTimestampsCannotCompleteRequest() async {
        for timestamp in [now.addingTimeInterval(-1.01), now.addingTimeInterval(1)] {
            let meter = SceneTestMeter(); let model = model(meter)
            let task = await startPreview(model, meter: meter)
            model.readScene()
            await sendMeasurement(ExposureReading(sceneEV100: 15, timestamp: timestamp, source: .camera), model: model, meter: meter)
            XCTAssertEqual(model.state, .stale)
            XCTAssertNil(model.calculation)
            task.cancel(); await task.value
        }
    }
    func testManualEntryRejectsLateResultAndFailure() async {
        let meter = SceneTestMeter(); let model = model(meter)
        let task = await startPreview(model, meter: meter)
        model.readScene()
        var late = reading(); late.requestID = model.measurementRequestID
        XCTAssertTrue(model.enterManualEV("8"))
        meter.continuation.yield(.reading(late))
        meter.continuation.yield(.unavailable("Camera failed"))
        meter.continuation.finish(); await task.value
        XCTAssertEqual(model.kind, .manual)
        XCTAssertEqual(model.reading?.sceneEV100, 8)
    }
    func testBackgroundStopsPreviewButPreservesMeasuredSnapshot() async {
        let stopped = expectation(description: "Producer receives cancellation")
        let meter = SceneTestMeter(onTermination: { stopped.fulfill() }); let model = model(meter)
        let task = await startPreview(model, meter: meter)
        model.readScene()
        await sendMeasurement(reading(), model: model, meter: meter)
        let measured = model.reading
        model.becameInactive(); task.cancel(); await task.value
        await fulfillment(of: [stopped], timeout: 3)
        XCTAssertEqual(model.reading, measured)
        XCTAssertFalse(model.canReadScene)
        model.becameActive()
        XCTAssertEqual(model.reading, measured)
        XCTAssertFalse(model.isReadingScene)
    }
    func testBackgroundCancelsPendingRequestAndDoesNotAutoReadOnReturn() async {
        let meter = SceneTestMeter(); let model = model(meter)
        let task = await startPreview(model, meter: meter)
        model.readScene()
        model.becameInactive()
        task.cancel(); await task.value
        model.becameActive()
        XCTAssertNil(model.reading)
        XCTAssertFalse(model.isReadingScene)
    }
    func testFailureAndInterruptionEndRequestWithoutAutomaticRecoveryReading() async {
        for failure in [MeterEvent.interrupted, .stale, .unavailable("Unsettled"), .denied] {
            let meter = SceneTestMeter(); let model = model(meter)
            let task = await startPreview(model, meter: meter)
            model.readScene()
            await sendEvent(failure, model: model, meter: meter)
            XCTAssertFalse(model.isReadingScene)
            XCTAssertNil(model.reading)
            await sendEvent(.awaitingReading, model: model, meter: meter)
            meter.continuation.yield(.reading(reading()))
            meter.continuation.finish(); await task.value
            XCTAssertEqual(model.state, .awaitingReading)
            XCTAssertNil(model.reading)
        }
    }
}
