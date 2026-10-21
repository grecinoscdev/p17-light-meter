import Foundation

/// Converts an unfiltered phone exposure sample to scene EV normalized to ISO 100.
/// This calculation alone does not establish calibration accuracy or sample stability.
public enum SceneExposure {
    /// Aperture is an f-number; duration is seconds; phoneISO is the sensor ISO,
    /// independent of the PENTAX dial. All three must be finite and positive.
    /// A finite calibration offset is added in EV. Throws typed input/numeric errors.
    public static func ev100(phoneAperture: Double, phoneExposureSeconds: Double,
                             phoneISO: Double, calibrationOffsetEV: Double = 0) throws -> Double {
        guard phoneAperture.isFinite, phoneAperture > 0,
              phoneExposureSeconds.isFinite, phoneExposureSeconds > 0,
              phoneISO.isFinite, phoneISO > 0 else {
            throw ExposureError.invalidPhoneSample
        }
        guard calibrationOffsetEV.isFinite else { throw ExposureError.invalidCalibrationOffset }
        // Log-space arithmetic avoids overflowing the aperture square or ISO ratio.
        let settingsEV = 2 * log2(phoneAperture) - log2(phoneExposureSeconds)
        let rawSceneEV100 = settingsEV - (log2(phoneISO) - log2(100))
        let calibratedSceneEV100 = rawSceneEV100 + calibrationOffsetEV
        guard calibratedSceneEV100.isFinite else { throw ExposureError.unrepresentableExposure }
        return calibratedSceneEV100
    }
}
