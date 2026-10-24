import Foundation

/// Layout shared by the existing overlay and camera preview. These are screen
/// points, not sensor pixels. Keeping one rectangle prevents independent crops.
enum GuideOrientation: String, CaseIterable {
    case portrait, landscape
    var filmHeightMM: Double { self == .portrait ? 24 : 17 }
}

enum CompositionGuide {
    /// Keep the original 204-point long side where space permits. Compact screens
    /// shrink both axes together; optical scaling uses the resulting guide size.
    static func frame(in bounds: CGRect, orientation: GuideOrientation = .portrait) -> CGRect {
        let availableWidth = max(0, bounds.width - 36)
        let availableHeight = max(0, bounds.height - 36)
        let width: Double
        let height: Double
        if orientation == .portrait {
            width = min(availableWidth, availableHeight * 17 / 24)
            height = width * 24 / 17
        } else {
            width = min(availableWidth, availableHeight)
            height = width * 17 / 24
        }
        return CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
    }

    /// A square viewport keeps both side rails fixed when only the guide rotates.
    static func previewSide(availableWidth: Double) -> Double {
        // Reserve two 64-point rails and 12-point gaps for readable 44-point buttons.
        return max(0, min(240, availableWidth - 152))
    }
}

/// Immutable optical metadata copied on the capture queue. Dimensions are in the
/// sensor's unrotated landscape orientation; FOV is horizontal, in degrees.
/// Apple reports zero when FOV is unknown, which this boundary rejects.
struct CameraPreviewFormat: Equatable, Sendable {
    let horizontalFieldOfViewDegrees: Double
    let formatWidth: Double
    let formatHeight: Double
    let outputWidth: Double
    let outputHeight: Double
    let zoomFactor: Double

    init?(horizontalFieldOfViewDegrees: Double, formatWidth: Double, formatHeight: Double,
          outputWidth: Double, outputHeight: Double, zoomFactor: Double) {
        guard horizontalFieldOfViewDegrees.isFinite, (0..<180).contains(horizontalFieldOfViewDegrees),
              horizontalFieldOfViewDegrees > 0,
              [formatWidth, formatHeight, outputWidth, outputHeight, zoomFactor].allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        self.horizontalFieldOfViewDegrees = horizontalFieldOfViewDegrees
        self.formatWidth = formatWidth
        self.formatHeight = formatHeight
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.zoomFactor = zoomFactor
    }
}

/// Pinhole approximation of the PENTAX 17 film frame, not optical-finder calibration.
/// Ricoh specifies a 25 mm lens and 17 × 24 mm portrait frame:
/// https://www.ricoh-imaging.co.jp/english/products/pentax17/spec/
/// Their half-angle tangents are 17/(2*25) horizontally and 24/(2*25) vertically.
/// Phone FOV comes from the active format, not an assumed iPhone lens equivalent.
enum PreviewFraming {
    private static let pentaxFocalLengthMM = 25.0

    /// Returns the entire portrait video image's rectangle in view coordinates.
    /// It may extend beyond the panel, or leave unused space outside the guide.
    /// Nil means invalid geometry or a phone view too narrow to cover the guide;
    /// the caller hides the image rather than displaying an incorrectly scaled crop.
    static func imageFrame(in bounds: CGRect, format: CameraPreviewFormat, orientation: GuideOrientation = .portrait) -> CGRect? {
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 36 else { return nil }
        let guide = CompositionGuide.frame(in: bounds, orientation: orientation)
        let formatAspect = format.formatWidth / format.formatHeight
        let outputAspect = format.outputWidth / format.outputHeight
        // A narrower output aspect crops the native horizontal FOV; a wider one
        // crops the vertical FOV. Uniform downsampling does not change the FOV.
        let horizontalCropFraction = min(1, outputAspect / formatAspect)
        let phoneHorizontalHalfAngleTangent = tan(format.horizontalFieldOfViewDegrees * .pi / 360)
            * horizontalCropFraction / format.zoomFactor
        // Portrait rotation makes the sensor's horizontal FOV the screen's vertical FOV.
        let pentaxVerticalHalfAngleTangent = orientation.filmHeightMM / (2 * pentaxFocalLengthMM)
        let imageHeight = guide.height * phoneHorizontalHalfAngleTangent / pentaxVerticalHalfAngleTangent
        let imageWidth = imageHeight / outputAspect
        guard imageWidth.isFinite, imageHeight.isFinite,
              imageWidth >= guide.width, imageHeight >= guide.height else { return nil }
        return CGRect(x: bounds.midX - imageWidth / 2, y: bounds.midY - imageHeight / 2,
                      width: imageWidth, height: imageHeight)
    }
}
