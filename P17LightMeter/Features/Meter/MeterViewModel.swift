import Foundation
import Observation
import ExposureCore

/// Main-actor owner of screen inputs and accepted readings. SwiftUI owns each
/// sampling task via requestID; generation checks discard superseded completions.
@MainActor @Observable
final class MeterViewModel {
    enum ReadingKind: Equatable { case simulated, measured, manual }
    enum State: Equatable {
        case idle, requestingPermission, starting, awaitingReading, settling, stale, denied, interrupted
        case ready(ExposureReading, ReadingKind)
        case failed(String)
    }
    private(set) var state: State = .idle
    private(set) var requestID = 0
    enum CameraMode: String, CaseIterable, Identifiable {
        case program
        case bokeh
        case slowSpeed
        var title: String {
            switch self {
            case .program: "P / Program"
            case .bokeh: "Bokeh"
            case .slowSpeed: "Slow-speed"
            }
        }
        var id: Self { self }
    }
    var cameraMode: CameraMode = .program { didSet { saveSettings() } }
    var cameraISO = 100 { didSet { saveSettings() } }
    var compensationThirds = 0 { didSet { saveSettings() } }
    // Shared target preference: Slow-speed currently has the same behavior as Program.
    var programAperture = 8.0 { didSet { saveSettings() } }
    var selectedFilter: NDFilter? { didSet { saveSettings() } }
    var showsGrid = true { didSet { saveSettings() } }
    let camera: CameraLightMeter?
    private(set) var supportsPointMetering = false
    private(set) var centerResetID = 0
    var guideOrientation: GuideOrientation = .portrait
    private(set) var previewFormat: CameraPreviewFormat?
    private(set) var isReadingScene = false
    private(set) var isPreviewReady = false
    private var currentCameraContext: CameraContext?
    private var streamActive = false
    private var isActive = true
    private var requestedAt: Date?
    private(set) var measurementRequestID: UUID?
    private var readingCommand: Task<Void, Never>?
    private let lightMeter: any LightMeter
    private let now: () -> Date

    init(lightMeter: any LightMeter, now: @escaping () -> Date = Date.init, referenceScenario: Bool = false, camera: CameraLightMeter? = nil, settingsStore: (any SettingsStore)? = nil) {
        self.settingsStore = settingsStore
        self.settingsReady = settingsStore == nil
        self.camera = camera
        self.lightMeter = lightMeter
        self.now = now
        if referenceScenario { cameraMode = .program; cameraISO = 400 }
    }

    var filmBoxISO: Int? { didSet { saveSettings() } }
    var useOwnedFilters = false {
        didSet {
            selectedFilter = nil
            saveSettings()
        }
    }
    private(set) var ownedFilters: [NDFilter] = []
    private(set) var calibration: CalibrationRecord?
    private(set) var settingsReady: Bool
    private(set) var isResettingSavedData = false
    private(set) var settingsMessage: String?
    private(set) var savedDataNeedsReset = false
    private let settingsStore: (any SettingsStore)?
    // Five minutes permits reference entry without reusing an old comparison later.
    private static let maximumCalibrationDraftAgeSeconds = 300.0
    private var restoring = false
    private var restoreTask: Task<SavedSettings?, Error>?
    private var pendingSettings: SavedSettings?
    private var saveTask: Task<Void, Never>?

    var availableFilters: [NDFilter] {
        guard useOwnedFilters else { return NDFilter.catalog }
        let noFilter = NDFilter.catalog.filter { $0.stops == 0 }
        return noFilter + ownedFilters.sorted { $0.stops < $1.stops }
    }
    var reading: ExposureReading? {
        guard let raw = rawReading else { return nil }
        guard raw.source == .camera, let calibration, raw.cameraContext == calibration.context else { return raw }
        return ExposureReading(sceneEV100: raw.sceneEV100 + calibration.offsetEV,
            timestamp: raw.timestamp, source: raw.source, requestID: raw.requestID, cameraContext: raw.cameraContext)
    }
    var calibrationStatus: String {
        guard let calibration else { return "Uncalibrated" }
        guard let raw = rawReading, raw.source == .camera else { return "Reference correction saved; waiting for a camera measurement" }
        return raw.cameraContext == calibration.context ? "Reference correction applied" : "Camera configuration changed; correction inactive"
    }
    /// Only an explicitly requested, settled camera measurement from this session
    /// and configuration can anchor a comparison, within the five-minute entry window.
    func calibrationSample() -> ExposureReading? {
        guard kind == .measured, !isReadingScene, let raw = rawReading, raw.source == .camera,
              currentCameraContext == raw.cameraContext,
              raw.cameraContext?.isValid == true,
              (0...Self.maximumCalibrationDraftAgeSeconds).contains(now().timeIntervalSince(raw.timestamp)) else { return nil }
        return raw
    }
    func saveCalibration(sample: ExposureReading, referenceEV100: Double) -> Bool {
        guard let current = calibrationSample(), current == sample,
              sample.source == .camera, let context = sample.cameraContext,
              (0...Self.maximumCalibrationDraftAgeSeconds).contains(now().timeIntervalSince(sample.timestamp)) else { return false }
        let record = CalibrationRecord(context: context, rawEV100: sample.sceneEV100,
            referenceEV100: referenceEV100, sampleTimestamp: sample.timestamp, savedAt: now())
        do { try record.validate() } catch { return false }
        calibration = record
        saveSettings()
        return true
    }
    func resetCalibration() {
        calibration = nil
        saveSettings()
    }

    func setOwned(_ filter: NDFilter, included: Bool) {
        guard (try? SavedFilter(filter).filter()) != nil else { return }
        ownedFilters.removeAll { $0.id == filter.id }
        if included, ownedFilters.count < 100 { ownedFilters.append(filter) }
        if useOwnedFilters, !availableFilters.contains(where: { $0.id == selectedFilter?.id }) { selectedFilter = nil }
        saveSettings()
    }
    func addCustomFilter(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let stops = Double(normalized), stops.isFinite, stops > 0,
              stops <= SavedSettings.maximumCustomStops, ownedFilters.count < 100,
              !ownedFilters.contains(where: { $0.stops == stops }),
              let filter = try? NDFilter(id: "custom-" + UUID().uuidString, stops: stops) else { return false }
        setOwned(filter, included: true)
        return true
    }
    private var snapshot: SavedSettings {
        var result = SavedSettings()
        result.mode = cameraMode.rawValue
        result.cameraISO = cameraISO
        result.filmBoxISO = filmBoxISO
        result.compensationThirds = compensationThirds
        result.programAperture = programAperture
        result.showsGrid = showsGrid
        result.useOwnedFilters = useOwnedFilters
        result.ownedFilters = ownedFilters.map(SavedFilter.init)
        result.selectedFilterID = selectedFilter?.id
        result.calibration = calibration
        return result
    }
    private func apply(_ settings: SavedSettings) throws {
        try settings.validate()
        restoring = true
        defer { restoring = false }
        // Program is the requested startup mode, even if the previous session
        // saved another mode. Keep decoding old mode fields for schema compatibility.
        cameraMode = .program
        cameraISO = settings.cameraISO
        filmBoxISO = settings.filmBoxISO
        compensationThirds = settings.compensationThirds
        programAperture = settings.programAperture
        showsGrid = settings.showsGrid
        ownedFilters = try settings.validatedFilters()
        useOwnedFilters = settings.useOwnedFilters
        selectedFilter = availableFilters.first { $0.id == settings.selectedFilterID }
        calibration = settings.calibration
    }
    func restoreSettings() async {
        guard !settingsReady, let settingsStore else { return }
        if restoreTask == nil { restoreTask = Task { try await settingsStore.load() } }
        do {
            let settings = try await restoreTask?.value
            guard !settingsReady else { return }
            if let settings { try apply(settings) }
        } catch {
            savedDataNeedsReset = true
            settingsMessage = "Saved data could not be read. Current settings are temporary. Reset saved data in Settings to enable saving."
        }
        settingsReady = true
    }
    /// One writer serializes snapshots; rapid edits coalesce without older saves winning.
    func saveSettings() {
        guard settingsReady, !isResettingSavedData, !restoring, !savedDataNeedsReset, let settingsStore else { return }
        pendingSettings = snapshot
        guard saveTask == nil else { return }
        saveTask = Task {
            while let next = pendingSettings {
                pendingSettings = nil
                do {
                    try await settingsStore.save(next)
                    settingsMessage = nil
                }
                catch { settingsMessage = "Changes could not be saved. Check available storage and retry in Settings." }
            }
            saveTask = nil
        }
    }
    func flushPendingSaves() async { await saveTask?.value }
    func resetSavedData() async {
        guard settingsReady, !isResettingSavedData else { return }
        // Keep restoration complete while reset awaits I/O: a foreground restart
        // must not reapply the original launch snapshot during this replacement.
        isResettingSavedData = true
        defer { isResettingSavedData = false }
        await flushPendingSaves()
        do {
            let defaults = SavedSettings()
            try await settingsStore?.save(defaults)
            try apply(defaults)
            savedDataNeedsReset = false
            settingsMessage = nil
        } catch { settingsMessage = "Saved data could not be reset. Check available storage and try again." }
    }

    var canChooseMeteringPoint: Bool { supportsPointMetering && isPreviewReady && !isReadingScene }
    var canReadScene: Bool {
        guard settingsReady, !isResettingSavedData, !isReadingScene, isActive else { return false }
        switch state {
        case .starting, .requestingPermission: return false
        default: return true
        }
    }

    var recommendedAssessment: FilterAssessment? {
        guard case let .success(result) = calculation,
              case let .candidate(candidate) = result.recommendation else { return nil }
        return candidate
    }

    var exposureMode: ExposureMode {
        switch cameraMode {
        case .bokeh: .bokeh
        case .program: .program(targetAperture: programAperture)
        case .slowSpeed: .slowSpeed(targetAperture: programAperture)
        }
    }
    var targetAperture: Double { exposureMode.targetAperture }
    var rawReading: ExposureReading? {
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
                configuration: configuration, inventory: availableFilters, selectedFilter: selectedFilter)
        }
    }

    /// Owns the preview subscription independently of the one-shot measurement.
    /// Accepted readings remain snapshots while subsequent preview frames arrive.
    func load() async {
        await restoreSettings()
        guard !Task.isCancelled, isActive, !streamActive else { return }
        let generation = requestID
        streamActive = true
        if reading == nil, !isReadingScene { state = .starting }
        defer {
            if generation == requestID {
                streamActive = false
                isPreviewReady = false
            }
        }
        do {
            let events = await lightMeter.events()
            for try await event in events {
                try Task.checkCancellation()
                guard generation == requestID else { return }
                switch event {
                case let .previewFormat(format): previewFormat = format
                case let .cameraContext(context): currentCameraContext = context
                case let .pointMeteringSupported(supported): supportsPointMetering = supported
                case .awaitingReading:
                    isPreviewReady = true
                    if isReadingScene { sendReadingCommand() }
                    else if reading == nil { state = .awaitingReading }
                case .requestingPermission: showPreviewState(.requestingPermission)
                case .starting: showPreviewState(.starting)
                case .settling:
                    if isReadingScene { state = .settling }
                case .stale: failRequest(.stale)
                case .denied: failRequest(.denied)
                case .interrupted: failRequest(.interrupted)
                case let .unavailable(message): failRequest(.failed(message))
                case let .reading(sample):
                    // Unsolicited or late samples never replace a measured/manual value.
                    guard isReadingScene, sample.requestID == measurementRequestID else { continue }
                    guard sample.sceneEV100.isFinite else { throw ExposureError.invalidSceneEV }
                    if sample.source == .camera {
                        let ageSeconds = now().timeIntervalSince(sample.timestamp)
                        guard (0...ReadingStability.staleInterval).contains(ageSeconds),
                              let requestedAt, sample.timestamp >= requestedAt else {
                            failRequest(.stale)
                            continue
                        }
                        currentCameraContext = sample.cameraContext
                    }
                    isReadingScene = false
                    requestedAt = nil
                    state = .ready(sample, sample.source == .camera ? .measured : .simulated)
                }
            }
            if generation == requestID, isReadingScene { failRequest(.stale) }
        } catch is CancellationError {
            if generation == requestID {
                isReadingScene = false
                if reading == nil { state = .idle }
            }
        } catch {
            if generation == requestID { failRequest(.failed("The reading is unavailable. Press Read Scene to retry, or enter a manual EV.")) }
        }
    }

    private func showPreviewState(_ newState: State) {
        isPreviewReady = false
        if reading == nil { state = newState }
    }
    private func failRequest(_ failure: State) {
        isPreviewReady = false
        isReadingScene = false
        requestedAt = nil
        // A preview failure does not turn an explicitly measured snapshot into live data.
        if reading == nil { state = failure }
    }
    private func sendReadingCommand() {
        readingCommand?.cancel()
        readingCommand = Task {
            guard !Task.isCancelled, isReadingScene, let id = measurementRequestID else { return }
            await lightMeter.requestReading(id: id)
        }
    }

    func readScene() {
        guard canReadScene else { return }
        // A failed stream must reconnect before issuing its measurement command.
        if !isPreviewReady, streamActive { restartPreview() }
        measurementRequestID = UUID()
        requestedAt = now()
        isReadingScene = true
        state = .settling
        if isPreviewReady { sendReadingCommand() }
        else if !streamActive { requestID += 1 }
    }

    func toggleGuideOrientation() {
        guideOrientation = guideOrientation == .portrait ? .landscape : .portrait
    }

    func meterAtCenter() {
        guard canChooseMeteringPoint else { return }
        centerResetID += 1
        camera?.meter(at: CGPoint(x: 0.5, y: 0.5))
    }

    private func restartPreview() {
        readingCommand?.cancel()
        isPreviewReady = false
        streamActive = false
        supportsPointMetering = false
        currentCameraContext = nil
        previewFormat = nil
        centerResetID += 1
        requestID += 1
    }

    /// Manual planning is bounded to −20…30 EV100; it never triggers camera reading.
    func enterManualEV(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let ev = Double(normalized), ev.isFinite, (-20...30).contains(ev) else { return false }
        readingCommand?.cancel()
        isReadingScene = false
        requestedAt = nil
        state = .ready(ExposureReading(sceneEV100: ev, timestamp: now(), source: .manual), .manual)
        return true
    }

    func becameInactive() {
        isActive = false
        isReadingScene = false
        requestedAt = nil
        restartPreview()
        if reading == nil { state = .idle }
    }

    func becameActive() {
        guard !isActive else { return }
        isActive = true
        restartPreview()
    }
}
