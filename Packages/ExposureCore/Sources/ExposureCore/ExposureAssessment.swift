import Foundation

/// Program ranges apply only to the requested target; Bokeh ranges apply to the
/// modeled aperture. A target may fail even though Bokeh can stop down.
public enum ModeledRange: Equatable, Sendable {
    case withinPhysicalEnvelopeModeLimitUnverified
    case beyondBrightLimit
    case beyondSlowLimit
}

/// Keeps target feasibility separate from the continuous Bokeh approximation.
/// A nil modeled aperture/shutter means no exposure fits the modeled envelope.
public struct ExposureAssessment: Equatable, Sendable {
    public let mode: ExposureMode
    public let target: ProgramAssessment
    /// Program: requested target. Bokeh: continuous estimate, not an iris detent.
    public let modeledAperture: Double?
    public let modeledShutterSeconds: Double?
    public let modeledRange: ModeledRange
    /// Advisory uses the target shutter in Program and the modeled shutter in Bokeh.
    /// It is a user preference, not a camera specification or suitability veto.
    public let needsSteadySupport: Bool
}

public enum ExposureEngine {
    /// Assess one selected PENTAX filter, applied once to the unfiltered scene.
    /// The handheld threshold defaults to 1/60 s and must be finite and positive.
    /// Returns physical-envelope results, never a guarantee about per-mode policy.
    public static func assess(sceneEV100: Double, configuration: ExposureConfiguration,
                              ndStops: Double, handheldThresholdSeconds: Double = 1.0 / 60.0) throws -> ExposureAssessment {
        guard handheldThresholdSeconds.isFinite, handheldThresholdSeconds > 0 else {
            throw ExposureError.invalidHandheldThreshold
        }
        let targetAperture = configuration.mode.targetAperture
        let target = try ProgramExposure.assess(
            sceneEV100: sceneEV100, cameraISO: configuration.cameraISO,
            exposureCompensationEV: configuration.exposureCompensationEV,
            targetAperture: targetAperture, ndStops: ndStops
        )
        var modeledAperture: Double? = targetAperture
        var modeledShutterSeconds: Double? = target.shutterSeconds
        let modeledRange: ModeledRange
        switch target.range {
        case .withinPhysicalEnvelopeModeLimitUnverified:
            modeledRange = .withinPhysicalEnvelopeModeLimitUnverified
        case .slowerThanAutomaticEnvelope:
            modeledRange = .beyondSlowLimit
            modeledAperture = nil
            modeledShutterSeconds = nil
        case .fasterThanShutterLimit:
            if configuration.mode == .bokeh {
                // Equivalent exposure: Nnew² / tfast = Ntarget² / ttarget.
                // Log space prevents a ratio overflow for very bright inputs.
                let apertureEV = 2 * log2(targetAperture)
                    + log2(Pentax17Profile.fastestShutterSeconds) - log2(target.shutterSeconds)
                let smallestOpeningEV = 2 * log2(Pentax17Profile.apertureRange.upperBound)
                if apertureEV <= smallestOpeningEV + ExposureTolerance.boundaryEV {
                    modeledAperture = min(exp2(apertureEV / 2), Pentax17Profile.apertureRange.upperBound)
                    modeledShutterSeconds = Pentax17Profile.fastestShutterSeconds
                    modeledRange = .withinPhysicalEnvelopeModeLimitUnverified
                } else {
                    modeledRange = .beyondBrightLimit
                    modeledAperture = nil
                    modeledShutterSeconds = nil
                }
            } else {
                modeledRange = .beyondBrightLimit
                modeledAperture = nil
                modeledShutterSeconds = nil
            }
        }
        let advisoryShutterSeconds = modeledShutterSeconds ?? target.shutterSeconds
        return ExposureAssessment(
            mode: configuration.mode, target: target,
            modeledAperture: modeledAperture, modeledShutterSeconds: modeledShutterSeconds,
            modeledRange: modeledRange,
            needsSteadySupport: advisoryShutterSeconds > handheldThresholdSeconds
        )
    }
}
