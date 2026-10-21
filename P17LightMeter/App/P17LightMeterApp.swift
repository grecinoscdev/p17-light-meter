import SwiftUI

@main
struct P17LightMeterApp: App {
    var body: some Scene {
        WindowGroup {
            MeterView(viewModel: MeterViewModel(lightMeter: FakeLightMeter(
                sample: ExposureReading(sceneEV100: 15, timestamp: Date(), source: .simulated)
            )))
        }
    }
}
