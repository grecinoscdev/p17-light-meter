import SwiftUI
import ExposureCore

struct MeterSettingsView: View {
    @Bindable var model: MeterViewModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("PENTAX dials") {
                    Picker("Camera ISO", selection: $model.cameraISO) {
                        ForEach(Pentax17Profile.supportedCameraISO, id: \.self) { Text("ISO \($0)").tag($0) }
                    }
                    Picker("Exposure compensation", selection: $model.compensationThirds) {
                        ForEach(-6...6, id: \.self) { thirds in
                            Text("\(ExposureFormatting.number(Double(thirds) / 3, digits: 2)) EV").tag(thirds)
                        }
                    }
                    Text("PENTAX ISO is your dial setting, not the phone sensor ISO. Positive EC requests more exposure and reduces required ND.").font(.footnote)
                }
                Section("Aperture objective") {
                    if model.isProgram {
                        Picker("Program target", selection: $model.programAperture) {
                            ForEach([3.5, 4, 5.6, 8, 11, 16], id: \.self) { aperture in
                                Text(ExposureFormatting.aperture(aperture)).tag(aperture)
                            }
                        }
                        Text("These are target preferences, not known iris detents. f/8 is a preference, not a proven sweet spot.").font(.footnote)
                    } else { Text("Bokeh target is fixed at f/3.5.") }
                }
                Section("Composition") { Toggle("Show thirds grid", isOn: $model.showsGrid) }
                Section { Text("Live camera readings are uncalibrated. Stability describes repeatability, not accuracy. Calibration, owned filters, and saved preferences arrive in later milestones.") }
            }.navigationTitle("Camera settings")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}

struct ManualEVView: View {
    let model: MeterViewModel
    @State private var text = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Unfiltered scene EV100") {
                    TextField("EV100", text: $text).accessibilityIdentifier("manualEVField")
                        .keyboardType(.numbersAndPunctuation)
                    Text("Enter −20 through 30 EV100. Manual input replaces the accepted reading and is always labeled Manual.")
                    if let error { Text(error).foregroundStyle(.orange).accessibilityIdentifier("manualEVError") }
                }
                Button("Use manual reading") {
                    if model.enterManualEV(text) { dismiss() }
                    else { error = "Enter a finite number from −20 to 30." }
                }.frame(minHeight: MeterTheme.minimumTouchHeight).accessibilityIdentifier("applyManualEV")
            }.navigationTitle("Manual EV")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .onAppear { text = model.reading.map { ExposureFormatting.number($0.sceneEV100, digits: 3) } ?? "15" }
        }.preferredColorScheme(.dark)
    }
}
