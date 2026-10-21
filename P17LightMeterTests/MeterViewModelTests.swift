import XCTest
@testable import P17LightMeter

@MainActor
final class MeterViewModelTests: XCTestCase {
    func testFakeReadingReachesPresentationWithoutLosingItsOrigin() async {
        let sample = ExposureReading(sceneEV100: 15, timestamp: Date(timeIntervalSince1970: 0), source: .simulated)
        let model = MeterViewModel(lightMeter: FakeLightMeter(sample: sample))
        await model.load()
        guard case let .ready(reading, assessment) = model.state else {
            return XCTFail("Expected a calculated demo result")
        }
        XCTAssertEqual(reading, sample)
        XCTAssertEqual(assessment.shutterSeconds, 1.0 / 256.0, accuracy: 1e-12)
        XCTAssertEqual(ExposureFormatting.shutter(assessment.shutterSeconds), "≈ 1/256 s")
    }

    func testInvalidReadingShowsFailureInsteadOfDemoDefaults() async {
        let model = MeterViewModel(lightMeter: FakeLightMeter(sample:
            ExposureReading(sceneEV100: .nan, timestamp: Date(), source: .simulated)))
        await model.load()
        guard case .failed = model.state else { return XCTFail("Expected explicit failure") }
    }

    func testCancellationReturnsToIdle() async {
        let model = MeterViewModel(lightMeter: CancelledMeter())
        await model.load()
        XCTAssertEqual(model.state, .idle)
    }
}

private struct CancelledMeter: LightMeter {
    func reading() async throws -> ExposureReading { throw CancellationError() }
}
