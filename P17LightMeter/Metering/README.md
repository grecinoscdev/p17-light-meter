# Camera metering implementation

`LightMeter.events()` owns a preview subscription. It does not request a measurement. `requestReading(id:)` starts a fresh bounded settling window and returns at most one stable result carrying that ID. `MeterViewModel` accepts only the active request's response. A completed value is a measured snapshot, never a live reading.

SwiftUI owns the preview task via requestID. Backgrounding cancels capture and any unfinished measurement; foregrounding starts preview only. Manual input cancels acceptance of a pending response without freezing the composition preview. A generation check rejects events from old subscriptions, and measurement IDs reject old responses within the same subscription.

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
- After three seconds without stability, explain the problem instead of showing an endless spinner. The request ends; the user presses Read Scene again to retry.
- After one second without fresh video frames, publish Stale and clear the window. Interruption ends an unfinished request; reconnecting starts preview without taking a reading. Completed measured snapshots keep their timestamp and provenance.
- Stable describes repeatability only. There is no numeric accuracy claim or validated Program map. M4 optionally applies a matching saved reference correction after raw metering.

`CameraPreview` owns portrait video rotation, optical display scaling, rounded clipping of the visible image, and coordinate conversion for exposure-point taps. It hides the image until `CameraPreviewFormat` is valid; it never flashes an aspect-filled crop. The viewport is square from startup. Its side length depends only on available screen width, leaving fixed left/right rails for measurement summaries and actions. The rails retain their 240-point height on compact screens so the buttons remain usable even when the square is smaller. Optical scaling can leave unused space outside the guide when the camera cannot cover the entire square; it never stretches or enlarges the image merely to fill that space.

`CompositionGuide` supports portrait and landscape film axes, always starting in portrait. `PreviewFraming` divides the guide's vertical angular tangent (24/50 or 17/50) by the phone's portrait-video tangent to obtain the correct image scale. The camera image itself is not rotated by the guide toggle. Smaller panels shrink the guide uniformly. `PreviewFramingTests` independently checks both axes, compact layouts, zoom/output crop, and hidden startup/invalid metadata. The caption remains removed.

Tap conversion uses the resized preview layer, and taps do not request a reading. Center metering is in Settings. Physical framing, landscape alignment, and off-center tap weighting still require an iPhone/PENTAX comparison.

Tests: `ReadingStabilityTests` exercises the pure temporal policy with explicit
monotonic times. `LiveMeterStateTests` exercises synthetic event streams, lifecycle,
provenance, stale samples, and cancellation without camera hardware or sleeps.
`MeterViewModelTests` retains the demo/manual/ExposureCore integration regressions.


Each camera reading carries immutable `CameraContext` metadata assembled on the capture queue. The device identifier is injected by the app entry point; if unavailable, metering still works but calibration capture is disabled. Context includes physical camera, capture format/configuration, and OS identity. No camera imagery is stored in it.

`MeterViewModel.state` always retains raw readings. Its `reading` property applies a matching `CalibrationRecord.offsetEV` once, leaving manual/simulated samples untouched. The model owns restore/save tasks; one save worker serializes/coalesces immutable snapshots. `FileSettingsStore` owns atomic JSON I/O on its actor. Corruption blocks autosave until explicit reset, and failures remain visible. See `CalibrationTests`, `PersistenceTests`, and `SavedSettingsModelTests` for sign, context, freshness, inventory, restore/reset, and error-recovery behavior.
