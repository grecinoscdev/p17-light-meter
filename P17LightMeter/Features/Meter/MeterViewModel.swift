import Foundation
import Observation
import ExposureCore

/// Owns the demo screen's state. The view owns the loading task, which is cancelled
/// when it disappears. No camera session or background sampling runs in this slice.
@MainActor @Observable
final class MeterViewModel {
    enum State: Equatable {
        case idle
        case loading
        case ready(ExposureReading, ProgramAssessment)
        case failed(String)
    }

    private(set) var state: State = .idle
    private let lightMeter: any LightMeter

    init(lightMeter: any LightMeter) { self.lightMeter = lightMeter }

    func load() async {
        guard state == .idle else { return }
        state = .loading
        do {
            let reading = try await lightMeter.reading()
            try Task.checkCancellation()
            let assessment = try ProgramExposure.assess(
                sceneEV100: reading.sceneEV100, cameraISO: 400,
                exposureCompensationEV: 0, targetAperture: 8, ndStops: 3
            )
            state = .ready(reading, assessment)
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed("The demo reading could not be calculated. Try again.")
        }
    }

    func retry() async {
        state = .idle
        await load()
    }
}
