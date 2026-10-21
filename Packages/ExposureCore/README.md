# ExposureCore

Pure Swift exposure calculations for the PENTAX 17. No camera, UI, storage, or device state belongs in this package. Run its tests from the repository root with `swift test --package-path Packages/ExposureCore`.

## Entry points

| Type | Responsibility | Tests |
| --- | --- | --- |
| `SceneExposure` | Phone f-number, duration in seconds, and sensor ISO → EV100; add calibration offset once | `ExposureEngineTests` |
| `ExposureConfiguration` | Validate PENTAX ISO, EC dial, and target/mode | `ProgramExposureTests` |
| `Pentax17Profile` | Immutable versioned stock values and evidence; unknown mode limits remain nil | `ExposureEngineTests` |
| `ProgramExposure` | Required shutter at any permitted target and exact minimum ND | `ProgramExposureTests` |
| `ExposureEngine` | Program feasibility or continuous Bokeh estimate, plus handheld advisory | `ExposureEngineTests` |
| `NDFilter`, `NDRounding` | Stops, factor labels, and upward third-stop display boundary | `NDRecommendationTests` |
| `NDRecommendationEngine` | Nominal weakest eligible filter, manual comparison, and optional uncertainty alternative | `NDRecommendationTests` |

## Example

```swift
let configuration = try ExposureConfiguration(
    cameraISO: 400,
    exposureCompensationEV: 0,
    mode: .bokeh
)
let result = try NDRecommendationEngine.recommend(
    sceneEV100: 15,
    configuration: configuration,
    inventory: NDFilter.catalog,
    selectedFilter: NDFilter.catalog[3] // Optional manual ND8 comparison.
)

switch result.recommendation {
case let .candidate(candidate):
    // ND32 / 5 stops. f/3.5 requires approximately 1/334 s.
    // This is nominal physical feasibility; Bokeh's slow policy remains unknown.
    print(candidate.filter.standardLabel ?? "Custom filter")
case let .noMatch(reason):
    // Keep result.exactMinimumStops visible and explain reason.
    print(reason)
}
// result.selected still assesses ND8; it does not alter the recommendation.
```

For Program use `.program(targetAperture: 8)`. The resulting exposure only establishes feasibility at the requested aperture; it never predicts which aperture Program will choose.

## Result semantics

- `ExposureAssessment.target` always describes the requested aperture. In Bokeh this is f/3.5, even when insufficient ND makes the modeled aperture smaller.
- `modeledAperture` is the requested target for Program or a continuous estimate for Bokeh. Nil modeled aperture/shutter means no solution fits that model's envelope; the required target shutter remains available to explain the failure.
- `needsSteadySupport` compares against a configurable 1/60 s preference. It is not a mode specification and does not veto a filter by itself.
- Candidate eligibility requires the **target** shutter to fit 1/350…4 s. Stopping down in the Bokeh estimate does not qualify an inadequate filter for the f/3.5 objective. A candidate is never a claim of a verified mode slow limit.
- `selected` is optional manual comparison, independent of the nominal recommendation. Pass nil when returning to automatic selection. An empty inventory never falls back to generic filters; include the catalog's no-filter entry if removal is permitted.
- `uncertaintyEV` is an optional caller-supplied symmetric scene interval. Unknown stays nil. It does not represent calibration status or observed temporal variation. A stronger alternative is offered only when the nominal candidate crosses the fast boundary and a stronger filter covers both interval endpoints.
- Calibration accuracy, scene freshness, settling, held/manual provenance, and time-dependent recommendation stabilization are upstream responsibilities. Only pass accepted readings when presenting a current recommendation.

Input failures throw `ExposureError`; physical exposure failures are result states. Nonfinite or nonrepresentable arithmetic never becomes a default reading. Exact calculations retain Double precision; only `NDRounding` and the app's formatters round. The 1e-12 EV tolerance absorbs floating-point noise, not measurement uncertainty.

The maintained formulas and independent golden cases are in [PLAN.md](../../PLAN.md). [Research](../../doc/pentax17-deep-research-report.md) documents the distinction between official specifications, secondary f/16 evidence, and the Bokeh modeling assumption. Golden constants were independently checked using 40-digit decimal logarithms. No physical-device or reference-meter validation is claimed by these tests.
