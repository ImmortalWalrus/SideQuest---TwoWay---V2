import SwiftUI
import UIKit
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.previewLayer.session = session
    }
}

struct PreviewLayerView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewLayerHostView {
        let view = PreviewLayerHostView()
        view.setPreviewLayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewLayerHostView, context: Context) {
        uiView.setPreviewLayer(previewLayer)
    }
}

final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        previewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        fatalError()
    }
}

final class PreviewLayerHostView: UIView {
    private var currentPreviewLayer: AVCaptureVideoPreviewLayer?

    func setPreviewLayer(_ previewLayer: AVCaptureVideoPreviewLayer) {
        guard currentPreviewLayer !== previewLayer else {
            previewLayer.frame = bounds
            return
        }

        currentPreviewLayer?.removeFromSuperlayer()
        currentPreviewLayer = previewLayer
        layer.addSublayer(previewLayer)
        previewLayer.frame = bounds
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        currentPreviewLayer?.frame = bounds
    }
}
