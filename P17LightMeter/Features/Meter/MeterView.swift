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
                            Text(mode.rawValue).tag(mode)
                        }
                    }.pickerStyle(.menu).frame(minHeight: MeterTheme.minimumTouchHeight)
                } else {
                    Picker("Camera mode", selection: $model.cameraMode) {
                        ForEach(MeterViewModel.CameraMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }.pickerStyle(.segmented).accessibilityIdentifier("mode")
                }
                ViewThatFits(in: .horizontal) {
                    HStack { inputControls }
                    VStack(alignment: .leading) { inputControls }
                }
                readingStatus
                if !textSize.isAccessibilitySize {
                    ZStack {
                        if let camera = viewModel.camera {
                            CameraPreview(camera: camera, format: viewModel.previewFormat, centerResetID: viewModel.centerResetID,
                                allowsMetering: viewModel.canChooseMeteringPoint,
                                onMeteringPointChanged: { viewModel.pointWillChange() })
                        }
                        DemoViewfinder(showsGrid: viewModel.showsGrid, hasCamera: viewModel.camera != nil)
                            .allowsHitTesting(false)
                    }.frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 20))
                }
                if viewModel.camera != nil {
                    if viewModel.supportsPointMetering {
                        Button("Center metering") { viewModel.meterAtCenter() }
                            .buttonStyle(MeterPillStyle())
                            .disabled(!viewModel.canChooseMeteringPoint)
                        Text("Tap the preview to bias exposure toward an area. This is not a calibrated spot meter.").font(.caption)
                    } else {
                        Text("Camera-wide metering · point selection unavailable").font(.caption)
                    }
                }
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
        case .idle, .starting, .settling:
            ProgressView(viewModel.camera == nil ? "Settling simulated reading…" : "Settling camera exposure…").accessibilityIdentifier("readingStatus")
        case .requestingPermission:
            Text("Allow camera access to measure light. You can also enter a manual EV.")
        case .denied:
            Text("Camera access is off or restricted. Allow access in Settings, or enter a manual EV.")
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }.buttonStyle(MeterPillStyle())
            Button("Retry metering") { viewModel.resume() }.buttonStyle(MeterPillStyle())
        case .interrupted:
            Text("Camera interrupted · waiting to reconnect. Manual EV is still available.")
        case .stale:
            Text("Stale · no fresh camera reading")
            Button("Retry metering") { viewModel.resume() }.buttonStyle(MeterPillStyle())
        case let .failed(message):
            Text(message).accessibilityIdentifier("meterUnavailable")
            Button("Retry metering") { viewModel.resume() }.frame(minHeight: MeterTheme.minimumTouchHeight)
        case let .ready(reading, kind):
            let statusLayout = textSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .top))
            statusLayout {
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle(kind)).font(.subheadline.bold()).accessibilityIdentifier("readingStatus")
                    Text("EV100 \(ExposureFormatting.number(reading.sceneEV100))").accessibilityIdentifier("reading")
                    Text(reading.timestamp, format: .dateTime.hour().minute().second()).font(.caption)
                }
                if !textSize.isAccessibilitySize { Spacer() }
                Button(kind == .simulated || kind == .live ? "Hold" : (viewModel.camera == nil ? "Resume simulation" : "Resume metering")) {
                    if kind == .simulated || kind == .live { viewModel.hold() } else { viewModel.resume() }
                }.buttonStyle(MeterPillStyle()).accessibilityIdentifier("holdResume")
            }
        }
    }
    private func statusTitle(_ kind: MeterViewModel.ReadingKind) -> String {
        switch kind {
        case .simulated: "Simulated · camera inactive"
        case .live: "Live · Stable · Uncalibrated"
        case .held: viewModel.reading?.source == .camera ? "Held · Uncalibrated camera reading" : "Held · simulated reading"
        case .manual: "Manual · camera inactive"
        }
    }
}

struct MeterPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12).frame(minHeight: MeterTheme.minimumTouchHeight)
            .background(MeterTheme.panel, in: RoundedRectangle(cornerRadius: MeterTheme.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: MeterTheme.controlRadius).stroke(.white.opacity(configuration.isPressed ? 0.7 : 0.3)))
    }
}

/// Approximate half-frame overlay; field of view has not been calibrated.
struct DemoViewfinder: View {
    let showsGrid: Bool
    var hasCamera = false
    var body: some View {
        ZStack {
            if !hasCamera {
                LinearGradient(colors: [MeterTheme.panel, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            GeometryReader { geometry in
                let guide = CompositionGuide.frame(in: CGRect(origin: .zero, size: geometry.size))
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
            VStack { Spacer(); Text(hasCamera ? "17 × 24 · Approximate guide" : "17 × 24 · Approximate guide · No camera preview").font(.caption2).padding(6).background(MeterTheme.background) }
        }.clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
