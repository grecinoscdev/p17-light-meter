/// Bundled stock profile. There is no external profile-import boundary in v1.
/// Values are immutable and tested; changing evidence requires a version bump.
public enum Pentax17Profile {
    public static let identifier = "pentax17-stock-v1"
    public static let supportedCameraISO = [50, 100, 125, 160, 200, 400, 800, 1600, 3200]
    public static let fastestShutterSeconds = 1.0 / 350.0
    public static let physicalSlowestShutterSeconds = 4.0
    public static let apertureRange = 3.5...16.0
    public static let publishedMeterRangeEV100 = 2.5...16.5
    /// Nil means unverified, not unlimited and not the physical 4-second maximum.
    public static let programSlowestShutterSeconds: Double? = nil
    public static let bokehSlowestShutterSeconds: Double? = nil
    public static let officialSpecifications = "https://www.ricoh-imaging.co.jp/english/products/pentax17/spec/"
    public static let officialModeDescriptions = "https://www.ricoh-imaging.co.jp/english/products/pentax17/feature/"
    public static let apertureEvidence = "f/3.5: Ricoh; f/16: DPReview secondary evidence, doc/pentax17-deep-research-report.md"
    public static let modelEvidence = "Continuous Bokeh approximation; Program target feasibility only. PLAN.md sections 4–5. No empirical program map or aperture-step data."
}
