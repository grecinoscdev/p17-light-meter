import SwiftUI
import ExposureCore

struct MeterView: View {
    @State var viewModel: MeterViewModel
    @State private var showsSettings = false
    @State private var showsManual = false
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        @Bindable var model = viewModel
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    (Text("P") + Text("17").foregroundColor(MeterTheme.accent) + Text(" Light Meter"))
                        .font(.title.bold()).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button { showsSettings = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }
                        .accessibilityLabel("Camera settings")
                }
                if textSize.isAccessibilitySize {
                    Picker("Camera mode", selection: $model.cameraMode) {
                        ForEach(MeterViewModel.CameraMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }.pickerStyle(.menu).frame(minHeight: MeterTheme.minimumTouchHeight)
                } else {
                    Picker("Camera mode", selection: $model.cameraMode) {
                        ForEach(MeterViewModel.CameraMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }.pickerStyle(.segmented).accessibilityIdentifier("mode")
                }
                ViewThatFits(in: .horizontal) {
                    HStack { inputControls }
                    VStack(alignment: .leading) { inputControls }
                }
                if let message = viewModel.settingsMessage { Text(message).font(.footnote).foregroundStyle(.orange) }
                readingStatus
                ViewfinderPanel(model: viewModel)
                if let calculation = viewModel.calculation {
                    switch calculation {
                    case let .success(result):
                        FilterPanel(model: viewModel, result: result)
                    case .failure:
                        Label("These settings cannot produce a valid calculation. Review the camera settings or manual EV.", systemImage: "exclamationmark.triangle")
                    }
                }
            }.padding(20)
        }
        .disabled(!viewModel.settingsReady || viewModel.isResettingSavedData)
        .background(MeterTheme.background.ignoresSafeArea())
        .foregroundStyle(.white).tint(MeterTheme.accent).preferredColorScheme(.dark)
        .sheet(isPresented: $showsSettings) { MeterSettingsView(model: viewModel) }
        .sheet(isPresented: $showsManual) { ManualEVView(model: viewModel) }
        .task(id: viewModel.requestID) { await viewModel.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.becameActive() }
            else { viewModel.becameInactive() }
        }
    }

    @ViewBuilder private var inputControls: some View {
        Button("ISO \(viewModel.cameraISO) · EC \(ExposureFormatting.number(Double(viewModel.compensationThirds) / 3, digits: 2)) EV") {
            showsSettings = true
        }.buttonStyle(MeterPillStyle())
        Button("EV \(viewModel.reading.map { ExposureFormatting.number($0.sceneEV100) } ?? "—")") {
            showsManual = true
        }.buttonStyle(MeterPillStyle()).accessibilityLabel("Enter manual EV").accessibilityIdentifier("manualEV")
        Button("Target \(ExposureFormatting.aperture(viewModel.targetAperture))") {
            showsSettings = true
        }.buttonStyle(MeterPillStyle())
    }

    @ViewBuilder private var readingStatus: some View {
        switch viewModel.state {
        case .idle, .awaitingReading:
            Text("Press Read Scene to take a measurement.").accessibilityIdentifier("readingStatus")
        case .starting:
            ProgressView("Starting preview…").accessibilityIdentifier("readingStatus")
        case .settling:
            ProgressView("Reading scene…").accessibilityIdentifier("readingStatus")
        case .requestingPermission:
            Text("Allow camera access for the preview and on-demand readings. Manual EV is also available.")
        case .denied:
            Text("Camera access is off or restricted. Allow access in Settings, or enter a manual EV.")
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }.buttonStyle(MeterPillStyle())
        case .interrupted:
            Text("Camera interrupted. Press Read Scene when it is available again.")
        case .stale:
            Text("No fresh measurement. Press Read Scene to try again.")
        case let .failed(message):
            Text(message).accessibilityIdentifier("meterUnavailable")
        case let .ready(raw, kind):
            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle(kind)).font(.subheadline.bold()).accessibilityIdentifier("readingStatus")
                Text("EV100 \(ExposureFormatting.number(viewModel.reading?.sceneEV100 ?? raw.sceneEV100))")
                    .accessibilityIdentifier("reading")
                Text(raw.timestamp, format: .dateTime.hour().minute().second()).font(.caption)
            }
        }
    }
    private func statusTitle(_ kind: MeterViewModel.ReadingKind) -> String {
        switch kind {
        case .simulated: "Simulated measurement · unchanged until Read Scene"
        case .measured: "Measured · \(viewModel.calibrationStatus) · unchanged until Read Scene"
        case .manual: "Manual EV · unchanged until Read Scene"
        }
    }
}

struct MeterPillStyle: ButtonStyle {
    var horizontalPadding: Double = 12
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold))
            .padding(.horizontal, horizontalPadding).frame(minHeight: MeterTheme.minimumTouchHeight)
            .background(MeterTheme.panel, in: RoundedRectangle(cornerRadius: MeterTheme.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: MeterTheme.controlRadius).stroke(.white.opacity(configuration.isPressed ? 0.7 : 0.3)))
    }
}

/// Approximate half-frame overlay; field of view has not been calibrated.
struct DemoViewfinder: View {
    let showsGrid: Bool
    var hasCamera = false
    var orientation: GuideOrientation = .portrait
    var body: some View {
        ZStack {
            if !hasCamera {
                LinearGradient(colors: [MeterTheme.panel, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            GeometryReader { geometry in
                let guide = CompositionGuide.frame(in: CGRect(origin: .zero, size: geometry.size), orientation: orientation)
                let height = guide.height
                let width = guide.width
                ZStack {
                    Rectangle().stroke(MeterTheme.accent, lineWidth: 2)
                    if showsGrid {
                        Path { path in
                            for fraction in [1.0 / 3, 2.0 / 3] {
                                path.move(to: CGPoint(x: width * fraction, y: 0))
                                path.addLine(to: CGPoint(x: width * fraction, y: height))
                                path.move(to: CGPoint(x: 0, y: height * fraction))
                                path.addLine(to: CGPoint(x: width, y: height * fraction))
                            }
                        }.stroke(.white.opacity(0.2))
                    }
                    if !hasCamera { Image(systemName: "scope").font(.title).foregroundStyle(MeterTheme.accent) }
                }.frame(width: width, height: height).position(x: guide.midX, y: guide.midY)
            }.accessibilityHidden(true)
        }.clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
