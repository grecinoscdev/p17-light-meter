# Contributing to P17 Light Meter

These instructions apply to the entire repository. They guide both human contributors and coding agents.

## Primary requirement: code that someone else can understand

Write code that a junior Swift developer or a new agent can read, explain, safely change, and test without access to previous conversations. Prefer a straightforward implementation over cleverness, compactness, or speculative flexibility.

A reader should be able to answer these questions from the code and nearby documentation:

- What responsibility does this type or function have?
- Where do its inputs come from, and what units do they use?
- What result does it produce, including failures and unknown values?
- Which state does it change, and who owns that state?
- Why does a domain rule or unusual implementation choice exist?
- Where is its behavior tested?

If a change makes those answers harder to find, simplify it before considering the work complete.

## Read before changing code

1. Read [README.md](README.md) for the current project status and entry points.
2. Read the relevant sections of [PLAN.md](PLAN.md) for scope, architecture, exposure rules, and acceptance cases.
3. Inspect the existing implementation and nearby tests before introducing a new pattern.
4. Consult [the research](doc/pentax17-deep-research-report.md) when changing photographic behavior and [the UI reference](doc/Codex-UI-Reference-3x.png) when changing the main interface.

The app’s display name is **P17 Light Meter**. Use `P17LightMeter` for project and target identifiers. The original branding in the PNG is not the app name.

At the time these instructions were created, the repository contained documentation only. Confirm the current filesystem before assuming that a planned target, package, script, or test exists. Keep README status accurate as implementation progresses.

## Make the implementation easy to follow

### Names and units

- Use descriptive English names. Prefer `cameraISO`, `phoneISO`, `sceneEV100`, `ndStops`, and `shutterSeconds` over `iso`, `value`, `amount`, or `time` when the distinction matters.
- Use conventional Swift naming: `UpperCamelCase` for types and `lowerCamelCase` for functions and properties.
- Spell out unfamiliar abbreviations. Established domain terms such as ISO, EV, and ND are acceptable when their meaning is documented.
- Include units in numeric names or use a small domain type when it prevents a real mix-up. Do not build a general-purpose units framework for this app.
- Name functions after their work and boolean values after a readable condition. Avoid names such as `process`, `handleData`, or `Manager` that hide responsibility.

### Functions, types, and control flow

- Give each type a coherent responsibility and each function a clear task. Split functions when they mix calculation, device access, storage, or presentation.
- Prefer named intermediate values and explicit branches for nontrivial calculations. Avoid nested ternaries and long chains of transformations that obscure domain decisions.
- Use early returns or guards to keep normal execution easy to follow.
- Prefer immutable values and value types for readings, configuration, profiles, and calculation results.
- Use enums for meaningful states instead of several booleans that can contradict each other.
- Keep related code together. Extract a helper when it names a useful concept or removes meaningful duplication, not merely to shorten a file.
- Avoid rigid line-count rules. A cohesive function is better than many fragments whose behavior requires constant navigation.
- Keep implementation details private. Introduce public API only where a module boundary requires it.

For example, exposure code should expose the reasoning in its names:

```swift
// Inputs have already been validated at the domain boundary.
let isoAdjustmentEV = log2(Double(cameraISO) / 100.0)
let unfilteredSettingsEV = sceneEV100 + isoAdjustmentEV - exposureCompensationEV
let filteredSettingsEV = unfilteredSettingsEV - ndStops
```

This is easier to audit than compressing the calculation into an expression with single-letter variables. The formula’s sign convention still needs documentation and independent tests.

### Comments and documentation

- Explain **why** a decision exists, especially a photographic assumption, concurrency constraint, numerical tolerance, or platform workaround.
- Do not narrate obvious syntax or add a comment to every line. Improve misleading names before adding explanatory comments.
- Add Swift documentation comments to public domain APIs and non-obvious behavior. Explain purpose, units, valid inputs, outputs, failure behavior, and assumptions where relevant.
- Document significant service responsibilities and lifecycle ownership at the type boundary, so the reader knows where to start.
- Keep mathematical notation beside its plain-language meaning. State the source of camera constants and empirical values in profile metadata or a nearby reference.
- Use named constants for thresholds and tolerances, with a reason for the chosen value. Do not bury unexplained numbers in views or algorithms.
- Keep TODOs specific: describe the missing work and the condition for resolving it. Do not use TODOs to conceal an incomplete required behavior.
- Update comments when behavior changes. Remove obsolete code rather than leaving commented-out implementations.

## Preserve clear architectural boundaries

Follow the architecture in [PLAN.md](PLAN.md), adapting it only when actual implementation needs justify a change.

| Area | Responsibility | Keep out |
| --- | --- | --- |
| `ExposureCore` | Deterministic EV, exposure, profile, and ND logic | SwiftUI, AVFoundation, persistence, device state |
| `Metering` | Authorization, capture lifecycle, sampling, and reading quality | Filter recommendation policy and UI layout |
| Feature view models | Coordinate inputs, state, and domain results for the screen | Duplicated exposure formulas and direct file access |
| SwiftUI views | Render state and forward user actions | Camera session management and photographic calculations |
| `Persistence` | Save/load versioned settings and calibration | Camera control and recommendation decisions |
| `DesignSystem` | Shared visual tokens and useful controls | Business logic |

Construct dependencies at the app entry point and pass them explicitly. Use protocols at meaningful replacement boundaries, such as the real/fake light meter. Avoid global mutable state, service locators, unnecessary singletons, generic repository frameworks, and protocols for every small type.

Prefer Apple frameworks and the standard library for v1. Add a third-party dependency only when it solves a concrete problem that the existing tools do not reasonably solve; document its purpose and maintenance cost. Do not introduce an abstraction solely for a hypothetical future camera or platform.

## Keep photographic behavior honest

These rules must survive refactors and UI changes:

- Phone sensor ISO, PENTAX ISO dial, and film box ISO are different concepts. Never substitute one silently for another.
- PENTAX ISO is a user input, not an automatically optimized setting.
- Positive PENTAX EC requests more exposure and reduces required ND. Do not apply that EC to the phone’s autoexposure bias.
- Store ND attenuation in stops. Three stops means filter factor **ND8**, not “ND3.”
- The phone measures the unfiltered scene. Apply the selected PENTAX ND attenuation once.
- Bokeh exposure is modeled. Standard Program output is target-aperture feasibility until a validated empirical map exists.
- f/8 is a user preference, not a proven manufacturer-defined sweet spot.
- Do not invent aperture steps, Program thresholds, or per-mode slow limits. Unknown values must remain unknown.
- A filter must be assessed for slow-exposure problems as well as the fast-shutter limit.
- Preserve full precision for calculations and round only at defined recommendation/display boundaries.
- Keep observed stability, calibration accuracy, and camera-model confidence separate.
- Held, manual, stale, unsettled, and live readings must remain distinguishable in state and presentation.

Use [PLAN.md](PLAN.md) as the maintained source for formulas and numeric acceptance cases. If evidence changes a rule, update its provenance, tests, and documentation together.

## Handle errors, concurrency, and lifecycle explicitly

- Validate user input, persisted data, profile data, and device samples at their boundaries. Do not silently turn invalid measurements into plausible defaults.
- Use typed errors or explicit result states for recoverable failures. Avoid force unwraps, `try!`, and swallowed errors in production paths. Preconditions are for internal programmer invariants, not camera availability or user input.
- Explain recovery in user-facing language. Keep technical diagnostics in appropriate logs, without private imagery or sensitive data.
- Keep UI state on the main actor. Keep blocking capture configuration and session start/stop off the main thread on a clearly owned serial execution context.
- Document which actor or queue owns mutable capture state. An actor declaration alone does not make blocking work appropriate for the main actor.
- Pass immutable, concurrency-safe values across boundaries. Do not suppress concurrency checks merely to silence compiler diagnostics.
- Make task, observer, and stream ownership visible. Cancel tasks, remove observers, and stop or suspend capture when their owner becomes inactive.
- Use bounded waiting for settling and explicit interruption/recovery states. Repeated starts and stops must not duplicate sessions or subscriptions.
- Inject fake readings and controllable timing where needed for deterministic tests; do not base tests on arbitrary sleeps or a real camera feed.

## Build an accessible, maintainable interface

- Implement the reference with native components and reusable design tokens. Preserve its hierarchy while accommodating the P17 Light Meter name.
- Keep display formatting separate from calculation. Centralize aperture, shutter, EV, and ND formatting where shared.
- Support Dynamic Type, VoiceOver, clear units, sufficient contrast, and at least 44-point touch targets. Never use color alone to communicate status.
- Keep preview coordinate conversion in the camera/preview boundary. Do not copy screen-coordinate calculations into multiple views.
- Respect system safe areas and lifecycle. The viewfinder remains an approximate composition guide unless its field of view has been validated.
- Preserve the offline, on-device design. v1 does not record or upload camera images and does not require an account.

## Work and verification process

1. Identify the relevant milestone or requested behavior and inspect affected files. Preserve unrelated work.
2. Make the smallest complete change that solves the task. Avoid unrelated rewrites and formatting churn.
3. Add or update meaningful tests for changed calculations, state transitions, persistence, or failure handling. For a bug, add a regression case when practical.
4. Run the checks appropriate to the change using the actual project setup. Do not invent scheme names, simulator identifiers, scripts, or successful results.
5. Review the diff as a maintainer: check naming, ownership, units, error states, comments, and unnecessary complexity.
6. Update README when setup/status changes and PLAN when scope, assumptions, or milestones change.
7. Report what changed, what was verified, and any remaining limitations. Distinguish tests actually run from checks still needing hardware or credentials.

For exposure tests, derive expected values independently of the production implementation. Cover sign conventions, numerical boundaries, invalid inputs, and realistic scenarios. Organize tests by behavior and use descriptive names; do not test only private implementation details or mirror the implementation to generate the expected answer.

Simulator tests verify logic and UI. Physical iPhones and a reference meter are required for metering accuracy. Do not infer device validation from a passing simulator build. Documentation-only edits need link/content checks, not a new app test suite.

During scaffolding, add exact, verified build/test commands and environment requirements to README. Until then, report the absence of a runnable app plainly.

## Definition of done

A change is complete when its intended behavior works, its code can be followed without chat history, appropriate checks have passed or are accurately reported as blocked, and the documentation matches reality. A new maintainer should know where to make the next related change and how to verify it.
