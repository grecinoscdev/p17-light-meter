import Foundation

/// Aperture objective, not a claim about Program's undocumented aperture choices.
public enum ExposureMode: Equatable, Sendable {
    case program(targetAperture: Double)
    case bokeh

    public var targetAperture: Double {
        switch self {
        case let .program(targetAperture): targetAperture
        case .bokeh: Pentax17Profile.apertureRange.lowerBound
        }
    }
}

/// Validated PENTAX dial settings. Film box ISO and phone sensor ISO are intentionally
/// absent: neither changes the camera's exposure calculation without changing its dial.
public struct ExposureConfiguration: Equatable, Sendable {
    public let cameraISO: Int
    public let exposureCompensationEV: Double
    public let mode: ExposureMode

    /// EC is −2…+2 in third stops. Program targets can be any f-number in 3.5…16;
    /// continuous values express a preference, never known physical iris detents.
    public init(cameraISO: Int, exposureCompensationEV: Double, mode: ExposureMode) throws {
        guard Pentax17Profile.supportedCameraISO.contains(cameraISO) else {
            throw ExposureError.unsupportedCameraISO
        }
        let compensationThirds = exposureCompensationEV * 3
        // Accept binary representations of exact third-stop dial values.
        let dialTolerance = 1e-9
        guard exposureCompensationEV.isFinite,
              (-2.0...2.0).contains(exposureCompensationEV),
              abs(compensationThirds - compensationThirds.rounded()) < dialTolerance else {
            throw ExposureError.invalidCompensation
        }
        guard mode.targetAperture.isFinite,
              Pentax17Profile.apertureRange.contains(mode.targetAperture) else {
            throw ExposureError.invalidTargetAperture
        }
        self.cameraISO = cameraISO
        self.exposureCompensationEV = exposureCompensationEV
        self.mode = mode
    }
}

/// Numeric tolerances absorb floating-point noise, never measurement uncertainty.
/// 1e-12 EV is many orders smaller than a meaningful photographic change.
enum ExposureTolerance {
    static let boundaryEV = 1e-12
}
