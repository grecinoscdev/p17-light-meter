import AVFoundation
import SwiftUI

/// The only boundary that translates view coordinates into camera coordinates.
/// AVFoundation accounts for portrait rotation and the aspect-fill crop.
struct CameraPreview: UIViewRepresentable {
    let camera: CameraLightMeter
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
            previewLayer.frame = bounds
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard let onTap else { return }
            let location = recognizer.location(in: self)
            onTap(previewLayer.captureDevicePointConverted(fromLayerPoint: location))
            reticle.frame = CGRect(x: location.x - 20, y: location.y - 20, width: 40, height: 40)
            reticle.isHidden = false
        }
    }
}
