import Foundation
import ExposureCore

/// Persistence DTO: domain filters are reconstructed through their validated API.
struct SavedFilter: Codable, Equatable, Sendable {
    let id: String
    let stops: Double
    init(_ filter: NDFilter) { id = filter.id; stops = filter.stops }
    func filter() throws -> NDFilter {
        guard stops > 0, stops <= SavedSettings.maximumCustomStops,
              id.count <= 100 else { throw SettingsError.invalidData }
        return try NDFilter(id: id, stops: stops)
    }
}

/// One small atomic document keeps preferences, inventory, and calibration in sync.
/// Never stores a live/held/manual reading or turns a saved scene into a fresh one.
struct SavedSettings: Codable, Equatable, Sendable {
    static let maximumCustomStops = 20.0 // Explicit UI entry bound, not a camera limit.
    var schemaVersion = 1
    var mode = "bokeh"
    var cameraISO = 100
    var filmBoxISO: Int?
    var compensationThirds = 0
    var programAperture = 8.0
    var showsGrid = true
    var useOwnedFilters = false
    var ownedFilters: [SavedFilter] = []
    var selectedFilterID: String?
    var calibration: CalibrationRecord?

    func validatedFilters() throws -> [NDFilter] {
        guard ownedFilters.count <= 100 else { throw SettingsError.invalidData }
        let filters = try ownedFilters.map { try $0.filter() }
        guard Set(filters.map(\.id)).count == filters.count else { throw SettingsError.invalidData }
        for filter in filters {
            if let catalog = NDFilter.catalog.first(where: { $0.id == filter.id }), catalog != filter {
                throw SettingsError.invalidData
            }
        }
        return filters
    }

    func validate() throws {
        guard schemaVersion == 1 else { throw SettingsError.unsupportedVersion }
        guard ["program", "bokeh", "slowSpeed"].contains(mode), (-6...6).contains(compensationThirds),
              [3.5, 4, 5.6, 8, 11, 16].contains(programAperture) else { throw SettingsError.invalidData }
        _ = try ExposureConfiguration(cameraISO: cameraISO, exposureCompensationEV: Double(compensationThirds) / 3,
            mode: .program(targetAperture: programAperture))
        if let filmBoxISO, !Pentax17Profile.supportedCameraISO.contains(filmBoxISO) { throw SettingsError.invalidData }
        let owned = try validatedFilters()
        let available = useOwnedFilters ? NDFilter.catalog.filter { $0.stops == 0 } + owned : NDFilter.catalog
        if let selectedFilterID, !available.contains(where: { $0.id == selectedFilterID }) { throw SettingsError.invalidData }
        try calibration?.validate()
    }
}

enum SettingsError: Error, Equatable {
    case unsupportedVersion, invalidData, tooLarge
}
