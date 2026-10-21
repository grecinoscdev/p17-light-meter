import Foundation

/// Invalid inputs are rejected rather than replaced with plausible exposure values.
public enum ExposureError: Error, Equatable, Sendable {
    case invalidSceneEV
    case unsupportedCameraISO
    case invalidCompensation
    case invalidTargetAperture
    case invalidNDStops
    case unrepresentableExposure
}

/// Stock physical limits, version 1. Mode-specific slow limits remain unknown.
/// Provenance: PLAN.md §4; Ricoh specifications for ISO, EC and shutter limits;
/// f/16 is secondary-source evidence documented in the research report.
public enum Pentax17Profile {
    public static let supportedCameraISO = [50, 100, 125, 160, 200, 400, 800, 1600, 3200]
    public static let fastestShutterSeconds = 1.0 / 350.0
    public static let physicalSlowestShutterSeconds = 4.0
    public static let apertureRange = 3.5...16.0
}

/// Physical feasibility at a requested aperture, not a prediction of Program's choice.
public enum TargetRange: Equatable, Sendable {
    case fasterThanShutterLimit
    case withinPhysicalEnvelopeModeLimitUnverified
    case slowerThanAutomaticEnvelope
}

public struct ProgramAssessment: Equatable, Sendable {
    public let shutterSeconds: Double
    public let minimumNDStops: Double
    public let range: TargetRange
}

/// Deterministic Program target-aperture math. Inputs refer to the unfiltered scene
/// and PENTAX dials, never the phone's sensor ISO or autoexposure compensation.
public enum ProgramExposure {
    /// Returns required shutter seconds and exact minimum ND stops for the fast limit.
    /// EC must be −2…+2 in third stops; positive EC requests more exposure.
    /// The target can be any f-number in 3.5…16; it does not imply an iris detent.
    /// Throws `ExposureError` for invalid inputs or unrepresentable numeric results.
    public static func assess(
        sceneEV100: Double,
        cameraISO: Int,
        exposureCompensationEV: Double,
        targetAperture: Double,
        ndStops: Double
    ) throws -> ProgramAssessment {
        guard sceneEV100.isFinite else { throw ExposureError.invalidSceneEV }
        guard Pentax17Profile.supportedCameraISO.contains(cameraISO) else {
            throw ExposureError.unsupportedCameraISO
        }
        // Tolerance accepts binary representations of exact third-stop dial values.
        let dialTolerance = 1e-9
        let compensationThirds = exposureCompensationEV * 3
        guard exposureCompensationEV.isFinite,
              (-2.0...2.0).contains(exposureCompensationEV),
              abs(compensationThirds - compensationThirds.rounded()) < dialTolerance else {
            throw ExposureError.invalidCompensation
        }
        guard targetAperture.isFinite,
              Pentax17Profile.apertureRange.contains(targetAperture) else {
            throw ExposureError.invalidTargetAperture
        }
        guard ndStops.isFinite, ndStops >= 0 else { throw ExposureError.invalidNDStops }

        let isoAdjustmentEV = log2(Double(cameraISO) / 100.0)
        let unfilteredSettingsEV = sceneEV100 + isoAdjustmentEV - exposureCompensationEV
        let filteredSettingsEV = unfilteredSettingsEV - ndStops
        let apertureEV = 2 * log2(targetAperture)
        let maximumSettingsEV = apertureEV - log2(Pentax17Profile.fastestShutterSeconds)
        let minimumNDStops = max(0, unfilteredSettingsEV - maximumSettingsEV)
        let shutterSeconds = exp2(apertureEV - filteredSettingsEV)
        guard shutterSeconds.isFinite, shutterSeconds > 0, minimumNDStops.isFinite else {
            throw ExposureError.unrepresentableExposure
        }

        // Compare in EV space so an exact calculated boundary is not rejected by
        // conversion to seconds. This tolerance only absorbs floating-point noise.
        let boundaryToleranceEV = 1e-12
        let minimumSettingsEV = apertureEV - log2(Pentax17Profile.physicalSlowestShutterSeconds)
        let range: TargetRange
        if filteredSettingsEV > maximumSettingsEV + boundaryToleranceEV {
            range = .fasterThanShutterLimit
        } else if filteredSettingsEV < minimumSettingsEV - boundaryToleranceEV {
            range = .slowerThanAutomaticEnvelope
        } else {
            range = .withinPhysicalEnvelopeModeLimitUnverified
        }
        return ProgramAssessment(
            shutterSeconds: shutterSeconds, minimumNDStops: minimumNDStops, range: range
        )
    }
}
