import AVFoundation
import Vision
import Foundation
import Combine

final class CameraScanner: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let captureSession = AVCaptureSession()
    @Published var lastDetectedCode: String?

    private let processingQueue = DispatchQueue(label: "scanner.queue", qos: .userInteractive)
    private var isProcessing = false
    private var scanningEnabled = false
    private var sessionStarted = false
    private weak var videoOutput: AVCaptureVideoDataOutput?

    override init() {
        super.init()
        configureSession()
    }

    private func configureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video,
                                                    position: .front),
              let input = try? AVCaptureDeviceInput(device: camera),
              captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true

        guard captureSession.canAddOutput(output) else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addOutput(output)
        output.setSampleBufferDelegate(self, queue: processingQueue)
        self.videoOutput = output

        captureSession.commitConfiguration()
    }

    func startRunning() {
        if !sessionStarted {
            sessionStarted = true
            // Must be called from main thread — AVCaptureSession's internal
            // collections are not thread-safe; dispatching to a global queue
            // causes "mutated while being enumerated" when start/stop race.
            captureSession.startRunning()
        }
        scanningEnabled = true
        isProcessing = false
    }

    func stopRunning() {
        scanningEnabled = false
        if sessionStarted {
            sessionStarted = false
            captureSession.stopRunning()
        }
        // Wait for any in-flight Vision request to finish so that
        // isProcessing is guaranteed to be false when we're done.
        // captureOutput guards on scanningEnabled, so the callback
        // will exit quickly via its defer block.
        processingQueue.sync {
            isProcessing = false
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard scanningEnabled, !isProcessing else { return }
        isProcessing = true

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            isProcessing = false
            return
        }

        let request = VNDetectBarcodesRequest { [weak self] request, error in
            defer { self?.isProcessing = false }

            guard let self, self.scanningEnabled, error == nil,
                  let results = request.results as? [VNBarcodeObservation],
                  let firstCode = results.first?.payloadStringValue else {
                return
            }

            if firstCode != self.lastDetectedCode {
                DispatchQueue.main.async {
                    // Re-check after dispatch in case stopRunning was called
                    guard self.scanningEnabled else { return }
                    self.lastDetectedCode = firstCode
                }
            }
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        try? handler.perform([request])
    }
}
