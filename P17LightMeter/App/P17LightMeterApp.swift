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
private struct DemoLightMeter: SingleReadingLightMeter {
    func reading() async throws -> ExposureReading {
        ExposureReading(sceneEV100: 15, timestamp: Date(), source: .simulated)
    }
}
