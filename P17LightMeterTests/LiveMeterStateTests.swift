import XCTest
import Observation
@testable import P17LightMeter

@MainActor
final class LiveMeterStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 100)

    private func start(_ model: MeterViewModel) async -> Task<Void, Never> {
        let started = expectation(description: "Subscription started")
        withObservationTracking { _ = model.state } onChange: { started.fulfill() }
        let task = Task { await model.load() }
        await fulfillment(of: [started], timeout: 2)
        return task
    }

    private func deliver(_ event: MeterEvent, through meter: StreamMeter, to model: MeterViewModel) async {
        let changed = expectation(description: "State changed after meter event")
        withObservationTracking { _ = model.state } onChange: { changed.fulfill() }
        meter.continuation.yield(event)
        await fulfillment(of: [changed], timeout: 2)
    }

    func testPermissionInterruptionFailureAndStaleRemoveRecommendationsAndRecover() async {
        let meter = StreamMeter()
        let date = now
        let model = MeterViewModel(lightMeter: meter, now: { date })
        let task = await start(model)
        let reading = ExposureReading(sceneEV100: 15, timestamp: date, source: .camera)
        for event in [MeterEvent.requestingPermission, .denied, .starting, .settling, .reading(reading),
                      .interrupted, .settling, .reading(reading), .stale, .unavailable("Retry"), .reading(reading)] {
            await deliver(event, through: meter, to: model)
            if case .reading = event {
                XCTAssertEqual(model.kind, .live)
                XCTAssertNotNil(model.calculation)
            } else { XCTAssertNil(model.calculation) }
        }
        task.cancel(); await task.value
        XCTAssertNil(model.calculation)
    }

    func testOldAndFutureCameraTimestampsCannotBeCurrent() async {
        for timestamp in [now.addingTimeInterval(-1.01), now.addingTimeInterval(1)] {
            let meter = StreamMeter()
            let date = now
            let model = MeterViewModel(lightMeter: meter, now: { date })
            let task = await start(model)
            await deliver(.reading(ExposureReading(sceneEV100: 15, timestamp: timestamp, source: .camera)), through: meter, to: model)
            XCTAssertEqual(model.state, .stale)
            XCTAssertNil(model.calculation)
            task.cancel(); await task.value
        }
    }

    func testHeldCameraReadingRetainsProvenanceAndRejectsLateEvents() async {
        let meter = StreamMeter()
        let date = now
        let model = MeterViewModel(lightMeter: meter, now: { date })
        let task = await start(model)
        await deliver(.reading(ExposureReading(sceneEV100: 15, timestamp: date, source: .camera)), through: meter, to: model)
        model.hold()
        meter.continuation.yield(.interrupted)
        meter.continuation.finish()
        await task.value
        XCTAssertEqual(model.kind, .held)
        XCTAssertEqual(model.reading?.source, .camera)
        XCTAssertEqual(model.reading?.timestamp, date)
        model.becameInactive()
        XCTAssertEqual(model.kind, .held)
    }

    func testCancellationTerminatesSubscriptionAndBackgroundRemovesLiveResult() async {
        let stopped = expectation(description: "Producer receives cancellation")
        let meter = StreamMeter(onTermination: { stopped.fulfill() })
        let date = now
        let model = MeterViewModel(lightMeter: meter, now: { date })
        let task = await start(model)
        await deliver(.reading(ExposureReading(sceneEV100: 15, timestamp: date, source: .camera)), through: meter, to: model)
        model.becameInactive()
        task.cancel() // SwiftUI cancels the old requestID task on the same transition.
        await task.value
        await fulfillment(of: [stopped], timeout: 2)
        XCTAssertEqual(model.state, .stale)
        XCTAssertNil(model.calculation)
        model.becameActive()
        XCTAssertEqual(model.state, .idle)
    }

    func testManualEntryRejectsLateCameraFailure() async {
        let meter = StreamMeter()
        let model = MeterViewModel(lightMeter: meter)
        let task = await start(model)
        XCTAssertTrue(model.enterManualEV("8"))
        meter.continuation.yield(.unavailable("Camera failed"))
        meter.continuation.finish()
        await task.value
        XCTAssertEqual(model.kind, .manual)
        XCTAssertEqual(model.reading?.sceneEV100, 8)
        XCTAssertNotNil(model.calculation)
    }

    func testEndedLiveStreamInvalidatesReading() async {
        let meter = StreamMeter()
        let date = now
        let model = MeterViewModel(lightMeter: meter, now: { date })
        let task = await start(model)
        await deliver(.reading(ExposureReading(sceneEV100: 15, timestamp: date, source: .camera)), through: meter, to: model)
        meter.continuation.finish()
        await task.value
        XCTAssertEqual(model.state, .stale)
    }
}

/// Bounded stream under test control: no camera and no sleeps.
private struct StreamMeter: LightMeter {
    let stream: AsyncThrowingStream<MeterEvent, Error>
    let continuation: AsyncThrowingStream<MeterEvent, Error>.Continuation
    init(onTermination: (@Sendable () -> Void)? = nil) {
        (stream, continuation) = AsyncThrowingStream.makeStream(bufferingPolicy: .bufferingNewest(8))
        continuation.onTermination = { _ in onTermination?() }
    }
    func events() async -> AsyncThrowingStream<MeterEvent, Error> { stream }
}
