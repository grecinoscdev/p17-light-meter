import XCTest
@testable import P17LightMeter

final class ReadingStabilityTests: XCTestCase {
    private let timestamp = Date(timeIntervalSince1970: 100)

    func testStableWindowPublishesMedianWithCameraProvenance() {
        var filter = ReadingStability(seconds: 0)
        for (index, ev) in [10.0, 10.1, 9.95].enumerated() {
            XCTAssertEqual(filter.accept(sceneEV100: ev, adjusting: false, exposureLimited: false,
                seconds: Double(index) * 0.25, timestamp: timestamp), .settling)
        }
        let result = filter.accept(sceneEV100: 10.05, adjusting: false, exposureLimited: false, seconds: 0.75, timestamp: timestamp)
        guard case let .reading(reading) = result else { return XCTFail("Expected stable median") }
        XCTAssertEqual(reading.sceneEV100, 10.025, accuracy: 1e-12)
        XCTAssertEqual(reading.source, .camera)
        XCTAssertEqual(reading.timestamp, timestamp)
    }

    func testInvalidAdjustingAndLimitedSamplesCannotBecomeLiveAndTimeoutIsBounded() {
        for input in [(Double.nan, false, false), (10, true, false), (10, false, true)] {
            var filter = ReadingStability(seconds: 0)
            for seconds in [0.0, 0.25, 0.5, 0.75, 2.99] {
                XCTAssertEqual(filter.accept(sceneEV100: input.0, adjusting: input.1, exposureLimited: input.2,
                    seconds: seconds, timestamp: timestamp), .settling)
            }
            guard case .unavailable = filter.accept(sceneEV100: input.0, adjusting: input.1, exposureLimited: input.2,
                seconds: 3, timestamp: timestamp) else { return XCTFail("Must stop presenting a spinner after 3 seconds") }
        }
    }

    func testNoiseAndSceneJumpInvalidateWindowThenRecover() {
        var filter = ReadingStability(seconds: 0)
        for index in 0...12 {
            let event = filter.accept(sceneEV100: index.isMultiple(of: 2) ? 10 : 11, adjusting: false,
                exposureLimited: false, seconds: Double(index) * 0.25, timestamp: timestamp)
            if case .reading = event { XCTFail("Flickering samples must not look stable") }
            if index == 12 { guard case .unavailable = event else { return XCTFail("Expected timeout") } }
        }
        for seconds in [3.25, 3.5, 3.75, 4.0] {
            let event = filter.accept(sceneEV100: 15, adjusting: false, exposureLimited: false, seconds: seconds, timestamp: timestamp)
            if seconds == 4 { guard case .reading = event else { return XCTFail("Must recover without retry") } }
        }
        XCTAssertEqual(filter.accept(sceneEV100: 8, adjusting: false, exposureLimited: false, seconds: 4.25, timestamp: timestamp), .settling)
    }

    func testGapRequiresNewWindowAndSamplesCannotSettleTooQuickly() {
        var filter = ReadingStability(seconds: 0)
        for seconds in [0.0, 0.1, 0.2, 0.3] {
            XCTAssertEqual(filter.accept(sceneEV100: 10, adjusting: false, exposureLimited: false,
                seconds: seconds, timestamp: timestamp), .settling)
        }
        XCTAssertEqual(filter.accept(sceneEV100: 10, adjusting: false, exposureLimited: false,
            seconds: 2, timestamp: timestamp), .settling)
    }
}
