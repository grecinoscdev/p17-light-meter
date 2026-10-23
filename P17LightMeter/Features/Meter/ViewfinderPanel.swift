import SwiftUI
import ExposureCore

/// Composition stays live; the side cards describe the last requested measurement.
struct ViewfinderPanel: View {
    let model: MeterViewModel
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        if textSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 16) {
                recommendationSummary
                readingActions
            }
        } else {
            GeometryReader { geometry in
                let previewWidth = CompositionGuide.previewWidth(availableWidth: geometry.size.width,
                    orientation: model.guideOrientation)
                let railWidth = max(0, (geometry.size.width - previewWidth - 24) / 2)
                HStack(spacing: 12) {
                    recommendationSummary.frame(width: railWidth, height: 240)
                    ZStack {
                        if let camera = model.camera {
                            CameraPreview(format: model.previewFormat, orientation: model.guideOrientation,
                                camera: camera, centerResetID: model.centerResetID,
                                allowsMetering: model.canChooseMeteringPoint)
                        }
                        DemoViewfinder(showsGrid: model.showsGrid, hasCamera: model.camera != nil,
                            orientation: model.guideOrientation).allowsHitTesting(false)
                    }
                    .frame(width: previewWidth, height: 240)
                    .clipped()
                    readingActions.frame(width: railWidth, height: 240)
                }.transaction { $0.animation = nil }
            }.frame(height: 240)
        }
    }

    private var recommendationSummary: some View {
        VStack(spacing: 12) {
            VStack(spacing: 6) {
                Text("Shutter").font(.caption)
                if let assessment = model.recommendedAssessment {
                    let exposure = assessment.exposure
                    Text(ExposureFormatting.shutter(model.cameraMode == .bokeh
                        ? exposure.modeledShutterSeconds ?? exposure.target.shutterSeconds
                        : exposure.target.shutterSeconds))
                        .font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.75)
                        .accessibilityIdentifier("viewfinderShutter")
                    Text(model.cameraMode == .bokeh ? "Modeled" : "At target aperture")
                        .font(.caption2).multilineTextAlignment(.center)
                } else { Text("—").font(.headline) }
            }
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                Text("Use ND").font(.caption2).multilineTextAlignment(.center)
                if let assessment = model.recommendedAssessment {
                    Button { model.selectedFilter = nil } label: {
                        VStack(spacing: 6) {
                            Text(ExposureFormatting.filter(assessment.filter)).font(.headline)
                            Text("\(ExposureFormatting.number(assessment.filter.stops)) stops").font(.caption)
                        }.frame(maxWidth: .infinity, minHeight: 66).padding(.vertical, 6)
                            .background(MeterTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(MeterTheme.background)
                    }.accessibilityLabel("Recommended \(ExposureFormatting.filter(assessment.filter)); use recommendation")
                        .accessibilityIdentifier("viewfinderRecommendation")
                } else {
                    Text(model.reading == nil ? "—" : "No match")
                        .font(.headline).multilineTextAlignment(.center)
                        .frame(minHeight: 66)
                }
            }
        }.padding(.vertical, 8)
    }

    private var readingActions: some View {
        VStack(spacing: 12) {
            Button { model.readScene() } label: {
                VStack(spacing: 8) {
                    Image(systemName: "viewfinder").font(.title2)
                    Text(model.isReadingScene ? "Reading…" : "Read Scene").font(.caption.bold())
                }.multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 76)
            }.buttonStyle(MeterPillStyle(horizontalPadding: 4)).disabled(!model.canReadScene)
                .accessibilityIdentifier("readScene")
            Spacer(minLength: 0)
            Button { model.toggleGuideOrientation() } label: {
                VStack(spacing: 8) {
                    Image(systemName: model.guideOrientation == .portrait ? "rectangle" : "rectangle.portrait")
                        .font(.title2)
                    Text("Rotate").font(.caption.bold())
                }.multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 76)
            }.buttonStyle(MeterPillStyle(horizontalPadding: 4))
                .accessibilityLabel(model.guideOrientation == .portrait ? "Switch guide to landscape" : "Switch guide to portrait")
                .accessibilityValue(model.guideOrientation.rawValue)
                .accessibilityIdentifier("guideOrientation")
        }.padding(.vertical, 8)
    }
}
