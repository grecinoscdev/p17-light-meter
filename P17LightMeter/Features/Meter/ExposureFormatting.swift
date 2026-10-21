import Foundation

/// Display rounding only; the domain result retains full precision in seconds.
enum ExposureFormatting {
    static func shutter(_ seconds: Double) -> String {
        if seconds < 1 {
            return "≈ 1/\(Int((1 / seconds).rounded())) s"
        }
        return "≈ \(seconds.formatted(.number.precision(.fractionLength(0...2)))) s"
    }
}
