import SwiftUI
import ExposureCore

struct FilterPanel: View {
    let model: MeterViewModel
    let result: NDRecommendation
    private var recommended: FilterAssessment? {
        if case let .candidate(candidate) = result.recommendation { return candidate }
        return nil
    }
    private var displayed: FilterAssessment? { result.selected ?? recommended }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ND FILTERS").font(.headline).accessibilityAddTraits(.isHeader)
            Text("Exact minimum: \(ExposureFormatting.number(result.exactMinimumStops, digits: 3)) stops")
                .accessibilityIdentifier("minimumND")
            if let recommended {
                Text("Recommended: \(ExposureFormatting.filter(recommended.filter)) · \(ExposureFormatting.number(recommended.filter.stops)) stops")
                    .foregroundStyle(MeterTheme.accent).accessibilityIdentifier("recommendation")
            } else if case let .noMatch(reason) = result.recommendation {
                Label(ExposureFormatting.noMatch(reason), systemImage: "exclamationmark.triangle")
                    .accessibilityIdentifier("recommendation")
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(NDFilter.catalog) { filter in
                            let selected = displayed?.filter.id == filter.id
                            Button { model.selectedFilter = filter } label: {
                                VStack(spacing: 6) {
                                    Text(ExposureFormatting.filter(filter)).font(.title2.bold())
                                    Text("\(ExposureFormatting.number(filter.stops)) stops").font(.caption)
                                    Text(selected ? "Selected" : "Compare").font(.caption.bold())
                                    if recommended?.filter.id == filter.id { Image(systemName: "star.fill") }
                                }.padding(12).frame(minWidth: 80, minHeight: 96)
                                    .background(selected ? MeterTheme.accent : MeterTheme.background, in: RoundedRectangle(cornerRadius: 18))
                                    .foregroundStyle(selected ? MeterTheme.background : .white)
                            }
                            .id(filter.id).accessibilityIdentifier("filter-\(Int(filter.stops))")
                            .accessibilityLabel("\(ExposureFormatting.filter(filter)), \(ExposureFormatting.number(filter.stops)) stops\(selected ? ", selected" : "")\(recommended?.filter.id == filter.id ? ", recommended" : "")")
                        }
                    }
                }
                .onAppear { if let id = displayed?.filter.id { proxy.scrollTo(id, anchor: .center) } }
                .onChange(of: displayed?.filter.id) { _, id in if let id { proxy.scrollTo(id, anchor: .center) } }
            }
            if model.selectedFilter != nil {
                Button("Use recommendation") { model.selectedFilter = nil }
                    .buttonStyle(MeterPillStyle()).accessibilityIdentifier("useRecommendation")
            }
            if let displayed {
                Text("Selected: \(ExposureFormatting.filter(displayed.filter)) · \(ExposureFormatting.number(displayed.filter.stops)) stops")
                    .accessibilityIdentifier("selectedFilter")
                exposureDetails(displayed.exposure)
            }
            DisclosureGroup("How to interpret this result") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Rounded minimum: \(ExposureFormatting.number(result.upwardThirdStopMinimum, digits: 2)) stops. Filter selection uses the full-precision requirement.")
                    Text("Selection is a comparison, not detection of the filter mounted on your PENTAX. The phone measures the unfiltered scene.")
                    Text("Dense or colored filters may affect PENTAX metering. Stacking may vignette the metering area. Test your filters.")
                    Text("Live readings are uncalibrated; stability does not establish accuracy. Simulated and manual readings do not calibrate the camera. Settings are not saved yet.")
                }.font(.footnote).padding(.top, 8)
            }
        }.padding(18).background(MeterTheme.panel, in: RoundedRectangle(cornerRadius: MeterTheme.panelRadius))
    }

    @ViewBuilder private func exposureDetails(_ exposure: ExposureAssessment) -> some View {
        if model.isProgram {
            Text("At target \(ExposureFormatting.aperture(model.targetAperture))").font(.headline)
            Text(ExposureFormatting.shutter(exposure.target.shutterSeconds)).font(.largeTitle.bold()).accessibilityIdentifier("shutter")
            Text("Program may choose another aperture.")
        } else if let aperture = exposure.modeledAperture, let seconds = exposure.modeledShutterSeconds {
            Text("Estimated Bokeh · \(ExposureFormatting.aperture(aperture)) equivalent").font(.headline)
            Text(ExposureFormatting.shutter(seconds)).font(.largeTitle.bold()).accessibilityIdentifier("shutter")
            Text("Continuous model; actual aperture steps are unknown.").font(.footnote)
        } else {
            Label("Outside the modeled Bokeh envelope", systemImage: "exclamationmark.triangle")
            Text("At f/3.5, required \(ExposureFormatting.shutter(exposure.target.shutterSeconds))")
        }
        Text(ExposureFormatting.range(exposure.target.range)).accessibilityIdentifier("rangeStatus")
        if exposure.needsSteadySupport {
            Label("Use steady support · slower than the 1/60 s handheld preference", systemImage: "hand.raised")
        }
    }
}
