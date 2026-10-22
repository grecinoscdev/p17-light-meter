import SwiftUI
import ExposureCore

struct OwnedFiltersView: View {
    @Bindable var model: MeterViewModel
    @State private var customStops = ""
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                Toggle("Use my filters", isOn: $model.useOwnedFilters)
                Text("When enabled, recommendations use only your filters plus no filter. An empty list never falls back to the generic catalog.").font(.footnote)
            }
            Section("Owned catalog filters") {
                ForEach(NDFilter.catalog.filter { $0.stops > 0 }) { filter in
                    Toggle("\(ExposureFormatting.filter(filter)) · \(ExposureFormatting.number(filter.stops)) stops", isOn: Binding(
                        get: { model.ownedFilters.contains(filter) },
                        set: { model.setOwned(filter, included: $0) }))
                }
            }
            Section("Custom attenuation") {
                TextField("ND stops", text: $customStops).keyboardType(.decimalPad).accessibilityIdentifier("customNDStops")
                Button("Add custom filter") {
                    if model.addCustomFilter(customStops) { customStops = ""; error = nil }
                    else { error = "Enter a unique attenuation above 0 and up to 20 stops. Up to 100 filters can be saved." }
                }
                if let error { Text(error).foregroundStyle(.orange) }
                Text("Enter stops, not the filter factor: ND8 is 3 stops. Fractional stops are supported.").font(.footnote)
                ForEach(model.ownedFilters.filter { !NDFilter.catalog.contains($0) }) { filter in
                    HStack {
                        Text("\(ExposureFormatting.number(filter.stops, digits: 3)) stops")
                        Spacer()
                        Button("Remove", role: .destructive) { model.setOwned(filter, included: false) }
                            .frame(minHeight: MeterTheme.minimumTouchHeight)
                    }
                }
            }
        }.navigationTitle("My filters")
    }
}
