import XCTest
import ExposureCore
@testable import P17LightMeter

final class PersistenceTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory
    }
    func testAtomicDocumentRoundTripIncludesInventoryAndCalibration() async throws {
        let directory = try temporaryDirectory()
        let store = FileSettingsStore(directory: directory)
        let missing = try await store.load()
        XCTAssertNil(missing)
        var settings = SavedSettings()
        settings.mode = "slowSpeed"; settings.cameraISO = 400; settings.filmBoxISO = 200
        settings.compensationThirds = -2; settings.programAperture = 11; settings.showsGrid = false
        settings.useOwnedFilters = true
        let filter = try NDFilter(id: "custom", stops: 2.5)
        settings.ownedFilters = [SavedFilter(filter)]; settings.selectedFilterID = filter.id
        settings.calibration = CalibrationRecord(context: CameraContext(deviceIdentifier: "device", cameraIdentifier: "wide", configurationIdentifier: "v1"),
            rawEV100: 12, referenceEV100: 12.5, sampleTimestamp: Date(timeIntervalSince1970: 100), savedAt: Date(timeIntervalSince1970: 101))
        try await store.save(settings)
        let restored = try await FileSettingsStore(directory: directory).load()
        XCTAssertEqual(restored, settings)
        try await store.save(SavedSettings())
        let reset = try await store.load()
        XCTAssertEqual(reset, SavedSettings())
    }
    func testUnreadableAndFutureDocumentsArePreserved() async throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("settings-v1.json")
        var future = SavedSettings(); future.schemaVersion = 99
        for data in [Data("not JSON".utf8), try JSONEncoder().encode(future)] {
            try data.write(to: file)
            do { _ = try await FileSettingsStore(directory: directory).load(); XCTFail("Must reject unsupported data") }
            catch { XCTAssertEqual(try Data(contentsOf: file), data) }
        }
    }
    func testInvalidPersistedInputsAreRejected() throws {
        var settings = SavedSettings(); settings.cameraISO = 123
        XCTAssertThrowsError(try settings.validate())
        settings = SavedSettings(); settings.programAperture = 9
        XCTAssertThrowsError(try settings.validate())
        settings = SavedSettings(); settings.selectedFilterID = "missing"
        XCTAssertThrowsError(try settings.validate())
        settings = SavedSettings(); settings.filmBoxISO = 123
        XCTAssertThrowsError(try settings.validate())
        settings = SavedSettings(); settings.ownedFilters = [SavedFilter(NDFilter.catalog[1]), SavedFilter(NDFilter.catalog[1])]
        XCTAssertThrowsError(try settings.validate())
        settings.ownedFilters = [SavedFilter(try NDFilter(id: NDFilter.catalog[1].id, stops: 2.5))]
        XCTAssertThrowsError(try settings.validate())
        settings.ownedFilters = [SavedFilter(try NDFilter(id: "too much", stops: 21))]
        XCTAssertThrowsError(try settings.validate())
    }
}

actor TestSettingsStore: SettingsStore {
    var settings: SavedSettings?
    var failsLoad = false
    var failsSave = false
    var saveCount = 0
    init(_ settings: SavedSettings? = nil, failsLoad: Bool = false) { self.settings = settings; self.failsLoad = failsLoad }
    func load() throws -> SavedSettings? {
        if failsLoad { throw SettingsError.invalidData }
        return settings
    }
    func save(_ settings: SavedSettings) throws {
        if failsSave { throw SettingsError.invalidData }
        try settings.validate(); self.settings = settings; saveCount += 1
    }
    func failSaving(_ fail: Bool) { failsSave = fail }
}

@MainActor
final class SavedSettingsModelTests: XCTestCase {
    private func model(store: TestSettingsStore? = nil) -> MeterViewModel {
        MeterViewModel(lightMeter: FakeLightMeter(sample: ExposureReading(sceneEV100: 15, timestamp: Date(), source: .simulated)), settingsStore: store)
    }
    func testLatestEditsRestoreWithoutRestoringSceneAndFilmISODoesNotChangeMetering() async throws {
        let store = TestSettingsStore()
        let first = model(store: store)
        await first.restoreSettings(); first.readScene(); await first.load()
        first.cameraMode = .slowSpeed; first.cameraISO = 400; first.compensationThirds = 3
        first.programAperture = 11; first.showsGrid = false
        let before = first.reading
        first.filmBoxISO = 200
        XCTAssertEqual(first.reading, before)
        first.useOwnedFilters = true
        XCTAssertTrue(first.addCustomFilter("2,5"))
        first.selectedFilter = first.ownedFilters.first
        await first.flushPendingSaves()
        let next = model(store: store)
        await next.restoreSettings()
        XCTAssertEqual(next.cameraMode, .program); XCTAssertEqual(next.cameraISO, 400)
        XCTAssertEqual(next.compensationThirds, 3); XCTAssertEqual(next.programAperture, 11)
        XCTAssertFalse(next.showsGrid); XCTAssertEqual(next.filmBoxISO, 200)
        XCTAssertEqual(next.selectedFilter?.stops, 2.5); XCTAssertTrue(next.useOwnedFilters)
        XCTAssertNil(next.reading); XCTAssertEqual(next.state, .idle)
    }
    func testOwnedInventoryNeverFallsBackAndRemovingSelectionClearsIt() async throws {
        let model = model(); model.readScene(); await model.load()
        model.useOwnedFilters = true
        XCTAssertEqual(model.availableFilters.map(\.stops), [0])
        guard case .noMatch = try XCTUnwrap(model.calculation).get().recommendation else { return XCTFail("Must not recommend an unowned filter") }
        XCTAssertFalse(model.addCustomFilter("nan")); XCTAssertFalse(model.addCustomFilter("0"))
        XCTAssertFalse(model.addCustomFilter("21")); XCTAssertTrue(model.addCustomFilter("2.5"))
        XCTAssertFalse(model.addCustomFilter("2.5"))
        let filter = try XCTUnwrap(model.ownedFilters.first)
        model.selectedFilter = filter; model.setOwned(filter, included: false)
        XCTAssertNil(model.selectedFilter)
        XCTAssertEqual(model.availableFilters.map(\.stops), [0])
    }
    func testLoadFailureBlocksWritesUntilExplicitReset() async {
        let store = TestSettingsStore(failsLoad: true)
        let model = model(store: store); await model.restoreSettings()
        XCTAssertTrue(model.savedDataNeedsReset); XCTAssertNotNil(model.settingsMessage)
        model.cameraISO = 400; await model.flushPendingSaves()
        let count = await store.saveCount
        XCTAssertEqual(count, 0)
        await model.resetSavedData()
        XCTAssertFalse(model.savedDataNeedsReset); XCTAssertNil(model.settingsMessage)
        XCTAssertEqual(model.cameraISO, 100)
        let stored = await store.settings
        XCTAssertEqual(stored, SavedSettings())
    }
    func testWriteFailureIsVisibleAndRetrySavesCurrentValues() async {
        let store = TestSettingsStore()
        let model = model(store: store); await model.restoreSettings()
        await store.failSaving(true)
        model.cameraISO = 400; await model.flushPendingSaves()
        XCTAssertNotNil(model.settingsMessage)
        await store.failSaving(false)
        model.saveSettings(); await model.flushPendingSaves()
        XCTAssertNil(model.settingsMessage)
        let stored = await store.settings
        XCTAssertEqual(stored?.cameraISO, 400)
    }
}
