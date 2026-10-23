import SwiftUI

@main
struct P17LightMeterApp: App {
    @State private var model: MeterViewModel

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let reference = arguments.contains("--reference-scenario")
        if reference || arguments.contains("--demo-meter") {
            _model = State(initialValue: MeterViewModel(lightMeter: DemoLightMeter(), referenceScenario: reference))
        } else {
            let camera = CameraLightMeter(deviceIdentifier: UIDevice.current.identifierForVendor?.uuidString)
            let directory = URL.applicationSupportDirectory.appendingPathComponent("P17LightMeter", isDirectory: true)
            let store: (any SettingsStore)? = arguments.contains("--isolated-settings") ? nil : FileSettingsStore(directory: directory)
            _model = State(initialValue: MeterViewModel(lightMeter: camera, camera: camera, settingsStore: store))
        }
    }

    var body: some Scene {
        WindowGroup { MeterView(viewModel: model) }
    }
}

/// Explicit opt-in demo; never substitutes for an unavailable physical camera.
private actor DemoLightMeter: LightMeter {
    private var continuation: AsyncThrowingStream<MeterEvent, Error>.Continuation?
    private var subscriptionID: UUID?

    func events() -> AsyncThrowingStream<MeterEvent, Error> {
        continuation?.finish()
        let id = UUID()
        subscriptionID = id
        let (stream, continuation) = AsyncThrowingStream<MeterEvent, Error>.makeStream(bufferingPolicy: .bufferingNewest(8))
        self.continuation = continuation
        continuation.onTermination = { [weak self] _ in Task { await self?.stop(id: id) } }
        continuation.yield(.awaitingReading)
        return stream
    }
    func requestReading(id: UUID) {
        continuation?.yield(.reading(ExposureReading(sceneEV100: 15, timestamp: Date(), source: .simulated, requestID: id)))
    }
    private func stop(id: UUID) {
        guard subscriptionID == id else { return }
        continuation = nil
        subscriptionID = nil
    }
}
