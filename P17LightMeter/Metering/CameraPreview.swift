import AVFoundation
import SwiftUI

/// The only boundary that translates view coordinates into camera coordinates.
/// AVFoundation accounts for portrait rotation and the aspect-fill crop.
struct CameraPreview: UIViewRepresentable {
    let camera: CameraLightMeter
    let format: CameraPreviewFormat?
    let centerResetID: Int
    let allowsMetering: Bool
    let onMeteringPointChanged: () -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        camera.attachPreview(to: view.previewLayer)
        view.previewLayer.videoGravity = .resizeAspectFill
        view.addGestureRecognizer(UITapGestureRecognizer(target: view, action: #selector(PreviewView.tapped(_:))))
        return view
    }
    func updateUIView(_ view: PreviewView, context: Context) {
        view.format = format
        view.setNeedsLayout()
        view.resetReticleIfNeeded(id: centerResetID)
        view.onTap = allowsMetering ? { point in
            onMeteringPointChanged()
            camera.meter(at: point)
        } : nil
    }
    static func dismantleUIView(_ view: PreviewView, coordinator: ()) {
        view.previewLayer.session = nil
        view.onTap = nil
    }

    final class PreviewView: UIView {
        let previewLayer = AVCaptureVideoPreviewLayer()
        var format: CameraPreviewFormat?
        var onTap: ((CGPoint) -> Void)?
        private let reticle = UIView()
        private var centerResetID = -1
        func resetReticleIfNeeded(id: Int) {
            guard centerResetID != id else { return }
            centerResetID = id
            reticle.isHidden = true
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            layer.addSublayer(previewLayer)
            clipsToBounds = true
            reticle.layer.borderWidth = 2
            reticle.layer.borderColor = UIColor.white.cgColor
            reticle.layer.cornerRadius = 20
            reticle.isUserInteractionEnabled = false
            reticle.isHidden = true
            addSubview(reticle)
            isAccessibilityElement = true
            accessibilityLabel = "Camera preview. Use Center metering to meter the center with VoiceOver."
        }
        required init?(coder: NSCoder) { nil }
        override func layoutSubviews() {
            super.layoutSubviews()
            // Only image scale changes; the panel and guide retain their existing layout.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if let format, let imageFrame = PreviewFraming.imageFrame(in: bounds, format: format) {
                previewLayer.frame = imageFrame
            } else {
                previewLayer.frame = bounds
            }
            CATransaction.commit()
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
                if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .off }
            }
        }
        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard let onTap else { return }
            let location = recognizer.location(in: self)
            // Layer size/origin now differ from the view. Convert locally before
            // AVFoundation applies portrait rotation and its own image mapping.
            let layerPoint = previewLayer.convert(location, from: layer)
            guard previewLayer.bounds.contains(layerPoint) else { return }
            onTap(previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint))
            reticle.frame = CGRect(x: location.x - 20, y: location.y - 20, width: 40, height: 40)
            reticle.isHidden = false
        }
    }
}
