import SwiftUI

/// Keeps a raw comparison snapshot while the live meter continues to establish
/// freshness. Leaving this screen discards the draft, never the saved correction.
struct CalibrationView: View {
    let model: MeterViewModel
    @State private var sample: ExposureReading?
    @State private var referenceText = ""
    @State private var message: String?
    private var referenceEV100: Double? {
        Double(referenceText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }
    var body: some View {
        Form {
            Section("Reference comparison") {
                Text("Fill the metering area with an evenly lit neutral target. Set a trusted reflected-light reference meter to ISO 100 and measure the same target without a filter. Keep the target and lighting unchanged while entering its EV100.")
                Text("Resume live metering first. Held, manual, simulated, and unsettled readings cannot be used.")
                Button("Capture stable reading") {
                    sample = model.calibrationSample()
                    message = sample == nil ? "Wait for a fresh, stable camera reading and try again." : nil
                }.disabled(model.calibrationSample() == nil)
                if let sample {
                    Text("Raw phone reading: \(ExposureFormatting.number(sample.sceneEV100, digits: 3)) EV100")
                    TextField("Reference meter EV100", text: $referenceText).keyboardType(.numbersAndPunctuation)
                        .accessibilityIdentifier("referenceEV100")
                    if let reference = referenceEV100, reference.isFinite, (-20...30).contains(reference) {
                        Text("Correction: \(ExposureFormatting.number(reference - sample.sceneEV100, digits: 3)) EV")
                        Text("Corrected comparison: \(ExposureFormatting.number(reference, digits: 3)) EV100")
                        if abs(reference - sample.sceneEV100) > 2 {
                            Text("This is a large correction. Check reference ISO 100, target coverage, and lighting before saving.").foregroundStyle(.orange)
                        }
                    }
                    Button("Save reference correction") {
                        if let reference = referenceEV100, model.saveCalibration(sample: sample, referenceEV100: reference) {
                            self.sample = nil
                            message = "Reference correction saved to current settings."
                        } else { message = "Enter a reference from −20 to 30 EV100 and keep live metering active. If the camera changed or five minutes passed, capture again." }
                    }
                }
                if let message { Text(message) }
            }
            Section("Saved correction") {
                Text(model.calibrationStatus)
                if let record = model.calibration {
                    Text("\(ExposureFormatting.number(record.offsetEV, digits: 3)) EV · \(record.savedAt.formatted(date: .abbreviated, time: .shortened))")
                    Button("Reset reference correction", role: .destructive) { model.resetCalibration(); sample = nil }
                }
                Text("One comparison does not establish accuracy across lighting or brightness levels. Camera or operating-system changes disable a mismatched correction. Stability describes repeatability, not accuracy.").font(.footnote)
                if let message = model.settingsMessage { Text(message).foregroundStyle(.orange) }
            }
        }.navigationTitle("Calibration")
    }
}
