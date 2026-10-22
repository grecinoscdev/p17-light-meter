import XCTest
@testable import P17LightMeter

final class PreviewFramingTests: XCTestCase {
    private func format(fov: Double = 90, width: Double = 640, height: Double = 480,
                        outputWidth: Double = 640, outputHeight: Double = 480,
                        zoom: Double = 1) throws -> CameraPreviewFormat {
        try XCTUnwrap(CameraPreviewFormat(horizontalFieldOfViewDegrees: fov,
            formatWidth: width, formatHeight: height,
            outputWidth: outputWidth, outputHeight: outputHeight, zoomFactor: zoom))
    }

    func testGuideKeepsExistingSizeAndCenter() {
        let guide = CompositionGuide.frame(in: CGRect(x: 0, y: 0, width: 360, height: 240))
        XCTAssertEqual(guide.width, 144.5)
        XCTAssertEqual(guide.height, 204)
        XCTAssertEqual(guide.midX, 180)
        XCTAssertEqual(guide.midY, 120)
    }

    func testPortraitImageMatchesBothFilmAxes() throws {
        // At 90 degrees, tan(half-angle) = 1. The full portrait image height
        // must be 204 / (24 / 50) = 425 points; its width is 425 * 3/4.
        let bounds = CGRect(x: 0, y: 0, width: 360, height: 240)
        let image = try XCTUnwrap(PreviewFraming.imageFrame(in: bounds, format: format()))
        XCTAssertEqual(image.height, 425, accuracy: 1e-10)
        XCTAssertEqual(image.width, 318.75, accuracy: 1e-10)
        XCTAssertEqual(image.midX, bounds.midX)
        XCTAssertEqual(image.midY, bounds.midY)
        let guide = CompositionGuide.frame(in: bounds)
        XCTAssertEqual(guide.height / image.height, 0.48, accuracy: 1e-12)
        XCTAssertEqual(guide.width / image.width * 0.75, 0.34, accuracy: 1e-12)
    }

    func testWiderPanelDoesNotMagnifyGuideImage() throws {
        // Regression: aspect-filling the panel magnified the portrait image
        // more on wider screens, giving the guide an inconsistent optical FOV.
        for width in [280.0, 360, 430] {
            let image = try XCTUnwrap(PreviewFraming.imageFrame(
                in: CGRect(x: 0, y: 0, width: width, height: 240), format: format()))
            XCTAssertEqual(image.height, 425, accuracy: 1e-10)
            XCTAssertEqual(image.midX, width / 2)
        }
    }

    func testOutputCropAndZoomAreIncluded() throws {
        let bounds = CGRect(x: 0, y: 0, width: 360, height: 240)
        // 16:9 to 4:3 retains three quarters of the horizontal tangent extent.
        let cropped = try XCTUnwrap(PreviewFraming.imageFrame(in: bounds,
            format: format(width: 1920, height: 1080)))
        XCTAssertEqual(cropped.height, 318.75, accuracy: 1e-10)
        let zoomed = try XCTUnwrap(PreviewFraming.imageFrame(in: bounds, format: format(zoom: 2)))
        XCTAssertEqual(zoomed.height, 212.5, accuracy: 1e-10)
        let wide = try XCTUnwrap(PreviewFraming.imageFrame(in: bounds,
            format: format(outputWidth: 1920, outputHeight: 1080)))
        XCTAssertEqual(wide.height, 425, accuracy: 1e-10)
        XCTAssertEqual(wide.width, 239.0625, accuracy: 1e-10)
    }

    func testInvalidAndInsufficientFieldOfViewUseFallback() throws {
        for fov in [0, -1, 180, Double.nan, .infinity] {
            XCTAssertNil(CameraPreviewFormat(horizontalFieldOfViewDegrees: fov,
                formatWidth: 640, formatHeight: 480, outputWidth: 640, outputHeight: 480, zoomFactor: 1))
        }
        XCTAssertNil(CameraPreviewFormat(horizontalFieldOfViewDegrees: 90,
            formatWidth: 0, formatHeight: 480, outputWidth: 640, outputHeight: 480, zoomFactor: 1))
        XCTAssertNil(PreviewFraming.imageFrame(in: .zero, format: try format()))
        XCTAssertNil(PreviewFraming.imageFrame(in: CGRect(x: 0, y: 0, width: 360, height: 240),
            format: try format(fov: 30)))
    }
}
