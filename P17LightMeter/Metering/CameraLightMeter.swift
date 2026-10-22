import AVFoundation
import ExposureCore
import Foundation

/// Owns the fixed rear camera and all mutable capture state on `captureQueue`.
/// Blocking configuration/start/stop and video callbacks use that same serial queue.
///
/// AVFoundation predates Swift Sendable: this audited queue-bound bridge is unchecked
/// because the compiler cannot prove DispatchQueue isolation. No device, input, output,
/// or sample buffer escapes the queue. The sole exception is attaching the immutable
/// session reference to a main-thread preview layer, AVFoundation's supported preview
/// pattern; UI code never configures or starts/stops the session. Frames are discarded,
/// never recorded, analyzed for image content, or sent outside this service.
final class CameraLightMeter: NSObject, LightMeter, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let captureQueue = DispatchQueue(label: "P17LightMeter.capture", qos: .userInitiated)
    private let session = AVCaptureSession()
    private var device: AVCaptureDevice?
    private var output: AVCaptureVideoDataOutput?
    private var continuation: AsyncThrowingStream<MeterEvent, Error>.Continuation?
    private var subscriptionID: UUID?
    private var observers: [NSObjectProtocol] = []
    private var watchdog: DispatchSourceTimer?
    private var stability = ReadingStability(seconds: 0)
    private var lastSampleSeconds = 0.0
    private var lastFrameSeconds = 0.0
    private var lastPresentationSeconds = -Double.infinity
    private var lastEvent: MeterEvent?
    private var previewFormat: CameraPreviewFormat?
    private enum CaptureStatus { case stopped, running, interrupted, failed }
    private var captureStatus: CaptureStatus = .stopped
    // Half a stop residual is a conservative AE failure gate, pending device validation.
    private static let maximumExposureTargetOffsetEV = 0.5

    @MainActor func attachPreview(to layer: AVCaptureVideoPreviewLayer) {
        layer.session = session
    }

    func events() async -> AsyncThrowingStream<MeterEvent, Error> {
        let id = UUID()
        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(8)) { continuation in
            captureQueue.async { self.begin(id: id, continuation: continuation) }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.captureQueue.async {
                    if self.subscriptionID == id { self.stop() }
                }
            }
        }
    }

    private func begin(id: UUID, continuation: AsyncThrowingStream<MeterEvent, Error>.Continuation) {
        dispatchPrecondition(condition: .onQueue(captureQueue))
        stop()
        subscriptionID = id
        self.continuation = continuation
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else {
            publish(.unavailable("No rear camera is available. Use manual EV, or run the simulated demo from the Xcode scheme."))
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndStart()
        case .notDetermined:
            publish(.requestingPermission)
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                self.captureQueue.async {
                    guard self.subscriptionID == id else { return }
                    if granted { self.configureAndStart() } else { self.publish(.denied) }
                }
            }
        case .denied, .restricted: publish(.denied)
        @unknown default: publish(.unavailable("Camera permission is unavailable. Enter a manual EV."))
        }
    }

    private func configureAndStart() {
        publish(.starting)
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            publish(.unavailable("No rear camera is available. Use manual EV, or run the simulated demo from the Xcode scheme."))
            return
        }
        guard camera.isExposureModeSupported(.continuousAutoExposure) else {
            publish(.unavailable("This camera does not support continuous light metering. Use manual EV."))
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
            session.beginConfiguration()
            // A fixed physical wide camera and one preset avoid virtual lens switching.
            // The preset selects a stable format; do not change it while sampling.
            if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                publish(.unavailable("The rear camera could not be connected. Retry or use manual EV."))
                return
            }
            session.addInput(input)
            guard session.canAddOutput(videoOutput) else {
                session.removeInput(input)
                session.commitConfiguration()
                publish(.unavailable("Camera samples are unavailable. Retry or use manual EV."))
                return
            }
            session.addOutput(videoOutput)
            session.commitConfiguration()
            // Stabilization adds a changing crop that would invalidate the FOV estimate.
            if let connection = videoOutput.connection(with: .video), connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .off
            }
            device = camera
            output = videoOutput
            try camera.lockForConfiguration()
            camera.videoZoomFactor = 1
            camera.exposureMode = .continuousAutoExposure
            camera.setExposureTargetBias(0)
            if camera.hasTorch && camera.isTorchModeSupported(.off) { camera.torchMode = .off }
            if camera.isExposurePointOfInterestSupported { camera.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5) }
            camera.unlockForConfiguration()
            installObservers()
            session.startRunning()
            guard session.isRunning else {
                publish(.unavailable("The camera could not start. Close other camera apps, then retry."))
                return
            }
            captureStatus = .running
            resetWindow()
            startWatchdog()
        } catch {
            publish(.unavailable("The camera could not be configured. Retry or enter a manual EV."))
        }
    }

    /// Coordinates are converted by the preview layer, never by the feature/view model.
    func meter(at point: CGPoint) {
        guard point.x.isFinite, point.y.isFinite, (0...1).contains(point.x), (0...1).contains(point.y) else { return }
        captureQueue.async {
            guard self.captureStatus == .running, let camera = self.device, self.session.isRunning,
                  camera.isExposurePointOfInterestSupported else { return }
            do {
                try camera.lockForConfiguration()
                camera.exposurePointOfInterest = point
                camera.exposureMode = .continuousAutoExposure
                camera.unlockForConfiguration()
                self.resetWindow()
            } catch { self.publish(.unavailable("The metering point could not change. Retry or use manual EV.")) }
        }
    }

    private func resetWindow() {
        let seconds = ProcessInfo.processInfo.systemUptime
        stability = ReadingStability(seconds: seconds)
        lastSampleSeconds = seconds
        lastFrameSeconds = seconds
        lastPresentationSeconds = -.infinity
        lastEvent = nil
        publish(.settling)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        dispatchPrecondition(condition: .onQueue(captureQueue))
        guard output === self.output, captureStatus == .running, session.isRunning,
              let camera = device, continuation != nil,
              CMSampleBufferDataIsReady(sampleBuffer) else { return }
        let presentationSeconds = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard presentationSeconds.isFinite, presentationSeconds > lastPresentationSeconds else { return }
        let frameAgeSeconds = CMClockGetTime(CMClockGetHostTimeClock()).seconds - presentationSeconds
        guard frameAgeSeconds >= 0, frameAgeSeconds <= ReadingStability.staleInterval else { return }
        lastPresentationSeconds = presentationSeconds
        let seconds = ProcessInfo.processInfo.systemUptime
        lastFrameSeconds = seconds
        guard seconds - lastSampleSeconds >= ReadingStability.sampleInterval else { return }
        lastSampleSeconds = seconds
        updatePreviewFormat(camera: camera, sampleBuffer: sampleBuffer)
        // Device exposure properties describe the current AE solution. Frame callbacks
        // establish freshness; they are not a calibrated, per-pixel luminance measure.
        let sceneEV100 = try? SceneExposure.ev100(phoneAperture: Double(camera.lensAperture),
            phoneExposureSeconds: camera.exposureDuration.seconds, phoneISO: Double(camera.iso))
        // A residual over half a stop means AE has not reached its own target (often
        // saturation). This conservative gate is a quality rule, not an accuracy claim.
        let offset = Double(camera.exposureTargetOffset)
        let limited = !offset.isFinite || abs(offset) > Self.maximumExposureTargetOffsetEV
        publish(stability.accept(sceneEV100: sceneEV100, adjusting: camera.isAdjustingExposure,
            exposureLimited: limited, seconds: seconds, timestamp: Date().addingTimeInterval(-frameAgeSeconds)))
    }

    private func updatePreviewFormat(camera: AVCaptureDevice, sampleBuffer: CMSampleBuffer) {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let activeFormat = camera.activeFormat
        let dimensions = CMVideoFormatDescriptionGetDimensions(activeFormat.formatDescription)
        let outputDimensions = CMVideoFormatDescriptionGetDimensions(description)
        let fieldOfView = camera.isGeometricDistortionCorrectionEnabled
            ? activeFormat.geometricDistortionCorrectedVideoFieldOfView : activeFormat.videoFieldOfView
        previewFormat = CameraPreviewFormat(horizontalFieldOfViewDegrees: Double(fieldOfView),
            formatWidth: Double(dimensions.width), formatHeight: Double(dimensions.height),
            outputWidth: Double(outputDimensions.width), outputHeight: Double(outputDimensions.height),
            zoomFactor: Double(camera.videoZoomFactor))
    }

    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: captureQueue)
        timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            guard let self, self.captureStatus == .running else { return }
            if ProcessInfo.processInfo.systemUptime - self.lastFrameSeconds > ReadingStability.staleInterval {
                self.stability = ReadingStability(seconds: ProcessInfo.processInfo.systemUptime)
                self.publish(.stale)
            }
        }
        watchdog = timer
        timer.resume()
    }

    private func installObservers() {
        guard let id = subscriptionID else { return }
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.interruptionEndedNotification,
                     AVCaptureSession.runtimeErrorNotification] {
            let token = NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                guard let self else { return }
                self.captureQueue.async {
                    guard self.subscriptionID == id else { return }
                    if name == AVCaptureSession.wasInterruptedNotification {
                        guard self.captureStatus == .running else { return }
                        self.captureStatus = .interrupted
                        self.publish(.interrupted)
                    } else if name == AVCaptureSession.interruptionEndedNotification {
                        guard self.captureStatus == .interrupted else { return }
                        if !self.session.isRunning { self.session.startRunning() }
                        guard self.session.isRunning else {
                            self.captureStatus = .failed
                            self.publish(.unavailable("The camera could not reconnect. Retry or use manual EV."))
                            return
                        }
                        self.captureStatus = .running
                        self.resetWindow()
                    } else {
                        self.captureStatus = .failed
                        self.publish(.unavailable("The camera stopped unexpectedly. Retry to reconnect, or use manual EV."))
                        self.watchdog?.cancel()
                        self.watchdog = nil
                        self.output?.setSampleBufferDelegate(nil, queue: nil)
                        self.session.stopRunning()
                    }
                }
            }
            observers.append(token)
        }
    }

    private func publish(_ event: MeterEvent) {
        // Repeated unavailable/settling states do not need four identical UI updates/sec.
        guard event != lastEvent else { return }
        // Pair capabilities with status so a slow consumer cannot lose them when
        // the bounded stream replaces older events with newer readings.
        if let device {
            continuation?.yield(.pointMeteringSupported(device.isExposurePointOfInterestSupported))
        }
        continuation?.yield(.previewFormat(previewFormat))
        continuation?.yield(event)
        lastEvent = event
    }

    private func stop() {
        captureStatus = .stopped
        watchdog?.cancel(); watchdog = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        output?.setSampleBufferDelegate(nil, queue: nil)
        session.stopRunning()
        session.beginConfiguration()
        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }
        session.commitConfiguration()
        device = nil; output = nil
        previewFormat = nil
        continuation?.finish(); continuation = nil
        subscriptionID = nil; lastEvent = nil
    }
}
