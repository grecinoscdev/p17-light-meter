# P17 Light Meter

A native iPhone light meter in development for PENTAX 17 photographers. It will measure scene light and help answer: **“Which ND filter should I use for this shot?”**

**Current status: M3 camera metering implemented; physical-device validation pending.** The default launch uses the fixed rear wide-angle camera with permission handling, preview/tap metering, settling, live EV100, Hold/manual input, and interruption recovery. Live readings are explicitly **uncalibrated**. Simulator users can enter manual EV or opt into the EV15 demo; preferences still reset on launch.

## Start here

| Document | Purpose |
| --- | --- |
| [PLAN.md](PLAN.md) | Product scope, architecture, formulas, milestones, and acceptance criteria |
| [AGENTS.md](AGENTS.md) | Coding and contribution rules for humans and agents, emphasizing junior-friendly readability and maintenance |
| [Deep research](doc/pentax17-deep-research-report.md) | Camera behavior, exposure physics, calibration, evidence, and open questions |
| [UI reference](doc/Codex-UI-Reference-3x.png) | Visual direction for the viewfinder and ND filter controls |

The PNG uses an earlier name. The app’s display name is **P17 Light Meter**, and its planned project/target identifier is `P17LightMeter`.

## What the app will do

- Measure reflected light through a fixed rear iPhone camera and display EV100.
- Account for the photographer’s PENTAX ISO dial and exposure compensation.
- Recommend an ND filter for Bokeh or a preferred Program-mode aperture.
- Compare filters through a native filter wheel, including a no-filter option and the user’s owned filters.
- Show the required shutter, exposure limits, and whether the reading is live, held, manual, or still settling.
- Offer tap-to-meter, Hold / Resume, manual EV entry, and device calibration.
- Provide an approximate half-frame composition guide based on the reference design.

The planned app works offline with settings and calibration stored on the device. v1 does not require an account, record photos, upload camera imagery, or control the PENTAX remotely.

## Understanding the results

The two modes answer different questions:

| Mode | Intended answer | Limitation |
| --- | --- | --- |
| Bokeh | How much ND makes f/3.5 possible, and what exposure would the model require? | Camera behavior and phone measurements remain estimates until validated |
| P / Program | How much ND makes the preferred aperture physically possible? | The camera may choose another aperture; its exact Program curve is not established |

The default Program target will be f/8, an editable preference rather than a claim about the lens’s proven sharpest aperture. See [the plan’s camera model and correctness rules](PLAN.md#4-camera-model-and-correctness-rules) for the evidence and assumptions.

ND is stored and explained in **stops**. Filter-factor labels are secondary: **ND8 means 3 stops**, while **ND32 means 5 stops**. The app will not use “ND3” to mean three stops.

For example, at EV100 15, camera ISO 400, EC 0, and an f/8 target, selecting ND8 (3 stops) produces a required shutter of approximately **1/256 s**. That establishes exposure feasibility at f/8; it does not guarantee that Program will select f/8. This is also the scenario shown in the UI reference.

## Development setup

Current stack:

- Swift 6, SwiftUI, iOS 17 minimum deployment target.
- Local `ExposureCore` Swift package; no third-party dependencies.
- Xcode project with shared `P17LightMeter` scheme and app/unit/UI test targets.
- Xcode 27.1 / Swift 6.4 on this development machine; older toolchains have not been verified. The project uses Xcode's synchronized source folders.

Open `P17LightMeter.xcodeproj` and select the `P17LightMeter` scheme. On a physical iPhone, run with no launch arguments and allow camera access. Defaults remain Bokeh / ISO 100 / EC 0. The simulator has no rear camera: the default launch explains that limitation and offers manual EV. For the interactive EV15 demo, add `--demo-meter` in Scheme → Run → Arguments. `--reference-scenario` also opts into simulation and selects Program / ISO 400 / f/8, with ND8 at 1/256 s. Remove both arguments to test real metering.

From the repository root:

```sh
swift test --package-path Packages/ExposureCore

xcodebuild -project P17LightMeter.xcodeproj -scheme P17LightMeter \
  -destination 'platform=iOS Simulator,id=D765A957-4815-45CB-9A10-E87E4337B608' \
  -derivedDataPath build test CODE_SIGNING_ALLOWED=NO

xcodebuild -project P17LightMeter.xcodeproj -scheme P17LightMeter \
  -destination 'generic/platform=iOS' -derivedDataPath build/device \
  build CODE_SIGNING_ALLOWED=NO
```

Verified October 22, 2026: **26 ExposureCore tests, 20 app tests, and 3 UI journeys passed.** Simulator and unsigned iPhone builds succeeded. Tests cover temporal stability/timeout/recovery, synthetic permission/interruption/failure events, stale timestamps, cancellation, held/manual provenance, existing exposure interactions, and the simulator's no-camera/manual fallback. Physical camera permissions, live capture, tap mapping, interruptions, VoiceOver traversal, and reference-meter accuracy still need a real iPhone; use the [M3 device checklist](doc/validation/M3-device-checks.md). No physical deployment or accuracy result is implied by the unsigned build. Xcode emitted SDK-version and unused App Intents metadata diagnostics; they did not fail the checks.

The destination above is this machine's iPhone 18 Pro / iOS 27.0 simulator. On another Mac, use `xcrun simctl list devices available` and replace the ID with an installed iPhone simulator. The test command builds the app and runs app-state and UI tests; the separate Swift command runs domain tests. Build output is ignored under `build/`.

For a physical device, select your development team in Xcode Signing & Capabilities and replace the provisional `com.example.P17LightMeter` bundle identifier with one you own. Simulator builds do not require signing. No signing team or physical deployment has been verified.

A physical iPhone and development signing are needed for camera testing. A trusted reflected-light meter is needed for accuracy validation. Real PENTAX 17 hardware and known ND filters are needed for field validation of camera recommendations.

## Repository layout

Implemented layout:

| Location | Role |
| --- | --- |
| `P17LightMeter.xcodeproj/` | App/test targets and shared scheme |
| `P17LightMeter/App/` | App entry and explicit real/demo dependency wiring |
| `P17LightMeter/Features/Meter/` | Interactive screen, settings/manual sheets, filter panel, state ownership, and formatting |
| `P17LightMeter/Metering/` | Streaming boundary, serial capture service, stability policy, and native preview |
| `P17LightMeter/DesignSystem/` | Shared colors |
| `Packages/ExposureCore/` | EV conversion, validated settings, versioned stock profile, Bokeh/Program assessment, ND policy, and tests |
| `P17LightMeterTests/` | Synthetic streams, stability, lifecycle, invalid data, cancellation, and display checks |
| `P17LightMeterUITests/` | Reference/demo journeys and no-camera manual fallback |
| `doc/` | Research and visual reference |

Persistence, owned-filter editing, and calibration remain future work. Real capture is implemented but has not yet been validated on physical hardware. See the [metering implementation guide](P17LightMeter/Metering/README.md) for queue ownership, sampling thresholds, and test entry points. The stock profile is compiled immutable data with version/provenance metadata; external profile import and empirical Program maps remain deferred. See [ExposureCore guide](Packages/ExposureCore/README.md) for API use and result semantics.

The intended data flow is:

```text
Phone exposure readings → calibrated scene EV100
Scene EV100 + PENTAX settings + filter choices → ExposureCore result
Result + metering state → view model → SwiftUI screen
```

Camera access, calculations, storage, and UI each have a distinct responsibility. The fake meter allows UI and calculation work without a physical camera. Detailed types and directory structure are in [PLAN.md](PLAN.md#8-architecture-and-project-organization).

## Implementation roadmap

- [x] **M0 — Foundation:** app, package, fake meter, and simulator build/tests verified. Physical signing remains unverified.
- [x] **M1 — Exposure core:** implemented formulas, stock profile, Bokeh/Program assessment, ND inventory policy, and golden/boundary tests.
- [x] **M2 — Reference UI:** controls, filter comparison, Hold/Resume, manual EV, and adaptive composition guide implemented and simulator-tested.
- [ ] **M3 — Real metering:** implementation added; physical-iPhone exit checks remain pending.
- [ ] **M4 — Calibration and persistence:** save settings and validate corrected readings.
- [ ] **M5 — Field validation and beta:** test devices, accessibility, practical camera use, and release readiness.

The `--reference-scenario` launch argument reproduces EV100 15 / ISO 400 / EC 0 / f/8 / ND8 and a 1/256 s readout. Full milestone exit criteria and estimates are in [PLAN.md](PLAN.md#9-delivery-milestones).

## Testing and accuracy

Testing will have three layers:

1. **Pure calculation tests:** independently calculated scenarios, exposure-compensation signs, ND rounding, invalid input, and bright/slow boundaries.
2. **App and simulator checks:** fake meter states, settings, calibration persistence, permission/error flows, layout, and accessibility.
3. **Physical validation:** compare supported iPhones against a reference meter under varied light, then test recommendations with the film camera and known filters.

A stable phone reading is not proof of accuracy. Simulator success is not camera calibration. The app will distinguish measurement stability, calibration status, and model confidence, and will avoid claiming exact Program behavior without empirical evidence.

The validation scenarios and proposed accuracy goals are documented in [PLAN.md](PLAN.md#10-validation-strategy). No hardware accuracy results have been recorded yet.

## Contributing

Read [AGENTS.md](AGENTS.md) before changing the project. The core expectation is that a junior developer or a new agent can understand and maintain the implementation without needing its author to explain it.

Use descriptive names with units, straightforward control flow, focused types, and comments explaining non-obvious decisions. Keep photographic calculations out of views, make failures explicit, and test behavior with independently derived expectations. Favor small, complete changes over speculative abstractions.

Update this README when setup, implemented features, or verification commands change. Update the plan when scope or evidence changes. When handing off work, state what changed, what was actually checked, and what still needs verification.

## Trying the interface and real metering

- Switch between Bokeh and Program. Bokeh fixes the target at f/3.5; Program retains your chosen aperture preference.
- Open Camera settings (sliders icon or ISO/target pill) to change ISO, EC, Program target, or the thirds grid.
- Tap a filter card to compare it. The selected filter and recommended filter remain separately labeled. Use recommendation restores automatic selection. The app cannot detect the mounted PENTAX filter.
- Hold freezes the accepted camera or simulated reading and timestamp while settings continue recalculating. Resume metering restarts capture and settling; Resume simulation accepts a fresh EV15 sample.
- Tap the EV pill for manual input, including negative EV. The supported planning-entry range is −20…30 EV100; invalid input leaves the previous reading intact. Manual readings remain visibly Manual.
- Backgrounding stops capture and invalidates unheld readings. Held/manual values remain labeled; returning to the foreground restarts sampling when needed.
- On a real iPhone, tap the preview to bias autoexposure toward that area, or use Center metering. This is not a calibrated spot meter. The camera preview remains an approximate composition guide.
- Permission denial offers Settings and manual entry. Unsettled/stale/interrupted readings hide recommendations. Stable light recovers automatically; a runtime camera failure offers Retry.
- Results and controls scroll on compact displays. The approximate guide collapses at accessibility text sizes. No animation is required for any interaction.

The simulator may take time to start on this development machine. Run the **P17LightMeter** scheme with ⌘R, or open **P17 Light Meter** in Simulator; the UI-test runner is a separate app.
