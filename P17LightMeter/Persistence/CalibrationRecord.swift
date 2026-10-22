import Foundation

/// Local device identity and the fixed camera configuration used for a raw sample.
/// Neither identifier is displayed or uploaded. A changed configuration must not
/// silently reuse a correction measured with a different camera pipeline.
struct CameraContext: Codable, Equatable, Sendable {
    let deviceIdentifier: String
    let cameraIdentifier: String
    let configurationIdentifier: String

    var isValid: Bool {
        [deviceIdentifier, cameraIdentifier, configurationIdentifier].allSatisfy { !$0.isEmpty && $0.count <= 2048 }
    }
}

/// One reference-meter comparison, not a total accuracy or uncertainty estimate.
/// Offset has EV units and is derived from raw data, so repeated application cannot
/// accumulate an old correction into a newly saved calibration.
struct CalibrationRecord: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let context: CameraContext
    let rawEV100: Double
    let referenceEV100: Double
    let sampleTimestamp: Date
    let savedAt: Date
    var offsetEV: Double { referenceEV100 - rawEV100 }

    func validate() throws {
        guard schemaVersion == 1 else { throw SettingsError.unsupportedVersion }
        guard context.isValid, rawEV100.isFinite, referenceEV100.isFinite,
              (-20...30).contains(rawEV100), (-20...30).contains(referenceEV100),
              sampleTimestamp.timeIntervalSince1970.isFinite, savedAt.timeIntervalSince1970.isFinite,
              savedAt >= sampleTimestamp else { throw SettingsError.invalidData }
    }
}
