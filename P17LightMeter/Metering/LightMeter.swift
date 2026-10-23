import Foundation

/// Immutable measurement with explicit origin; stability is not calibration accuracy.
struct ExposureReading: Equatable, Sendable {
    enum Source: Sendable { case simulated, manual, camera }
    let sceneEV100: Double
    let timestamp: Date
    let source: Source
    // Correlates the result to an explicit Read Scene command; never persisted.
    var requestID: UUID? = nil
    var cameraContext: CameraContext? = nil
}

enum MeterEvent: Equatable, Sendable {
    case requestingPermission, starting, awaitingReading, settling, stale, interrupted
    case denied
    case unavailable(String)
    case reading(ExposureReading)
    case pointMeteringSupported(Bool)
    case previewFormat(CameraPreviewFormat?)
    case cameraContext(CameraContext?)
}

/// Each subscription owns capture until cancelled. Events never contain imagery.
protocol LightMeter: Sendable {
    func events() async -> AsyncThrowingStream<MeterEvent, Error>
    func requestReading(id: UUID) async
}

/// Deterministic one-request source for app tests. Subscription alone never reads.
actor FakeLightMeter: LightMeter {
    let sample: ExposureReading
    private var continuation: AsyncThrowingStream<MeterEvent, Error>.Continuation?
    init(sample: ExposureReading) { self.sample = sample }
    func events() -> AsyncThrowingStream<MeterEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream<MeterEvent, Error>.makeStream()
        self.continuation = continuation
        continuation.yield(.awaitingReading)
        return stream
    }
    func requestReading(id: UUID) {
        var reading = sample
        reading.requestID = id
        continuation?.yield(.reading(reading))
        continuation?.finish()
        continuation = nil
    }
}
