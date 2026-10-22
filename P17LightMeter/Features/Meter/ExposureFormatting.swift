import Foundation
import ExposureCore

/// Display rounding only. No conversion to Int: very short valid exposures can
/// have reciprocals beyond Int's range when entered manually.
enum ExposureFormatting {
    static func number(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...digits)))
    }
    static func shutter(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "Unavailable" }
        if seconds < 1 { return "≈ 1/\(number(1 / seconds, digits: 0)) s" }
        return "≈ \(number(seconds, digits: 2)) s"
    }
    static func aperture(_ value: Double) -> String { "f/\(number(value))" }
    static func filter(_ filter: NDFilter) -> String { filter.standardLabel ?? "Custom" }
    static func range(_ range: TargetRange) -> String {
        switch range {
        case .fasterThanShutterLimit: "Target requires faster than 1/350 s. More ND is needed."
        case .slowerThanAutomaticEnvelope: "Target requires more than 4 s, outside the automatic envelope."
        case .withinPhysicalEnvelopeModeLimitUnverified: "Target is within the physical shutter envelope. Mode slow limit is unverified."
        }
    }
    static func noMatch(_ reason: NoMatchingFilterReason) -> String {
        switch reason {
        case .emptyInventory: "No filters in this inventory."
        case .insufficientAttenuation: "No listed filter is strong enough."
        case .exposuresTooSlow: "No listed filter qualifies: required exposures are too slow."
        case .inventorySkipsFeasibleRange: "Listed filters are either too weak or make the exposure too slow."
        }
    }
}
