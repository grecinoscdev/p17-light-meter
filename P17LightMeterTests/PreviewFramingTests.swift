import AVFoundation
import XCTest
@testable import P17LightMeter

@MainActor
final class PreviewFramingTests: XCTestCase {
    private func format(fov: Double = 90, outputWidth: Double = 640, outputHeight: Double = 480,
                        zoom: Double = 1) throws -> CameraPreviewFormat {
        try XCTUnwrap(CameraPreviewFormat(horizontalFieldOfViewDegrees: fov,
            formatWidth: 640, formatHeight: 480, outputWidth: outputWidth, outputHeight: outputHeight, zoomFactor: zoom))
    }
    func testPortraitGuideKeepsPreviouslyMatchedSize() {
        let guide = CompositionGuide.frame(in: CGRect(x: 0, y: 0, width: 180.5, height: 240))
        XCTAssertEqual(guide.width, 144.5)
        XCTAssertEqual(guide.height, 204)
        XCTAssertEqual(guide.midX, 90.25)
        XCTAssertEqual(guide.midY, 120)
    }
    func testBothOrientationsMatchFilmAxesWithoutRotatingCameraImage() throws {
        for orientation in GuideOrientation.allCases {
            let bounds = CGRect(x: 0, y: 0, width: 240, height: 240)
            let guide = CompositionGuide.frame(in: bounds, orientation: orientation)
            let image = try XCTUnwrap(PreviewFraming.imageFrame(in: bounds, format: format(), orientation: orientation))
            // At 90 degrees, full portrait video height is 204 / (24 / 50) = 425.
            // Rotating the film rectangle swaps 17/50 and 24/50 angular tangents.
            XCTAssertEqual(image.height, 425, accuracy: 1e-10)
            XCTAssertEqual(image.width, 318.75, accuracy: 1e-10)
            XCTAssertEqual(guide.height / image.height, orientation == .portrait ? 0.48 : 0.34, accuracy: 1e-12)
            XCTAssertEqual(guide.width / image.width * 0.75, orientation == .portrait ? 0.34 : 0.48, accuracy: 1e-12)
        }
    }
    func testCompactPanelsPreserveOpticalRatiosAndReserveButtonSpace() throws {
        for availableWidth in [280.0, 335, 400, 500] {
            for orientation in GuideOrientation.allCases {
                let width = CompositionGuide.previewWidth(availableWidth: availableWidth, orientation: orientation)
                XCTAssertGreaterThanOrEqual(availableWidth - width, 152)
                let bounds = CGRect(x: 0, y: 0, width: width, height: 240)
                let guide = CompositionGuide.frame(in: bounds, orientation: orientation)
                let image = try XCTUnwrap(PreviewFraming.imageFrame(in: bounds, format: format(), orientation: orientation))
                XCTAssertTrue(bounds.contains(guide))
                XCTAssertEqual(guide.height / image.height, orientation == .portrait ? 0.48 : 0.34, accuracy: 1e-12)
            }
        }
    }
    func testImageHiddenUntilMatchedMetadataThenRemainsMatchedAcrossLayouts() throws {
        let view = CameraPreview.PreviewView(frame: CGRect(x: 0, y: 0, width: 180.5, height: 240))
        view.layoutIfNeeded()
        XCTAssertTrue(view.previewLayer.isHidden)
        view.format = try format()
        for _ in 0..<3 {
            view.setNeedsLayout(); view.layoutIfNeeded()
            XCTAssertFalse(view.previewLayer.isHidden)
            XCTAssertEqual(view.previewLayer.frame.height, 425, accuracy: 1e-10)
            XCTAssertEqual(view.previewLayer.frame.width, 318.75, accuracy: 1e-10)
            XCTAssertNotNil(view.layer.mask)
        }
        view.format = nil
        view.setNeedsLayout(); view.layoutIfNeeded()
        XCTAssertTrue(view.previewLayer.isHidden)
    }
    func testUnknownOrInsufficientFOVNeverUsesWrongAspectFillFallback() throws {
        XCTAssertNil(CameraPreviewFormat(horizontalFieldOfViewDegrees: 0, formatWidth: 640, formatHeight: 480,
            outputWidth: 640, outputHeight: 480, zoomFactor: 1))
        let view = CameraPreview.PreviewView(frame: CGRect(x: 0, y: 0, width: 180.5, height: 240))
        view.format = try format(fov: 30)
        view.setNeedsLayout(); view.layoutIfNeeded()
        XCTAssertTrue(view.previewLayer.isHidden)
    }
    func testZoomAndOutputAspectStillAffectMatching() throws {
        let bounds = CGRect(x: 0, y: 0, width: 180.5, height: 240)
        let zoomed = try XCTUnwrap(PreviewFraming.imageFrame(in: bounds, format: format(zoom: 2)))
        XCTAssertEqual(zoomed.height, 212.5, accuracy: 1e-10)
        let wide = try XCTUnwrap(PreviewFraming.imageFrame(in: bounds, format: format(outputWidth: 1920, outputHeight: 1080)))
        XCTAssertEqual(wide.width, 239.0625, accuracy: 1e-10)
    }
}
