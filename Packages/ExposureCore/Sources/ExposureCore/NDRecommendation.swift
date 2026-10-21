import Foundation

/// Evaluates one filter at the requested target. An estimated stopped-down Bokeh
/// exposure does not make a filter eligible for the f/3.5 objective.
public struct FilterAssessment: Equatable, Sendable {
    public let filter: NDFilter
    public let exposure: ExposureAssessment
    /// Selected stops minus exact minimum, which is clamped to zero in dim light.
    public let headroomStops: Double
    /// Nil means no uncertainty estimate supplied. True means the supplied scene
    /// interval spans the boundary; this is not a phone accuracy claim.
    public let crossesFastBoundary: Bool?
    public let crossesSlowBoundary: Bool?

    public var isTargetPhysicallyFeasible: Bool {
        exposure.target.range == .withinPhysicalEnvelopeModeLimitUnverified
    }
}

public enum NoMatchingFilterReason: Equatable, Sendable {
    case emptyInventory
    case insufficientAttenuation
    case exposuresTooSlow
    case inventorySkipsFeasibleRange
}

public enum FilterRecommendation: Equatable, Sendable {
    /// Nominal physical feasibility only; mode slow policy remains unverified.
    case candidate(FilterAssessment)
    case noMatch(NoMatchingFilterReason)
}

public struct NDRecommendation: Equatable, Sendable {
    public let exactMinimumStops: Double
    public let upwardThirdStopMinimum: Double
    public let recommendation: FilterRecommendation
    /// Assessed independently from recommendation. Nil means no manual selection.
    public let selected: FilterAssessment?
    /// Optional stronger candidate that covers the supplied scene interval at both
    /// boundaries. Never replaces the nominal recommendation or adds a hidden stop.
    public let strongerAlternative: FilterAssessment?
    /// Every candidate's target range explains why it was accepted or rejected.
    public let candidates: [FilterAssessment]
}

/// Stateless policy for one accepted scene reading. Metering freshness, settling,
/// hold/manual state, calibration confidence and temporal hysteresis belong upstream.
public enum NDRecommendationEngine {
    /// Chooses the weakest filter satisfying the target within the physical envelope.
    /// Inventory IDs must be unique. A manual selection may be outside the inventory.
    /// uncertaintyEV, when available, is a finite nonnegative symmetric scene interval;
    /// nil means unknown. This function never estimates uncertainty from stability.
    public static func recommend(
        sceneEV100: Double,
        configuration: ExposureConfiguration,
        inventory: [NDFilter],
        selectedFilter: NDFilter? = nil,
        uncertaintyEV: Double? = nil,
        handheldThresholdSeconds: Double = 1.0 / 60.0
    ) throws -> NDRecommendation {
        if let uncertaintyEV {
            guard uncertaintyEV.isFinite, uncertaintyEV >= 0,
                  (sceneEV100 - uncertaintyEV).isFinite,
                  (sceneEV100 + uncertaintyEV).isFinite else {
                throw ExposureError.invalidUncertainty
            }
        }
        guard Set(inventory.map(\.id)).count == inventory.count else {
            throw ExposureError.duplicateFilterIdentifier
        }
        let unfiltered = try ExposureEngine.assess(
            sceneEV100: sceneEV100, configuration: configuration, ndStops: 0,
            handheldThresholdSeconds: handheldThresholdSeconds
        )
        let exactMinimumStops = unfiltered.target.minimumNDStops
        let orderedFilters = inventory.sorted {
            if $0.stops == $1.stops { return $0.id < $1.id }
            return $0.stops < $1.stops
        }
        let candidates = try orderedFilters.map {
            try assessFilter($0, sceneEV100: sceneEV100, configuration: configuration,
                             uncertaintyEV: uncertaintyEV, handheldThresholdSeconds: handheldThresholdSeconds)
        }
        let nominalCandidate = candidates.first { $0.isTargetPhysicallyFeasible }
        let recommendation: FilterRecommendation
        if let nominalCandidate {
            recommendation = .candidate(nominalCandidate)
        } else {
            recommendation = .noMatch(noMatchReason(candidates))
        }
        let selected = try selectedFilter.map {
            try assessFilter($0, sceneEV100: sceneEV100, configuration: configuration,
                             uncertaintyEV: uncertaintyEV, handheldThresholdSeconds: handheldThresholdSeconds)
        }
        var strongerAlternative: FilterAssessment?
        if let nominalCandidate, nominalCandidate.crossesFastBoundary == true {
            // Starting from a nominally feasible exposure, no boundary crossing
            // means this stronger candidate covers the entire supplied interval.
            strongerAlternative = candidates.first {
                $0.filter.stops > nominalCandidate.filter.stops && $0.isTargetPhysicallyFeasible
                    && $0.crossesFastBoundary == false && $0.crossesSlowBoundary == false
            }
        }
        return NDRecommendation(
            exactMinimumStops: exactMinimumStops,
            upwardThirdStopMinimum: try NDRounding.upwardThirdStops(exactMinimumStops),
            recommendation: recommendation, selected: selected,
            strongerAlternative: strongerAlternative, candidates: candidates
        )
    }

    private static func assessFilter(
        _ filter: NDFilter, sceneEV100: Double, configuration: ExposureConfiguration,
        uncertaintyEV: Double?, handheldThresholdSeconds: Double
    ) throws -> FilterAssessment {
        let exposure = try ExposureEngine.assess(
            sceneEV100: sceneEV100, configuration: configuration, ndStops: filter.stops,
            handheldThresholdSeconds: handheldThresholdSeconds
        )
        var crossesFastBoundary: Bool?
        var crossesSlowBoundary: Bool?
        if let uncertaintyEV {
            let bright = try ProgramExposure.assess(
                sceneEV100: sceneEV100 + uncertaintyEV, cameraISO: configuration.cameraISO,
                exposureCompensationEV: configuration.exposureCompensationEV,
                targetAperture: configuration.mode.targetAperture, ndStops: filter.stops
            )
            let dim = try ProgramExposure.assess(
                sceneEV100: sceneEV100 - uncertaintyEV, cameraISO: configuration.cameraISO,
                exposureCompensationEV: configuration.exposureCompensationEV,
                targetAperture: configuration.mode.targetAperture, ndStops: filter.stops
            )
            crossesFastBoundary = bright.range == .fasterThanShutterLimit && dim.range != .fasterThanShutterLimit
            crossesSlowBoundary = dim.range == .slowerThanAutomaticEnvelope && bright.range != .slowerThanAutomaticEnvelope
        }
        return FilterAssessment(
            filter: filter, exposure: exposure,
            headroomStops: filter.stops - exposure.target.minimumNDStops,
            crossesFastBoundary: crossesFastBoundary, crossesSlowBoundary: crossesSlowBoundary
        )
    }

    private static func noMatchReason(_ candidates: [FilterAssessment]) -> NoMatchingFilterReason {
        if candidates.isEmpty { return .emptyInventory }
        if candidates.allSatisfy({ $0.exposure.target.range == .fasterThanShutterLimit }) {
            return .insufficientAttenuation
        }
        if candidates.allSatisfy({ $0.exposure.target.range == .slowerThanAutomaticEnvelope }) {
            return .exposuresTooSlow
        }
        return .inventorySkipsFeasibleRange
    }
}
