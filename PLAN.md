# P17 Light Meter — Native iOS Implementation Plan

Created: October 20, 2026  
Status: M0–M2 implemented and simulator-tested. M3 camera metering is implemented; its physical-device exit criterion remains pending. M4 calibration and persistence are implemented, with reference-meter exit checks pending. M5 remains planned.
App name: **P17 Light Meter**. Use `P17LightMeter` for project and target identifiers.

## 1. Product goal

Build an offline, native iPhone light meter that answers: **“Which ND filter should I put on my PENTAX 17 for this light?”**

The app measures reflected scene light, accounts for the photographer’s PENTAX ISO and exposure-compensation settings, and recommends an ND filter for a chosen aperture objective. Its central experience is the live viewfinder and filter wheel shown in the reference.

The first release supports two modes:

- **Bokeh:** determine the ND needed to make f/3.5 possible within the shutter limit; show an estimated resulting exposure.
- **P / Program:** determine the ND needed to make a preferred aperture physically possible; never imply that the camera will necessarily select that aperture.

The research establishes a useful distinction: exposure mathematics can be implemented now, while precise reproduction of the camera’s unpublished Program behavior requires measurements. An empirical Program map is a later enhancement, not a prerequisite for the first release.

## 2. Inputs and project baseline

Reviewed project inputs:

- [Deep research report](doc/pentax17-deep-research-report.md): exposure physics, PENTAX constraints, ND scenarios, calibration, and implementation suggestions.
- [UI reference](doc/Codex-UI-Reference-3x.png): 1170 × 2532 image showing the viewfinder, controls, and ND panel. Replace its original branding with **P17 Light Meter** in the implementation.

The folder now includes a SwiftUI app, shared scheme, local ExposureCore package, fake meter, and unit/UI test targets. Xcode 27.1 and an iPhone 18 Pro / iOS 27.0 simulator are available. Development signing and physical devices remain unverified.

Proposed defaults, intended to let development proceed without a lengthy setup phase:

| Decision | Initial choice |
| --- | --- |
| Platform | iPhone, iOS 17 or later; verify deployment compatibility during scaffolding |
| UI | SwiftUI with an AVFoundation preview bridge |
| Orientation | Portrait-first v1; landscape support deferred |
| First-launch settings | Bokeh, camera ISO 100, EC 0; visibly editable before relying on a reading |
| Program target | f/8, labeled as a preference rather than an optical guarantee |
| Storage | On-device preferences and versioned JSON; no account or server |
| Camera | One fixed rear wide-angle physical camera; no automatic lens switching |
| Filter selection | Generic catalog initially; “My filters” becomes available after the user selects owned filters |
| Privacy | Camera access only; no image recording, uploads, microphone, or location access |

## 3. Scope and product boundaries

### Required for v1

- Live camera preview and EV100 readout with settling, stable, held, and unavailable states.
- Tap-to-meter, center reset, and a clearly labeled Hold / Resume control.
- P / Program and Bokeh mode selector.
- Supported camera ISO choices, EC adjustment, and editable Program target aperture.
- ND wheel with a no-filter option, exact minimum ND, recommended filter, and manual filter comparison.
- Distinct wording for a recommendation, a selected filter, and the filter physically mounted on the camera; the app cannot detect the last one.
- Target-aperture shutter calculation, warnings, and explanation of model limitations.
- Editable owned-filter list, including custom stop values.
- Calibration offset for the selected iPhone camera, with reset and calibration status.
- Manual EV entry for camera-unavailable use and reproducible testing, always marked “Manual.”
- Persistence of settings and calibration, accessibility, camera lifecycle handling, and physical-device validation.

### Later releases

- Empirically measured Standard Program profiles and actual Program-aperture prediction.
- Filter-specific meter calibration, more advanced device calibration curves, and profile import/export.
- Landscape layouts, exposure history, film-roll notes, widgets, and localization beyond the initial language.
- Dedicated Slow-speed features, flash, and Bulb planning, including film-specific reciprocity handling if added.

Photo capture, film emulation, automatic ISO optimization, and remote control of the PENTAX are outside v1. Bokeh mode does not mean simulated phone-camera background blur.

## 4. Camera model and correctness rules

Use a versioned camera profile instead of scattering constants throughout the UI.

| Property | Profile value / handling |
| --- | --- |
| Lens | Fixed 25 mm f/3.5; approximately 37 mm equivalent |
| Frame | 17 × 24 mm in portrait orientation |
| Maximum aperture | f/3.5 |
| Minimum aperture | f/16, identified as secondary-source evidence from the research |
| Fastest shutter | 1/350 s |
| Physical automatic slow limit | 4 s; not a verified slow limit for every mode |
| ISO dial | 50, 100, 125, 160, 200, 400, 800, 1600, 3200 |
| EC dial | −2 through +2 EV in 1/3-EV steps |
| Published meter range | EV 2.5–16.5 at ISO 100 |
| Standard/Bokeh slow limits | Unknown until verified; optional profile fields |
| Standard program curve / aperture steps | Unknown; do not fabricate |

Official hardware values are cross-checked against [Ricoh’s specifications](https://www.ricoh-imaging.co.jp/english/products/pentax17/spec/). Ricoh describes Bokeh as choosing the largest available aperture for the scene; a continuous mathematical approximation of that behavior remains an estimate. [Ricoh mode descriptions](https://www.ricoh-imaging.co.jp/english/products/pentax17/feature/)

Rules that apply throughout the app:

1. Camera ISO is an input, never an optimization variable. Phone sensor ISO is a separate metering input.
2. Camera EC changes the PENTAX prediction, not the iPhone’s autoexposure bias.
3. Positive EC requests more exposure and therefore reduces the required ND.
4. f/8 is an editable target, not a manufacturer-certified sweet spot.
5. A target inside the fast-shutter boundary does not prove the selected mode can provide the needed slow shutter.
6. A mathematically valid result does not establish calibrated phone accuracy or exact camera behavior.
7. Never mark unsupported, stale, or unsettled readings as a valid current recommendation.

## 5. Exposure engine

Implement and test the engine as pure Swift before connecting the camera or final UI. Use seconds for time, f-numbers for aperture, and stops for ND internally. Retain full precision until display formatting.

### Scene EV and target exposure

```text
Eraw = log2(phoneAperture² / phoneExposureSeconds) − log2(phoneISO / 100)
E100 = Eraw + calibrationOffsetEV

V0 = E100 + log2(cameraISO / 100) − cameraEC
V  = V0 − filterStops

targetShutterSeconds = targetAperture² / 2^V
Vmax(targetAperture) = log2(targetAperture² / (1 / 350))
minimumND = max(0, V0 − Vmax(targetAperture))
```

The phone meters the unfiltered scene. Filters selected in the app represent filters on the PENTAX; do not subtract ND twice or instruct users to cover the phone lens with the selected filter.

Validate all inputs: positive ISO, aperture and duration; finite EV; permitted EC and target values; nonnegative ND. Return explicit invalid-input states rather than silently clamping impossible values.

### Bokeh model

- At or below `Vmax(3.5)`, calculate the exposure required at f/3.5.
- Above that boundary, estimate the widest feasible aperture as `sqrt(2^V / 350)` with shutter 1/350 s.
- If the required aperture exceeds f/16, report the modeled bright-limit failure.
- If required exposure exceeds 4 s, report outside the modeled automatic envelope.
- Where a slow shutter falls within the physical envelope but the Bokeh policy is unknown, show “Required shutter; mode limit unverified.” A configurable handheld advisory can default to 1/60 s, explicitly separate from camera specifications.
- Display intermediate apertures as approximate equivalents, not physical iris detents.

### Slow-speed mode

Slow-speed currently uses the same editable target-aperture feasibility calculation
and ND policy as P / Program. Both share the user's Program target preference
(default f/8). Keep a distinct mode identity for later Slow-speed features, but do
not impose a fixed f/16 aperture or invent a separate program curve or slow limit.
The output carries the same qualification: Program may choose another aperture.

Acceptance case: EV15 / ISO400 / EC0 / target f/8 recommends ND8 and requires
1/256 s in both modes. Changing the target in either mode updates their shared
preference. Held/manual readings and selected filters survive mode changes.

### Program mode

For v1, calculate the shutter **at the requested target aperture**. Example: “At target f/8: ≈1/256 s. Program may choose another aperture.”

Keep measured-map support as a future extension: if testing establishes a target-aperture interval `[VL, VH]`, eligible ND lies in `[V0 − VH, V0 − VL]`, intersected with nonnegative stops. Multiple disjoint intervals must remain separate. Do not ship placeholder data that masquerades as measured camera behavior.

### ND selection and naming

The report sometimes uses “ND3” to mean three stops, while the UI uses filter factors. Standardize the app on **stops**, with filter factors as secondary labels:

| Attenuation | Factor label |
| --- | --- |
| 0 stops | None |
| 1 stop | ND2 |
| 2 stops | ND4 |
| 3 stops | ND8 |
| 4 stops | ND16 |
| 5 stops | ND32 |
| 6 stops | ND64 |
| 7 stops | ND128 |
| 8 stops | ND256 |

Use `factor = 2^stops`; never display “ND3” as shorthand for three stops. Support fractional custom stops without inventing a standard product label.

Selection policy:

1. Calculate the exact minimum and optional upward-rounded 1/3-stop minimum, using an epsilon at floating-point boundaries.
2. Choose the weakest eligible filter from the active catalog or owned inventory.
3. Evaluate the resulting shutter and range status before calling it suitable. A filter that solves the bright limit may create a slow-exposure problem.
4. If none is suitable, show the requirement and why no listed filter qualifies. Do not silently recommend an inadequate filter or stacked filters.
5. Keep manually selected and recommended filters separate. Manual selection immediately updates the comparison; returning to “Use recommendation” restores automatic selection.
6. Calculate headroom as `selectedStops − minimumND`. Close-to-limit results show “Near shutter limit” when the reading’s plausible uncertainty crosses the boundary.

Do not silently add a safety stop. Show the nominal result and, when justified by measured uncertainty, a stronger alternative with its slower shutter. Stabilize filter changes over consecutive readings; tune hysteresis using actual device data.

The manual cautions that dense or colored filters can affect metering and stacking may vignette the metering area. Put this explanation in filter help and contextual warnings, rather than repeating it across the screen. [Operating manual, “Using a Filter,” printed page 30](https://www.ricoh-imaging.co.jp/english/support/man-pdf/pentax17_om_en_web.pdf)

## 6. Native interface based on the PNG

Rebuild the reference as native controls and a real camera preview. The PNG is a visual specification, not a background to flatten into the app.

| Reference element | Implementation and behavior |
| --- | --- |
| P17 Light Meter header | White wordmark with a lime “17” accent and compact subtitle; adapt the reference layout to fit the app name |
| P / Program pill | Native selector for Program and Bokeh |
| ISO / EV / target pills | ISO opens camera settings; EV opens reading details/manual entry; target is editable and shared in Program/Slow-speed, and fixed at f/3.5 in Bokeh |
| Full-screen scene | Live preview, restrained dark overlays behind controls, no grain over metered imagery |
| Lime corner brackets | 17:24 portrait frame, optional thirds grid, dimmed surrounding area |
| Central reticle | Tap location and settling feedback; accessible center-reset action |
| Bottom ND panel | Persistent rounded panel, horizontally scrolling filter cards, expandable details |
| Selected lime card | Selected filter; add a separate recommendation marker if another filter is recommended |
| Large shutter readout | Required shutter at target, or estimated Bokeh exposure, with explicit mode wording |
| Status row | Text plus icon for validity, uncertainty, and camera limits; never color alone |

Add essentials absent from the image: EC control, Hold / Resume, settings, no-filter option, metering status, and camera-permission states. Keep nonzero EC visible on the main screen. Put calibration, film box ISO, filter ownership, and detailed explanations in sheets.

Use the reference’s dark teal/charcoal, lime accents, rounded outlines, and strong numeric hierarchy. Extract reusable color, spacing, type, and corner-radius tokens during implementation. Preserve system status-bar and home-indicator safe areas instead of drawing them.

### Viewfinder geometry

The frame’s **aspect ratio** and its **field of view** are separate requirements. A 17:24 rectangle alone does not reproduce the PENTAX lens view.

- v1 provides a composition guide labeled approximate; do not promise exact 37 mm-equivalent framing from an arbitrary phone crop.
- Use the fixed phone camera’s active-format FOV and video output dimensions to scale the image under the existing guide. The pinhole target is a 25 mm lens on 17 × 24 mm film. Revalidate against actual framing before enabling a stronger claim.
- Keep the full preview visible around the guide where possible. Avoid assuming the same screen fractions work on every phone.
- Transform taps through `AVCaptureVideoPreviewLayer` coordinate conversion, accounting for aspect-fill crop and orientation; avoid hand-coded normalized screen coordinates.
- The dimmed area is a visual composition mask, not a guarantee that iPhone AE excludes that area. Tap-to-meter is exposure weighting, not a calibrated spot meter or an exact reproduction of PENTAX partial metering.

### Interaction and accessibility

- Camera permission is requested when the user starts live metering, with a short explanation. Denial offers Settings and manual EV mode.
- Live readings update at a legible cadence. Hold freezes the accepted measurement and its timestamp; changing ISO, EC, or ND still recalculates from that held reading.
- Stopping Hold restarts settling. Backgrounding, interruptions, or camera changes invalidate live readings; held readings remain visibly held and dated.
- Use minimum 44-point touch targets, Dynamic Type, VoiceOver labels with spoken units, adequate contrast, and Reduce Motion support.
- At large text sizes or on compact screens, collapse the preview and allow the controls/results to scroll. Keep critical actions and result text reachable.

## 7. iPhone metering and calibration

### Capture pipeline

1. Check authorization and device capabilities; configure a fixed rear wide-angle camera.
2. Configure continuous autoexposure with neutral phone exposure bias, torch off, and a stable capture format. Keep session configuration and start/stop off the main thread.
3. Support exposure-point changes where available; show a clear fallback when unsupported.
4. Observe exposure adjustment and collect timestamped aperture, ISO, and duration samples through a serialized capture service.
5. After settling, calculate sample EV100, reject invalid/outlier samples, and use a short rolling median.
6. Publish reading quality and age with the result. Start with a 0.5–1 second sample window and a roughly 4 Hz UI update limit; tune on hardware.
7. Bound settling with a timeout, initially 3 seconds. Persistent motion, flicker, or exposure-limit conditions must produce an unstable/unavailable state rather than an endless spinner or false precision.
8. Tear down observers and pause capture when inactive; recover cleanly from interruptions and runtime failures.

Apple exposes the required exposure state through [AVFoundation’s exposure APIs](https://developer.apple.com/documentation/avfoundation/capture-device-exposure). Use a capability-checked wrapper so platform details remain outside exposure mathematics.

Proposed meter state model: `idle → requestingPermission → starting → settling → live ↔ held`, plus `manual`, `denied`, `interrupted`, and `failed`. Results should carry their source and age independently of screen state.

### Calibration

Provide a simple v1 flow: aim the phone and a trusted reflected-light meter at the same evenly lit neutral target, wait for a stable phone reading, enter reference EV100, preview the correction, and save `offset = referenceEV100 − rawEV100`.

Store calibration with the device/camera identity, capture configuration identifier, date, and schema version. Invalidate or flag it when its camera/configuration no longer matches. Support reset. A simulator or manual EV reading must never create a phone-camera calibration record.

Temporal dispersion measures **repeatability**, not total accuracy. Keep separate fields for observed variation, calibration residuals, and camera-model provenance. Do not display a numeric total ±EV accuracy claim until reference-meter validation supports it. Before that, use labels such as “Stable · Uncalibrated” and “Estimated camera behavior.”

Evaluate daylight, tungsten, and LED light, flat scenes and high contrast, and exposure saturation. If a constant offset fails across light levels, restrict the validated range and defer broader accuracy claims until a better calibration model exists.

## 8. Architecture and project organization

Use one iOS application target and one local Swift package for the deterministic domain logic. Organize capture and UI by feature within the app; avoid creating multiple framework targets before they are needed.

```text
P17LightMeter.xcodeproj
P17LightMeter/
  App/                     App entry, dependency wiring, lifecycle
  Features/Meter/          Main view, view model, viewfinder, filter wheel
  Features/Settings/       ISO/EC, filters, calibration, help
  Metering/                LightMeter protocol, AVFoundation service, fake source
  Persistence/             Preferences, calibration and inventory stores
  DesignSystem/            Tokens and shared controls
  Resources/               Assets and versioned camera profile
Packages/ExposureCore/
  Sources/ExposureCore/    EV math, profile, predictors, recommendation types
  Tests/ExposureCoreTests/ Deterministic and boundary tests
P17LightMeterTests/        Meter-state and persistence tests
P17LightMeterUITests/      Critical user journeys with injected fake readings
doc/                      Existing research and UI reference; validation notes
PLAN.md
README.md
```

Key types:

- `ExposureReading`: EV100, timestamp, source, repeatability, calibration identity/status.
- `MeteringConfiguration`: camera ISO, optional film ISO, camera EC, mode, target aperture.
- `CameraProfile`: physical limits, optional mode limits, evidence/provenance, version.
- `NDFilter`: identifier, display name, nominal stops, ownership; optional later calibration.
- `ExposureAssessment`: target shutter, estimated Bokeh aperture where applicable, range state, model provenance.
- `NDRecommendation`: exact requirement, chosen candidate, alternatives, headroom, reasons/warnings.
- `LightMeter`: async reading/state stream plus start, stop, and meter-point actions; fake implementation for previews and tests.

Use a main-actor observable view model for presentation, a dedicated serial capture service, and immutable values across that boundary. Choose either an actor with appropriate serialization or a dedicated queue; do not pass mutable AVFoundation objects freely between tasks. Cancel observation/stream tasks with the view lifecycle.

Persist preferences, filter inventory, and calibration together as one Codable JSON document in Application Support. M4 uses atomic replacement so a selected filter cannot be restored separately from its inventory; the small dataset does not need separate UserDefaults and structured stores. Version records and handle migration/corruption with a recoverable reset. Bundle the stock profile with the app; v1 does not need remote profile downloads or third-party runtime dependencies.

## 9. Delivery milestones

Each milestone must produce something reviewable and pass its exit criteria before the next dependent milestone begins. Estimates are planning ranges for one experienced iOS developer, not commitments; hardware access and calibration are the largest unknowns.

| Milestone | Work and deliverable | Exit criteria | Estimate |
| --- | --- | --- | --- |
| M0 — Foundation | Verify SDK/simulator and signing path; create app, shared scheme, local package, fake meter, test targets, README build instructions | Clean checkout builds on an installed simulator; fake EV reaches a basic screen | 0.5–1 day |
| M1 — Exposure core | Implement profile, formulas, Bokeh estimate, Program feasibility, ND inventory selection, result states | Golden scenarios and boundary/property tests pass; terminology is consistent | 1–2 days |
| M2 — Reference UI with fake data | Build viewfinder composition, pills, ND wheel, result panel, Hold, settings and manual EV | Reference scenario matches; compact and large-text layouts work; all controls recalculate correctly | 2–3 days |
| M3 — Real metering | Camera permission, fixed-camera preview, point conversion, sampling, stability, interruptions and lifecycle | Live reading works on physical hardware; invalid/stale readings cannot appear current; session stays responsive | 2–4 days |
| M4 — Calibration and persistence | Calibration flow, owned filters, settings restoration, uncertainty copy and contextual warnings | Reference-meter comparisons recorded; persistence and reset verified; no unsupported accuracy claim | 1–2 days |
| M5 — Field validation and beta | Device/light matrix, accessibility, sustained-use checks, PENTAX ND trials, release assets and TestFlight preparation | Release criteria below satisfied or supported range narrowed explicitly | 2–4 days plus field/film turnaround |

Expected implementation effort: approximately **9–16 focused development days**, excluding hardware procurement, film processing, and distribution review. If the first live-meter experiment cannot meet useful accuracy, address metering before adding optional features.

Implemented and simulator-tested first slice: **M0 + the first M1 vertical slice** — render injected EV100 15 / ISO 400 / EC 0 / Program target f/8, select ND8 (3 stops), and show ≈1/256 s with the Program qualification. This exactly exercises the supplied reference without depending on a live camera.

## 10. Validation strategy

### Exposure engine acceptance cases

Calculate expected values independently from implementation. Compare floating-point calculations with explicit tolerances; test display rounding separately.

| Case | Expected result |
| --- | --- |
| f/3.5 at 1/350 | EV ≈12.065921 |
| f/8 at 1/350 | EV ≈14.451211 |
| f/16 at 1/350 | EV ≈16.451211 |
| EV100 15, ISO 100, EC 0, Bokeh | Minimum ≈2.934079 stops; ND8 / 3 stops gives ≈1/334 s |
| EV100 15, ISO 400, EC 0, Bokeh | Minimum ≈4.934079 stops; ND32 / 5 stops gives ≈1/334 s |
| Reference: EV100 15, ISO 400, f/8, ND8 | V=14; required shutter exactly 1/256 s; Program aperture not guaranteed |
| EV100 15, ISO 100, f/8 | Minimum ≈0.548789 stops; 2/3 stop rounded minimum; 1-stop catalog filter gives 1/256 s |
| EV100 13, ISO 100, Bokeh | Minimum ≈0.934079 stop; ND2 / 1 stop qualifies |
| EV100 8, ISO 100, Bokeh, no ND | f/3.5 requires ≈1/20.90 s; show slow-shutter advisory and unknown mode-limit status |
| EV100 0, ISO 100, Bokeh, no ND | f/3.5 requires 12.25 s; exceeds physical automatic envelope |
| ISO 100 → 400 | Unclamped ND requirement increases 2 stops |
| EC 0 → +1 | Unclamped ND requirement decreases 1 stop |
| Exact threshold and ±epsilon | No extra stop caused by floating-point rounding |
| Empty or inadequate owned inventory | Explicit no-matching-filter result; generic requirement remains visible |

Also cover exposure round trips, monotonicity, no-ND conditions, stronger filters causing longer shutters, non-finite inputs, out-of-profile targets, uncertainty intervals crossing boundaries, and separation of selected/recommended filters. Verify that no auto-ISO behavior is introduced.

### App verification

- Use fake reading streams for settling, noisy, held, timed-out, interrupted, and failed states.
- Test denial/recovery, mode/ISO/EC changes, tap coordinates under preview cropping, inventory persistence, and calibration save/reset/mismatch.
- Review screenshots against the PNG at the reference aspect ratio and at compact/large-text layouts; verify semantics rather than merely pixel resemblance.
- Exercise VoiceOver, contrast, touch sizes, Reduce Motion, and controls over bright camera imagery.
- Run package tests and app tests through a documented `xcodebuild` command using the actual shared scheme and discovered simulator destination. Record the exact command in README after M0.
- Simulator verification covers UI and logic; camera accuracy requires physical iPhones.

### Hardware and field gates

Use at least two iPhone models, including the oldest hardware intended to be supported. Compare a neutral target against a trusted reflected meter across approximately EV100 6–16 under multiple lighting types.

Proposed internal targets: at least 90% of stable uniform-target readings within ±0.3 EV after calibration, no tested point beyond ±0.5 EV without an explicit limitation, and repeatability standard deviation ≤0.15 EV under steady light. These are validation goals, not pre-existing product claims. Record raw data, device/camera/configuration, lighting, and residual errors in `doc/validation/`.

Aim for a first stable reading within 2 seconds in ordinary light and after a tap; use the timeout state for harder conditions. Run a 10-minute live-meter session to inspect heat, energy use, UI responsiveness, observer leaks, and repeated foreground/background recovery.

Trial no-filter, 3-stop, and 5-stop scenarios on a real PENTAX 17 with known filters. Record any exposure discrepancies and avoid using phone-meter validation alone as proof of the PENTAX model. Film results support practical exposure checks; measuring actual aperture/shutter behavior requires a dedicated experiment.

## 11. Empirical Program research after v1

Use a stable, uniform target, a reference meter, and repeatable lighting. Sweep EV in approximately 1/3-stop increments at fixed ISO/EC, then repeat selected points across ISO and EC to test the assumed shifts.

Recover shutter durations with optical timing equipment and measure aperture behavior through a controlled optical method. Record repeated runs, camera sample, setup, uncertainty, and any discrete transitions or hysteresis. Validate on another camera where possible.

Only then create a versioned map with measured EV coverage, aperture/shutter behavior, and confidence. Validate it against held-out observations. Outside measured coverage, fall back to feasibility rather than extrapolating exact camera behavior. This phase is separate from the v1 estimate.

## 12. Risks and release criteria

| Risk / dependency | Planned response |
| --- | --- |
| Phone AE is not a calibrated photographic meter | Physical reference-meter testing, saved calibration, limited accuracy claims |
| Standard program and mode slow limits are unknown | Conditional wording and optional profile fields; empirical follow-up |
| Reading looks steady but is biased or saturated | Separate stability from calibration; range/capability checks and field validation |
| Filter labels are ambiguous | Stops are canonical; factor labels remain secondary |
| Stronger ND solves brightness but causes slow exposure | Evaluate both boundaries and show the shutter tradeoff |
| Phone frame does not match film-camera view | Approximate guide until field-of-view validation is complete |
| No reference meter, real camera, or supported test phones | Continue math/UI work; do not treat hardware-validation milestones as completed |
| Signing/distribution setup is missing | Complete simulator work; resolve developer-team access before physical deployment/beta distribution |

Release is ready when the core cases pass, the reference interaction is implemented, physical metering results support the advertised range, calibration and persistence work, camera denial/interruption paths are usable, and accessibility checks pass. The shipping UI must always distinguish Program feasibility from estimated Bokeh behavior and measured light from manual or held input.

Before distribution, finalize the app icon, bundle identifier, signing team, support/privacy information, and actual device-support matrix. Prepare screenshots and a TestFlight build after device validation; public distribution is a separate release action.

## 13. Evidence and maintenance

The supplied research is the main domain source. Its embedded research citation identifiers are not portable URLs, so preserve the original report and use direct links in implementation notes when verifying a claim. Keep official facts, secondary evidence, engineering assumptions, and empirical measurements distinct in profile metadata.

Primary sources checked while preparing this plan:

- [Ricoh PENTAX 17 specifications](https://www.ricoh-imaging.co.jp/english/products/pentax17/spec/) — physical limits and controls.
- [Ricoh PENTAX 17 features](https://www.ricoh-imaging.co.jp/english/products/pentax17/feature/) — mode descriptions and format.
- [PENTAX 17 operating manual](https://www.ricoh-imaging.co.jp/english/support/man-pdf/pentax17_om_en_web.pdf) — operational limitations and filter guidance.
- [Apple AVFoundation exposure APIs](https://developer.apple.com/documentation/avfoundation/capture-device-exposure) — capture-device exposure inputs and state.
- [Apple preview-layer coordinate conversion](https://developer.apple.com/documentation/avfoundation/avcapturevideopreviewlayer/capturedevicepointconverted(fromlayerpoint:)) — implementation reference for tap mapping.

Update this plan as milestones complete and measurements replace assumptions. Record changes to exposure behavior and camera-profile provenance alongside the relevant tests.

## 14. Implementation log

October 20, 2026: Added the foundation demo and Program target calculation. The demo deliberately uses the reference inputs rather than the eventual first-launch Bokeh defaults. ProgramExposure validates PENTAX inputs, applies ND once, and distinguishes fast-limit failure, physical-envelope feasibility with unknown mode policy, and slow-limit failure. A one-shot injectable LightMeter supports this fixed slice; the M3 streaming/capture lifecycle is still pending. No camera permission or imagery is used. Full M1 recommendation/Bokeh/profile work and the M2 reference interaction are not complete.

Verification: five package tests and four simulator tests passed on Xcode 27.1 with iPhone 18 Pro / iOS 27.0. M0 simulator exit criteria are met; device signing remains a documented external setup requirement. No physical camera accuracy or complete M2 accessibility validation is claimed. See README for the exact commands.

### M1 — Exposure core

Implemented the pure Swift domain layer: phone EV100 conversion with a calibration offset, validated dial configuration, versioned stock profile/provenance, continuous Bokeh estimate, Program target feasibility, ND labels/factors and fractional custom filters, exact and third-stop minimums, inventory selection, and selected-filter comparison. Recommendations assess both physical shutter boundaries; unknown mode slow policies remain explicit. Optional caller-supplied scene uncertainty identifies boundary crossings and a stronger alternative only when that alternative covers both endpoints. It never adds a hidden safety stop or treats stability as accuracy.

The stock profile is immutable compiled data rather than JSON: there is no imported profile data in v1, so no parser or migration layer is needed yet. Source links and version metadata live in `Pentax17Profile.swift`. A future empirical/imported profile must add validation at that boundary. No Program curve or aperture steps have been invented.

Owned inventory is the supplied filter array. Include the no-filter entry explicitly if removing a filter is an available option; an empty array produces an empty-inventory result. Equal-strength filters are ordered by identifier for deterministic selection. The exact minimum drives eligibility; upward third-stop rounding is display information only.

26 package tests cover the golden cases, numerical boundaries, invalid samples/configuration/filter inputs, signs, exposure round trips and monotonicity, selected/recommended separation, inventory gaps, and uncertainty crossing either boundary. The fixed demo remains unchanged; M2 will wire this API to mode/settings/filter interactions. Temporal recommendation hysteresis remains M3 work to tune with real readings.

M1 verification: all 26 package tests and all four simulator regression tests passed on the documented iPhone 18 Pro / iOS 27.0 destination. The reference screen still shows 1/256 s. No UI layout or hardware behavior was changed in this milestone.

### M2 — Interactive simulated interface

Implemented Bokeh/Program selection, ISO/EC and Program-target settings, generic ND filter cards including None, separate selected/recommended labels, automatic-selection restore, manual EV validation, Hold/Resume, timestamped provenance, and explicit invalid/stale states. All exposure results come from ExposureCore. The default is Bokeh / ISO100 / EC0 with simulated EV15; `--reference-scenario` reproduces the original Program screenshot inputs.

The composition guide is a 17:24 illustration over a dark simulated viewfinder, not a camera image or calibrated field of view. It collapses for accessibility text sizes. The screen scrolls to keep controls reachable on compact devices. Real preview and tap-to-meter coordinate conversion remain M3 work. Camera permission, calibration, film-box ISO, owned-filter editing, and persistence remain in their planned later milestones.

Manual EV entry accepts −20…30 EV100 as an explicit planning range, not a claim about the phone or PENTAX meter range. A request generation prevents old asynchronous samples overwriting manual input or restoring invalidated readings. SwiftUI owns and cancels sampling tasks. Unit tests use explicit completion handshakes rather than sleeps for these races.

M2 verification (October 21, 2026): all ten app-state tests and both UI journeys passed on iPhone 18 Pro / iOS 27.0. The UI journeys verify Program reference exposure, Bokeh switching, manual filter selection/automatic restore, and Hold/manual EV/Resume. iPhone 17e normal and largest accessibility-size layouts were visually inspected; status/actions stack vertically and the mode control uses a menu at accessibility sizes. The simulator text-size setting was restored after inspection. Full VoiceOver traversal and physical-device validation remain later gates.


### M3 implementation record — October 22, 2026

Added the fixed physical rear wide-angle camera service, permission/recovery states,
portrait aspect-fill preview, preview-layer tap conversion, accessible center reset,
continuous neutral-bias AE, frame-driven exposure sampling, and serial capture lifecycle.
Default launch uses the camera; `--demo-meter` or `--reference-scenario` explicitly
select simulation. An unavailable camera never silently becomes simulated live data.

The initial temporal policy requires four non-adjusting samples spanning at least
0.75 s with at most 0.2 EV spread, then publishes their median at at most 4 Hz. Invalid
samples or scene jumps clear the window. An absolute phone AE target offset over
0.5 EV blocks publication; this is an initial conservative exposure-limit gate,
not an accuracy measurement. A 3 s settling timeout explains instability while
continuing to sample; a 1 s fresh-frame watchdog publishes Stale. All thresholds
require hardware evaluation. This window reduces transient recommendation changes;
additional ND-boundary hysteresis is deferred until real-device traces justify a
policy that never recommends less than the required attenuation.

Hold/manual/background transitions cancel the capture subscription. Generations
reject superseded events; held readings retain timestamp and camera provenance.
Interruption end restarts settling; runtime errors expose Retry. Live labels say
Stable · Uncalibrated, with no numeric accuracy claim. Calibration remains M4.

See the [metering guide](P17LightMeter/Metering/README.md) for ownership and tests,
and the [physical-device checklist](doc/validation/M3-device-checks.md) for the
remaining exit checks. M3 is not hardware-validated yet. Reference-meter accuracy,
real permission prompts, tap mapping, exposure saturation, lifecycle recovery, and
full VoiceOver traversal cannot be established by the simulator tests.

Verification: 26 package tests, 20 app tests, and 3 simulator UI journeys passed on
October 22, 2026. Simulator and unsigned iPhone builds succeeded. No physical
camera or reference-meter validation has been performed in this milestone run.


### Third mode — Slow-speed

Slow-speed remains a distinct selection but currently matches P / Program behavior:
shared editable aperture target, target-feasibility output, ND selection, and shutter
limit warnings. The initial fixed-f/16 assumption was withdrawn and removed.
Dedicated Slow-speed features are deferred. Tests cover calculation parity across
apertures, light levels and filters, target validation, and preserved held state.

Verification after the correction: 29 core tests, 21 app tests, and 3 simulator UI
journeys passed. The UI journey confirms Slow-speed and Program both show target
f/8 with ND8 at 1/256 s for the reference scene. Physical-device validation remains
pending.


### Framing correction — physical comparison

The user reports that the app works on an iPhone 16 Pro Max. In a comparison using
the green guide, the PENTAX 17 was 2.2 m from the subject and the phone needed to
move back to 3.2 m for similar framing. This implies an approximate display-scale
ratio of 2.2/3.2 = 0.6875, or a 31.25% reduction from the previous image scale at
the same position. This is a comparison baseline, not a calibrated universal factor.

The old preview aspect-filled a wide panel independently of the portrait guide,
introducing an extra screen-dependent crop. The new image rectangle is based on
active-format FOV, geometric distortion correction, output crop, zoom, and the
shared guide rectangle. Portrait video height in points is:

`guideHeight * tan(phoneOutputHorizontalFOV / 2) / (24 / (2 * 25))`

The rotated video width follows its aspect ratio. This targets the film frame's
angular extent without resizing the guide, adding controls, or modifying exposure
math. The image may leave unused background outside the guide where the sensor's
view ends. Tap conversion accounts for the layer's new origin and dimensions.
Unknown or insufficient FOV falls back to the original approximate preview.

Verification completed October 22, 2026: simulator tests passed (26 app tests,
including five geometry regressions, and 3 UI journeys). The unsigned iPhone build
also succeeded. No code fixes were needed during verification. The user subsequently tested the corrected framing on the iPhone 16 Pro Max and reported it is almost the same as the PENTAX 17. Multi-distance and film-plane validation remain pending. ExposureCore was unchanged
and its separate suite was not rerun in this verification pass.


### M4 — Calibration and persistence

Implemented local settings restoration, selected-filter restoration, owned catalog/custom filters, optional film-box ISO, and reference correction capture/preview/save/reset. Generic and owned inventory are explicit choices; no filter is always available, but an empty owned inventory never falls back to generic filters. Custom attenuation accepts finite values above zero through 20 stops, with at most 100 owned entries. These are input bounds, not camera limits.

The view model retains raw readings and derives corrected EV100 exactly once. Capture requires a fresh live camera sample; saving requires the same live camera context and a snapshot no older than five minutes. This timeout permits reference entry without reusing a stale comparison later. Reference entry accepts −20…30 EV100. Corrections larger than two stops prompt a setup check, not an accuracy assertion. Held camera readings retain their matching correction; manual and simulated readings never receive it.

Calibration stores local device identity, physical camera identity, pipeline version, OS version, active/output format dimensions, media subtype, aperture, zoom, distortion correction, frame-duration configuration, raw/reference EV100, sample/save dates, and schema version. A context mismatch leaves the raw reading uncorrected and displays an inactive status. One comparison is not an uncertainty estimate or a claim of accuracy across illuminants.

The injected storage actor performs file I/O outside the main actor. A single serialized save worker coalesces pending snapshots and prevents an older edit from overwriting newer settings. A corrupt or unsupported file blocks autosaving until explicit reset; write failures offer retry. Demo/reference and isolated-test launches do not access normal saved settings. Persisted scenes are deliberately excluded.

Implementation may be tested before reference equipment is available, but M4's hardware exit remains open. Record comparisons using [the M4 checklist](doc/validation/M4-calibration-checks.md); do not infer physical accuracy from the automated tests.

Verification on October 22, 2026: 36 app tests passed on the final implementation; four simulator UI journeys passed, including custom-filter entry and disabled calibration capture in simulation. The final unsigned iPhone build passed. ExposureCore was unchanged and its separate tests were not rerun. Hardware/reference-meter validation remains pending.

### Full-width preview — user-selected presentation

After M4 iPhone testing, the user reported the wide rounded preview shrinking into a narrow square-edged image. Startup used aspect-fill; incoming optical metadata then applied the previous PENTAX framing correction. The user explicitly selected a consistently full-width preview after being informed that this changes framing inside the green guide.

The preview now always aspect-fills the rounded panel. Removed the optical display-scaling path and its unused metadata events, retaining the camera configuration identity used for exposure calibration. Tap conversion continues through AVFoundation so it accounts for the aspect-fill crop. The green guide and thirds grid keep their existing dimensions; the bottom “17 × 24 · Approximate guide” caption is removed. The earlier near-match report describes the superseded display mode, not the current full-width preview.

Verification: 34 app tests passed on the iPhone 18 Pro / iOS 27.0 simulator, including three preview/guide layout tests. The unsigned iPhone build passed. The obsolete optical-scaling tests were replaced with full-width layout regressions. UI journeys and ExposureCore were not rerun for this presentation change; physical preview and tap alignment remain for the user's iPhone check.

### Matched framing and on-demand scene readings — supersedes full-width preview

The user reversed the full-width presentation choice: PENTAX matching has priority. Restored optical FOV scaling in a narrow viewport; the preview remains hidden until metadata permits the correct scale, with no aspect-fill fallback. The overlay caption stays removed. Portrait is the startup orientation; landscape swaps the 17 × 24 mm film axes. Both orientations use the resulting guide size and camera FOV to preserve angular framing. On compact displays the guide shrinks uniformly to leave accessible side controls.

The left rail shows the shutter at the recommended ND and the recommended filter card. The right rail provides Read Scene and the orientation toggle (the request named the left side twice; the second pair is placed on the right). Large Dynamic Type moves the summaries/actions into a vertical layout. Detailed filter comparison and exposure warnings remain below.

Camera preview lifetime is now separate from measurement lifetime. Starting the app, tapping the preview, changing orientation, or foregrounding does not take an exposure reading. Read Scene creates a uniquely identified request and a fresh bounded settling window; one stable sample completes it. Further frames do not update the displayed result. Timeout, interruption, or stale frames end the request and require another press. Late responses from older requests cannot replace a newer reading or manual input. Backgrounding stops capture while preserving a completed measured/manual snapshot.

Calibration accepts a settled, explicitly measured camera snapshot from the same session/configuration for up to five minutes. The selected snapshot must still be the latest measurement at save time; manual/simulated/pending/expired values are rejected. This replaces the previous live-reading-only calibration flow. It does not establish accuracy across conditions.

Every launch and saved-data reset selects P / Program; the previous saved mode remains schema-compatible but is intentionally not restored. Portrait orientation is session-only and starts afresh on launch. Other settings and exposure calibration remain persisted.

Verification: 35 app tests and four UI journeys passed on iPhone 18 Pro / iOS 27.0. The reading/manual-entry/orientation journey also passed on iPhone 17e after a compact-screen rail-width correction; exported portrait/landscape screenshots were inspected. The unsigned iPhone build passed. ExposureCore was unchanged and its separate suite was not rerun. Physical portrait/landscape framing, preview taps, camera interruptions, and reference-meter accuracy remain device checks.

### Fixed square composition viewport

The preview now uses the same square bounds for portrait and landscape guides. Its side length is capped at 240 points and reserves the existing side-control space on compact screens. Only the green film guide changes orientation; side-control sizes and positions stay fixed. The matched optical scaling remains unchanged, and in square bounds the camera image scale is identical for both orientations. The side rails keep their 240-point height to accommodate the buttons on smaller screens.

Verification: six framing tests and the reading/manual-entry/orientation UI journey passed on iPhone 17e / iOS 27.0. The UI regression compares shutter, ND card, Read Scene, and Rotate frames before and after rotation. Exported screenshots confirm square bounds and fixed side controls. Physical-camera appearance remains an iPhone check.
