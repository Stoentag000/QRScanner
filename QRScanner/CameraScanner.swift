import AVFoundation
import Vision
import Foundation
import Combine

// MARK: - Camera Device Model

struct CameraDevice: Identifiable, Hashable {
    let id: String          // AVCaptureDevice uniqueID
    let name: String        // Localized name
    let isContinuityCamera: Bool
    let isExternal: Bool

    var icon: String {
        if isContinuityCamera { return "iphone" }
        if isExternal { return "video" }
        return "web.camera"     // built-in
    }
}

final class CameraScanner: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let captureSession = AVCaptureSession()
    @Published var lastDetectedCode: String?
    @Published var availableCameras: [CameraDevice] = []
    @Published var currentCameraID: String?

    private let processingQueue = DispatchQueue(label: "scanner.queue", qos: .userInteractive)
    private var isProcessing = false
    private var scanningEnabled = false
    private var sessionStarted = false
    private weak var videoOutput: AVCaptureVideoDataOutput?

    override init() {
        super.init()
        refreshAvailableCameras()
    }

    // MARK: - Camera Discovery

    /// Scan the system for all video capture devices, including Continuity Camera (iPhone).
    func refreshAvailableCameras() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .external,               // USB / Thunderbolt webcams
                .continuityCamera,       // iPhone via Continuity Camera (macOS 13+)
            ],
            mediaType: .video,
            position: .unspecified
        )

        var seen = Set<String>()
        var cameras: [CameraDevice] = []

        for device in discovery.devices {
            // Deduplicate (some devices appear in multiple discovery types)
            guard !seen.contains(device.uniqueID) else { continue }
            seen.insert(device.uniqueID)

            let isCC = device.deviceType == .continuityCamera
            let isExt = device.deviceType == .external || device.deviceType == .continuityCamera

            cameras.append(CameraDevice(
                id: device.uniqueID,
                name: device.localizedName,
                isContinuityCamera: isCC,
                isExternal: isExt
            ))
        }

        DispatchQueue.main.async {
            self.availableCameras = cameras
        }
    }

    /// Resolve a AVCaptureDevice from a camera ID string.
    /// Falls back to the best available camera if the ID is invalid or "auto".
    private func resolveDevice(for cameraID: String) -> AVCaptureDevice? {
        if cameraID != AppSettings.autoCameraID {
            if let device = AVCaptureDevice(uniqueID: cameraID) {
                return device
            }
        }

        // Auto-pick: prefer built-in front → built-in back → external → continuity camera
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )

        let preferred: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external, .continuityCamera]
        for type in preferred {
            if let device = discovery.devices.first(where: { $0.deviceType == type }) {
                return device
            }
        }
        return discovery.devices.first
    }

    // MARK: - Session Configuration

    /// (Re)configure the capture session for the given camera ID.
    /// If the session is already running, it will be reconfigured live.
    func configure(with cameraID: String) {
        let wasRunning = sessionStarted

        if wasRunning {
            scanningEnabled = false
            captureSession.stopRunning()
            sessionStarted = false
        }

        // Remove existing inputs
        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }

        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high

        guard let device = resolveDevice(for: cameraID),
              let input = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            return
        }

        captureSession.addInput(input)

        // Add output if not already present
        if captureSession.outputs.isEmpty {
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
        }

        captureSession.commitConfiguration()

        DispatchQueue.main.async {
            self.currentCameraID = device.uniqueID
        }

        if wasRunning {
            sessionStarted = true
            captureSession.startRunning()
            scanningEnabled = true
            isProcessing = false
        }
    }

    // MARK: - Start / Stop

    func startRunning(cameraID: String? = nil) {
        let targetID = cameraID ?? currentCameraID ?? AppSettings.autoCameraID

        // If switching cameras or first run, (re)configure
        if currentCameraID != targetID || captureSession.inputs.isEmpty {
            configure(with: targetID)
        }

        if !sessionStarted {
            sessionStarted = true
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
                    guard self.scanningEnabled else { return }
                    self.lastDetectedCode = firstCode
                }
            }
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        try? handler.perform([request])
    }
}
