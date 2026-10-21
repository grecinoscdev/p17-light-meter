import Foundation

/// Nominal attenuation in stops. Inventory ownership belongs to the caller, who
/// passes either the catalog or owned filters into NDRecommendationEngine.
public struct NDFilter: Equatable, Sendable, Identifiable {
    public let id: String
    public let stops: Double

    /// Stable nonempty identifiers and finite nonnegative stops are required.
    /// Rejects attenuation whose factor cannot be represented as a finite Double.
    public init(id: String, stops: Double) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExposureError.invalidFilterIdentifier
        }
        guard stops.isFinite, stops >= 0, exp2(stops).isFinite else {
            throw ExposureError.invalidNDStops
        }
        self.id = id
        self.stops = stops
    }

    public var factor: Double { exp2(stops) }

    /// Only the conventional catalog factors have a standard label. Fractional
    /// custom stops should be formatted as stops by the presentation layer.
    public var standardLabel: String? {
        guard stops.rounded() == stops, (0...8).contains(stops) else { return nil }
        if stops == 0 { return "None" }
        return "ND\(Int(factor))"
    }

    // Private initializer only for the compile-time stock catalog, tested below.
    private init(catalogStops: Int) {
        id = "nd-\(catalogStops)-stops"
        stops = Double(catalogStops)
    }

    /// Includes no filter. Owned inventories must explicitly include this option
    /// if removal is allowed; an empty inventory stays empty, rather than falling back.
    public static let catalog: [NDFilter] = (0...8).map { NDFilter(catalogStops: $0) }
}

public enum NDRounding {
    /// Upward third-stop display boundary; catalog selection uses the exact minimum.
    /// A 1e-12 EV tolerance prevents representational noise adding an extra third.
    public static func upwardThirdStops(_ stops: Double) throws -> Double {
        guard stops.isFinite, stops >= 0 else { throw ExposureError.invalidNDStops }
        let thirdStopCount = (stops - ExposureTolerance.boundaryEV) * 3
        guard thirdStopCount.isFinite else { throw ExposureError.unrepresentableExposure }
        return max(0, ceil(thirdStopCount) / 3)
    }
}
