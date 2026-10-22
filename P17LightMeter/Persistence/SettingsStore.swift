import Foundation

/// Replaceable I/O boundary; tests use temporary directories or a controlled store.
protocol SettingsStore: Sendable {
    func load() async throws -> SavedSettings?
    func save(_ settings: SavedSettings) async throws
}

/// Owns synchronous, small-file I/O away from the main actor. Atomic replacement
/// avoids half-written documents. Unknown/corrupt files are preserved until the
/// user explicitly resets saved data; load never overwrites them with defaults.
actor FileSettingsStore: SettingsStore {
    private let fileURL: URL
    init(directory: URL) { fileURL = directory.appendingPathComponent("settings-v1.json") }

    func load() throws -> SavedSettings? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        // The UI permits at most 100 filters. A megabyte is already far beyond
        // normal data size and prevents an accidental huge import/read.
        if let bytes = attributes[.size] as? NSNumber, bytes.intValue > 1_048_576 { throw SettingsError.tooLarge }
        let settings = try JSONDecoder().decode(SavedSettings.self, from: Data(contentsOf: fileURL))
        try settings.validate()
        return settings
    }

    func save(_ settings: SavedSettings) throws {
        try settings.validate()
        let data = try JSONEncoder().encode(settings)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
