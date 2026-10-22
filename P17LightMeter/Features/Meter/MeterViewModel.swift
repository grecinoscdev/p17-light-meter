import Foundation
import Observation
import ExposureCore

/// Main-actor owner of screen inputs and accepted readings. SwiftUI owns each
/// sampling task via requestID; generation checks discard superseded completions.
@MainActor @Observable
final class MeterViewModel {
    enum ReadingKind: Equatable { case simulated, live, held, manual }
    enum State: Equatable {
        case idle, requestingPermission, starting, settling, stale, denied, interrupted
        case ready(ExposureReading, ReadingKind)
        case failed(String)
    }
    private(set) var state: State = .idle
    private(set) var requestID = 0
    enum CameraMode: String, CaseIterable, Identifiable {
        case program = "P / Program"
        case bokeh = "Bokeh"
        case slowSpeed = "Slow-speed"
        var id: Self { self }
    }
    var cameraMode: CameraMode = .bokeh
    var cameraISO = 100
    var compensationThirds = 0
    // Shared target preference: Slow-speed currently has the same behavior as Program.
    var programAperture = 8.0
    var selectedFilter: NDFilter?
    var showsGrid = true
    let camera: CameraLightMeter?
    private(set) var supportsPointMetering = false
    private(set) var centerResetID = 0
    private var awaitsPointReset = false
    private let lightMeter: any LightMeter
    private let now: () -> Date

    init(lightMeter: any LightMeter, now: @escaping () -> Date = Date.init, referenceScenario: Bool = false, camera: CameraLightMeter? = nil) {
        self.camera = camera
        self.lightMeter = lightMeter
        self.now = now
        if referenceScenario { cameraMode = .program; cameraISO = 400 }
    }

    var canChooseMeteringPoint: Bool {
        guard supportsPointMetering else { return false }
        return kind == .live || state == .settling
    }

    var exposureMode: ExposureMode {
        switch cameraMode {
        case .bokeh: .bokeh
        case .program: .program(targetAperture: programAperture)
        case .slowSpeed: .slowSpeed(targetAperture: programAperture)
        }
    }
    var targetAperture: Double { exposureMode.targetAperture }
    var reading: ExposureReading? {
        guard case let .ready(reading, _) = state else { return nil }
        return reading
    }
    var kind: ReadingKind? {
        guard case let .ready(_, kind) = state else { return nil }
        return kind
    }
    var calculation: Result<NDRecommendation, Error>? {
        guard let reading else { return nil }
        return Result {
            let configuration = try ExposureConfiguration(
                cameraISO: cameraISO, exposureCompensationEV: Double(compensationThirds) / 3,
                mode: exposureMode)
            return try NDRecommendationEngine.recommend(sceneEV100: reading.sceneEV100,
                configuration: configuration, inventory: NDFilter.catalog, selectedFilter: selectedFilter)
        }
    }

    func load() async {
        guard state == .idle else { return }
        let generation = requestID
        state = .settling
        do {
            let events = await lightMeter.events()
            for try await event in events {
                try Task.checkCancellation()
                guard generation == requestID else { return }
                switch event {
                case .requestingPermission: state = .requestingPermission
                case .starting: state = .starting
                case .settling:
                    awaitsPointReset = false
                    state = .settling
                case .stale: state = .stale
                case .denied: state = .denied
                case .interrupted: state = .interrupted
                case let .unavailable(message): state = .failed(message)
                case let .pointMeteringSupported(supported): supportsPointMetering = supported
                case let .reading(sample):
                    if awaitsPointReset { continue }
                    guard sample.sceneEV100.isFinite else { throw ExposureError.invalidSceneEV }
                    if sample.source == .camera {
                        let ageSeconds = now().timeIntervalSince(sample.timestamp)
                        guard (0...ReadingStability.staleInterval).contains(ageSeconds) else {
                            state = .stale
                            continue
                        }
                    }
                    state = .ready(sample, sample.source == .camera ? .live : .simulated)
                }
            }
            if generation == requestID, Task.isCancelled || kind == .live { state = .stale }
        } catch is CancellationError {
            if generation == requestID { state = .idle }
        } catch {
            if generation == requestID { state = .failed("The reading is unavailable. Retry or enter a manual EV.") }
        }
    }

    func hold() {
        guard case let .ready(reading, kind) = state, kind == .live || kind == .simulated else { return }
        requestID += 1
        state = .ready(reading, .held)
    }

    func pointWillChange() {
        guard canChooseMeteringPoint else { return }
        awaitsPointReset = true
        state = .settling
    }

    func meterAtCenter() {
        guard canChooseMeteringPoint else { return }
        centerResetID += 1
        pointWillChange()
        camera?.meter(at: CGPoint(x: 0.5, y: 0.5))
    }

    func resume() {
        awaitsPointReset = false
        supportsPointMetering = false
        centerResetID += 1
        requestID += 1
        state = .idle
    }

    /// Manual planning is bounded to −20…30 EV100 to keep entry mistakes explicit.
    /// Invalid text leaves the accepted reading and pending request untouched.
    func enterManualEV(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let ev = Double(normalized), ev.isFinite, (-20...30).contains(ev) else { return false }
        requestID += 1
        state = .ready(ExposureReading(sceneEV100: ev, timestamp: now(), source: .manual), .manual)
        return true
    }

    func becameInactive() {
        if kind == .held || kind == .manual { return }
        requestID += 1
        state = .stale
    }

    func becameActive() {
        if state == .stale { resume() }
    }
}
