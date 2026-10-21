import SwiftUI
import ExposureCore

struct MeterView: View {
    @State var viewModel: MeterViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("P17 Light Meter")
                    .font(.largeTitle.bold())
                    .foregroundStyle(MeterTheme.accent)
                Text("FOUNDATION DEMO · P / PROGRAM")
                    .font(.subheadline.weight(.semibold))
                switch viewModel.state {
                case .idle, .loading:
                    ProgressView("Loading demo reading…")
                case let .ready(reading, assessment):
                    result(reading: reading, assessment: assessment)
                case let .failed(message):
                    Text(message)
                    Button("Try again") { Task { await viewModel.retry() } }
                        .frame(minHeight: 44)
                }
            }
            .padding(24)
        }
        .background(MeterTheme.background)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .task { await viewModel.load() }
    }

    private func result(reading: ExposureReading, assessment: ProgramAssessment) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Simulated EV100 \(reading.sceneEV100.formatted(.number.precision(.fractionLength(1))))")
                .font(.title2.bold())
                .accessibilityIdentifier("reading")
            Text("PENTAX ISO 400 · EC 0 EV · Target f/8")
            RoundedRectangle(cornerRadius: 20)
                .fill(MeterTheme.panel)
                .frame(height: 180)
                .overlay {
                    VStack(spacing: 12) {
                        Image(systemName: "viewfinder").font(.largeTitle)
                        Text("Demo reading — camera inactive")
                        Text("No live metering yet").font(.caption)
                    }
                    .padding()
                }
            VStack(alignment: .leading, spacing: 16) {
                Text("SELECTED FILTER").font(.caption.bold())
                Text("ND8 · 3 stops")
                    .font(.title.bold())
                    .foregroundStyle(MeterTheme.accent)
                Text("At target f/8")
                Text(ExposureFormatting.shutter(assessment.shutterSeconds))
                    .font(.largeTitle.bold())
                    .accessibilityIdentifier("shutter")
                Text(rangeMessage(assessment.range))
                Text("Program may choose another aperture.")
                Text("Required shutter; mode limit unverified.")
                    .font(.footnote)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MeterTheme.panel, in: RoundedRectangle(cornerRadius: 20))
            Text("This fixed reference scenario verifies the exposure calculation. Camera metering, settings, and filter recommendations are planned next.")
                .font(.footnote)
        }
    }

    private func rangeMessage(_ range: TargetRange) -> String {
        switch range {
        case .fasterThanShutterLimit: "Required shutter exceeds the 1/350 s fast limit."
        case .withinPhysicalEnvelopeModeLimitUnverified: "Within the 1/350 s fast limit at target f/8."
        case .slowerThanAutomaticEnvelope: "Required shutter exceeds the 4 s automatic envelope."
        }
    }
}
