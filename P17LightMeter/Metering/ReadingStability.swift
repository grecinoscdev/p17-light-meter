import Foundation

/// Pure temporal filter. Call with monotonic seconds, not wall-clock time.
/// Four samples spanning 0.75 seconds must fit within 0.2 EV before publishing
/// their median. These initial repeatability thresholds need hardware tuning;
/// they make no claim about absolute accuracy. A jump invalidates the old window.
struct ReadingStability {
    static let sampleInterval = 0.25
    static let staleInterval = 1.0
    static let settlingTimeout = 3.0
    static let maximumSpreadEV = 0.2
    private var samples: [(seconds: Double, ev: Double)] = []
    private var unsettledSince: Double

    init(seconds: Double) { unsettledSince = seconds }

    mutating func accept(sceneEV100: Double?, adjusting: Bool, exposureLimited: Bool,
                         seconds: Double, timestamp: Date) -> MeterEvent {
        guard let sceneEV100, sceneEV100.isFinite, !adjusting, !exposureLimited else {
            samples.removeAll()
            return waiting(seconds: seconds, limited: exposureLimited)
        }
        if let previous = samples.last, seconds - previous.seconds > Self.staleInterval {
            samples.removeAll()
        }
        if samples.contains(where: { abs($0.ev - sceneEV100) > Self.maximumSpreadEV }) {
            samples.removeAll()
        }
        samples.append((seconds, sceneEV100))
        if samples.count > 4 { samples.removeFirst() }
        guard samples.count == 4, seconds - samples[0].seconds >= 0.75 else {
            return waiting(seconds: seconds, limited: false)
        }
        let sorted = samples.map(\.ev).sorted()
        let median = (sorted[1] + sorted[2]) / 2
        unsettledSince = seconds
        return .reading(ExposureReading(sceneEV100: median, timestamp: timestamp, source: .camera))
    }

    private func waiting(seconds: Double, limited: Bool) -> MeterEvent {
        guard seconds - unsettledSince >= Self.settlingTimeout else { return .settling }
        if limited { return .unavailable("The phone cannot expose this light level reliably. Change the lighting or enter a manual EV.") }
        return .unavailable("Light is not stable yet. Keep the phone still and aim at an evenly lit area. Metering will recover automatically.")
    }
}
