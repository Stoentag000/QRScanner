import SwiftUI
import AVFoundation

// MARK: - Camera Preview (AVCaptureSession → SwiftUI)

struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(previewLayer)

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let previewLayer = nsView.layer?.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = nsView.bounds
        }
    }
}
