# Camera metering implementation

`LightMeter.events()` is the injectable boundary. Each subscription owns capture;
terminating it stops the session. `MeterViewModel` consumes events on the main actor.
SwiftUI cancels that task when its request ID changes, on Hold/manual input, when the
scene becomes inactive, or when the view disappears. A generation check prevents a
late event from replacing a held/manual reading. Resume creates a new subscription.

`CameraLightMeter` owns one physical rear wide-angle camera, one VGA capture preset,
and a serial dispatch queue. Configuration, start/stop, exposure-point changes,
video callbacks, notifications, and its watchdog all run on that queue. It uses a
narrow, documented `@unchecked Sendable` boundary because AVFoundation does not
express that dispatch-queue ownership in Swift's type system. Do not access its
mutable fields off the capture queue. Only attaching its immutable session reference
to a preview layer happens on the main thread, following Apple's preview model.
See [AVCaptureSession](https://developer.apple.com/documentation/avfoundation/avcapturesession)
and [AVCaptureVideoPreviewLayer](https://developer.apple.com/documentation/avfoundation/avcapturevideopreviewlayer).

The camera uses continuous AE, zero phone exposure bias, and torch off. It does not
apply the PENTAX ISO, EC, or ND to the phone. ExposureCore converts current aperture,
ISO, and exposure duration to EV100 without a calibration offset. Video buffers are
used only to establish sample freshness; images are never recorded or uploaded.
The current device exposure solution is not per-pixel luminance measurement.

Initial quality policy, pending physical-device tuning:

- Process at most four exposure samples per second, only with advancing, fresh host-clock frame timestamps.
- Require four non-adjusting samples spanning at least 0.75 seconds, with no more than 0.2 EV spread. Publish their median at full precision.
- Invalid samples, exposure adjustment, or scene jumps clear the accepted window. A new stable window is required; the previous recommendation is hidden.
- An absolute AE target offset greater than 0.5 EV is treated as an exposure-limit/unsettled condition, not as a corrected reading.
- After three seconds without stability, explain the problem instead of showing an endless spinner. Sampling continues so it can recover automatically.
- After one second without fresh video frames, publish Stale and clear the window. Interruption events also invalidate live results; interruption end restarts settling. Runtime errors offer explicit Retry.
- Stable describes repeatability only. There is no numeric accuracy claim or validated Program map. M4 optionally applies a matching saved reference correction after raw metering.

`CameraPreview` owns portrait rotation, field-of-view scaling, and tap conversion
through `captureDevicePointConverted(fromLayerPoint:)`. The point biases camera AE;
it is not a calibrated spot meter. Center metering is an accessible alternative.
The overlay and preview share `CompositionGuide.frame(in:)`, preserving the existing
panel and guide layout. `PreviewFraming` scales the image so the guide approximates
the angular extent of a 25 mm lens on 17 × 24 mm film (about 37.56° horizontal and
51.28° vertical in portrait). It uses the active format's horizontal FOV, corrected
FOV when geometric distortion correction is enabled, output aspect ratio, and zoom.
Stabilization is disabled to avoid a variable crop. Capture remains on the physical
wide camera at zoom 1; the display scale is separate from light-meter calculations.

The portrait image no longer aspect-fills the wide panel independently of the guide.
Where the sensor cannot supply the full area outside the guide, those outer areas
remain background; the image is not stretched or fabricated to fill them. Invalid
or insufficient FOV metadata retains the original approximate preview. Taps convert
from view to the resized layer's coordinates first; taps outside its image are ignored.

This is a pinhole estimate, not calibration of the PENTAX optical viewfinder or
close-distance parallax. `PreviewFramingTests` covers both axes, panel widths,
output cropping, zoom, and unavailable metadata. All five geometry tests passed on October 22, 2026, as part of 26 app tests
and 3 simulator UI journeys. Simulator and unsigned iPhone builds succeeded.
The user subsequently reported near agreement with the PENTAX 17 on an iPhone 16 Pro Max. Multiple distances, film-plane framing, and precise tap alignment still need device checks.

Tests: `ReadingStabilityTests` exercises the pure temporal policy with explicit
monotonic times. `LiveMeterStateTests` exercises synthetic event streams, lifecycle,
provenance, stale samples, and cancellation without camera hardware or sleeps.
`MeterViewModelTests` retains the demo/manual/ExposureCore integration regressions.


Each camera reading carries immutable `CameraContext` metadata assembled on the capture queue. The device identifier is injected by the app entry point; if unavailable, metering still works but calibration capture is disabled. Context includes physical camera, capture format/configuration, and OS identity. No camera imagery is stored in it.

`MeterViewModel.state` always retains raw readings. Its `reading` property applies a matching `CalibrationRecord.offsetEV` once, leaving manual/simulated samples untouched. The model owns restore/save tasks; one save worker serializes/coalesces immutable snapshots. `FileSettingsStore` owns atomic JSON I/O on its actor. Corruption blocks autosave until explicit reset, and failures remain visible. See `CalibrationTests`, `PersistenceTests`, and `SavedSettingsModelTests` for sign, context, freshness, inventory, restore/reset, and error-recovery behavior.
