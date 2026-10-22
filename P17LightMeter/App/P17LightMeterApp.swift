import SwiftUI

@main
struct P17LightMeterApp: App {
    var body: some Scene {
        WindowGroup {
            MeterView(viewModel: MeterViewModel(lightMeter: DemoLightMeter(),
                referenceScenario: ProcessInfo.processInfo.arguments.contains("--reference-scenario")))
        }
    }
}

/// Repeatable scene with a fresh timestamp on each explicit resume. Camera access
/// is deferred to M3; simulated readings never claim live or calibrated accuracy.
private struct DemoLightMeter: LightMeter {
    func reading() async throws -> ExposureReading {
        ExposureReading(sceneEV100: 15, timestamp: Date(), source: .simulated)
    }
}
