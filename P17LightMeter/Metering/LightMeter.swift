import Foundation

/// Immutable measurement with explicit origin; demo data must never look live.
struct ExposureReading: Equatable, Sendable {
    enum Source: Sendable { case simulated }
    let sceneEV100: Double
    let timestamp: Date
    let source: Source
}

/// One-shot boundary for the foundation slice. M3 will add capture lifecycle and
/// streaming states here without moving camera access into the presentation layer.
protocol LightMeter: Sendable {
    func reading() async throws -> ExposureReading
}

struct FakeLightMeter: LightMeter {
    let sample: ExposureReading

    func reading() async throws -> ExposureReading { sample }
}
