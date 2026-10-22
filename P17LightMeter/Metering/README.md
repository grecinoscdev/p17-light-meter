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
- Stable describes repeatability only. There is no numeric accuracy claim, saved calibration, or validated Program map.

`CameraPreview` owns portrait rotation, aspect-fill rendering, and tap conversion
through `captureDevicePointConverted(fromLayerPoint:)`. The point biases camera AE;
it is not a calibrated spot meter. Center metering is an accessible alternative.
The 17:24 overlay is an approximate composition guide, not a validated field of view.

Tests: `ReadingStabilityTests` exercises the pure temporal policy with explicit
monotonic times. `LiveMeterStateTests` exercises synthetic event streams, lifecycle,
provenance, stale samples, and cancellation without camera hardware or sleeps.
`MeterViewModelTests` retains the demo/manual/ExposureCore integration regressions.
