import Foundation

/// Immutable measurement with explicit origin; stability is not calibration accuracy.
struct ExposureReading: Equatable, Sendable {
    enum Source: Sendable { case simulated, manual, camera }
    let sceneEV100: Double
    let timestamp: Date
    let source: Source
}

enum MeterEvent: Equatable, Sendable {
    case requestingPermission, starting, settling, stale, interrupted
    case denied
    case unavailable(String)
    case reading(ExposureReading)
    case pointMeteringSupported(Bool)
}

/// Each subscription owns capture until cancelled. Events never contain imagery.
protocol LightMeter: Sendable {
    func events() async -> AsyncThrowingStream<MeterEvent, Error>
}

/// Small adapter for deterministic single-reading demos and existing test fixtures.
protocol SingleReadingLightMeter: LightMeter {
    func reading() async throws -> ExposureReading
}
extension SingleReadingLightMeter {
    func events() async -> AsyncThrowingStream<MeterEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.reading(try await reading()))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
struct FakeLightMeter: SingleReadingLightMeter {
    let sample: ExposureReading
    func reading() async throws -> ExposureReading { sample }
}
