import XCTest
import Observation
@testable import P17LightMeter

/// Explicitly controlled preview and request responses; no camera or timing sleeps.
struct SceneTestMeter: LightMeter {
    let stream: AsyncThrowingStream<MeterEvent, Error>
    let continuation: AsyncThrowingStream<MeterEvent, Error>.Continuation
    init(onTermination: (@Sendable () -> Void)? = nil) {
        (stream, continuation) = AsyncThrowingStream.makeStream(bufferingPolicy: .bufferingNewest(16))
        continuation.onTermination = { _ in onTermination?() }
    }
    func events() async -> AsyncThrowingStream<MeterEvent, Error> { stream }
    func requestReading(id: UUID) async {}
}

@MainActor
extension XCTestCase {
    func startPreview(_ model: MeterViewModel, meter: SceneTestMeter) async -> Task<Void, Never> {
        let started = expectation(description: "Preview subscription started")
        withObservationTracking { _ = model.state } onChange: { started.fulfill() }
        let task = Task { await model.load() }
        await fulfillment(of: [started], timeout: 3)
        await sendEvent(.awaitingReading, model: model, meter: meter)
        return task
    }
    func sendEvent(_ event: MeterEvent, model: MeterViewModel, meter: SceneTestMeter) async {
        let changed = expectation(description: "Event changed presentation state")
        withObservationTracking { _ = model.state } onChange: { changed.fulfill() }
        meter.continuation.yield(event)
        await fulfillment(of: [changed], timeout: 3)
    }
    func sendMeasurement(_ reading: ExposureReading, model: MeterViewModel, meter: SceneTestMeter) async {
        var requestedReading = reading
        requestedReading.requestID = model.measurementRequestID
        await sendEvent(.reading(requestedReading), model: model, meter: meter)
    }
}
