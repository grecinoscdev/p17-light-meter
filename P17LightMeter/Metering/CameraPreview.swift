import AVFoundation
import SwiftUI

/// The only boundary that translates view coordinates into camera coordinates.
/// AVFoundation accounts for portrait rotation and the aspect-fill crop.
struct CameraPreview: UIViewRepresentable {
    let format: CameraPreviewFormat?
    let orientation: GuideOrientation
    let camera: CameraLightMeter
    let centerResetID: Int
    let allowsMetering: Bool

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        camera.attachPreview(to: view.previewLayer)
        view.addGestureRecognizer(UITapGestureRecognizer(target: view, action: #selector(PreviewView.tapped(_:))))
        return view
    }
    func updateUIView(_ view: PreviewView, context: Context) {
        view.format = format
        view.orientation = orientation
        view.setNeedsLayout()
        view.resetReticleIfNeeded(id: centerResetID)
        view.onTap = allowsMetering ? { point in
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
        var orientation: GuideOrientation = .portrait
        private let imageMask = CAShapeLayer()
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
            previewLayer.videoGravity = .resizeAspectFill
            layer.addSublayer(previewLayer)
            layer.mask = imageMask
            previewLayer.isHidden = true
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
            // Never show the old aspect-fill fallback while awaiting metadata.
            // The first visible frame already has the PENTAX-matched image scale.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if let format, let imageFrame = PreviewFraming.imageFrame(in: bounds, format: format, orientation: orientation) {
                previewLayer.frame = imageFrame
                previewLayer.isHidden = false
                let visibleImage = imageFrame.intersection(bounds)
                imageMask.path = UIBezierPath(roundedRect: visibleImage, cornerRadius: 16).cgPath
            } else {
                previewLayer.isHidden = true
                imageMask.path = UIBezierPath(roundedRect: bounds, cornerRadius: 16).cgPath
            }
            CATransaction.commit()
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
                if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .off }
            }
        }
        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard let onTap, !previewLayer.isHidden else { return }
            let location = recognizer.location(in: self)
            // AVFoundation accounts for portrait rotation and the aspect-fill
            // crop when translating the tap into a device point.
            let layerPoint = previewLayer.convert(location, from: layer)
            guard previewLayer.bounds.contains(layerPoint) else { return }
            onTap(previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint))
            reticle.frame = CGRect(x: location.x - 20, y: location.y - 20, width: 40, height: 40)
            reticle.isHidden = false
        }
    }
}
