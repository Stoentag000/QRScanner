import AVFoundation
import Vision
import Foundation
import Combine

struct CameraDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let isContinuityCamera: Bool
    let isExternal: Bool

    var icon: String {
        if isContinuityCamera { return "iphone" }
        if isExternal { return "video" }
        return "web.camera"
    }
}

/// Owns all AVCaptureSession work on `sessionQueue`.
/// Vision processing is performed on that same serial queue, so frames cannot race each other.
final class CameraScanner: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let captureSession = AVCaptureSession()
    @Published var lastDetectedCode: String?
    @Published var availableCameras: [CameraDevice] = []
    @Published var currentCameraID: String?
    @Published var cameraError: String?

    private let sessionQueue = DispatchQueue(label: "com.qrscanner.camera-session", qos: .userInitiated)
    private var scanningEnabled = false
    private var sessionStarted = false
    private var lastVisibleCode: String?
    private var deviceObservers: [NSObjectProtocol] = []

    override init() {
        super.init()
        refreshAvailableCameras()
        observeCameraChanges()
    }

    deinit {
        deviceObservers.forEach(NotificationCenter.default.removeObserver)
    }

    static func discoverCameras() -> [CameraDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )

        var seen = Set<String>()
        return discovery.devices.compactMap { device in
            guard seen.insert(device.uniqueID).inserted else { return nil }
            return CameraDevice(
                id: device.uniqueID,
                name: device.localizedName,
                isContinuityCamera: device.deviceType == .continuityCamera,
                isExternal: device.deviceType == .external || device.deviceType == .continuityCamera
            )
        }
    }

    func refreshAvailableCameras() {
        let cameras = Self.discoverCameras()
        DispatchQueue.main.async {
            self.availableCameras = cameras
        }
    }

    func startRunning(cameraID: String? = nil) {
        let targetID = cameraID ?? currentCameraID ?? AppSettings.autoCameraID
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.publishError("未获得摄像头权限。请在“系统设置 > 隐私与安全性 > 摄像头”中允许 QRScanner 使用摄像头。")
                return
            }
            self.sessionQueue.async {
                self.configureAndStart(cameraID: targetID)
            }
        }
    }

    func stopRunning() {
        sessionQueue.async {
            self.scanningEnabled = false
            self.lastVisibleCode = nil
            if self.sessionStarted {
                self.captureSession.stopRunning()
                self.sessionStarted = false
            }
            self.publishDetectedCode(nil)
        }
    }

    private func configureAndStart(cameraID: String) {
        captureSession.beginConfiguration()

        if sessionStarted {
            captureSession.stopRunning()
            sessionStarted = false
        }
        captureSession.inputs.forEach(captureSession.removeInput)
        captureSession.outputs.forEach(captureSession.removeOutput)
        captureSession.sessionPreset = .high

        guard let device = resolveDevice(for: cameraID) else {
            captureSession.commitConfiguration()
            scanningEnabled = false
            publishError("未检测到可用摄像头。")
            return
        }
        guard let input = try? AVCaptureDeviceInput(device: device), captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            scanningEnabled = false
            publishError("无法打开“\(device.localizedName)”。")
            return
        }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        guard captureSession.canAddOutput(output) else {
            captureSession.commitConfiguration()
            scanningEnabled = false
            publishError("无法配置摄像头输出。")
            return
        }

        captureSession.addInput(input)
        captureSession.addOutput(output)
        output.setSampleBufferDelegate(self, queue: sessionQueue)

        captureSession.commitConfiguration()
        lastVisibleCode = nil
        scanningEnabled = true
        sessionStarted = true
        captureSession.startRunning()
        DispatchQueue.main.async {
            self.currentCameraID = device.uniqueID
            self.cameraError = nil
            self.lastDetectedCode = nil
        }
    }

    private func resolveDevice(for cameraID: String) -> AVCaptureDevice? {
        if cameraID != AppSettings.autoCameraID, let device = AVCaptureDevice(uniqueID: cameraID) {
            return device
        }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        let preferred: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external, .continuityCamera]
        return preferred.compactMap { type in discovery.devices.first { $0.deviceType == type } }.first
            ?? discovery.devices.first
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard scanningEnabled, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let orientation: CGImagePropertyOrientation
        switch connection.videoRotationAngle {
        case 315..<360, 0..<45: orientation = .up
        case 45..<135: orientation = .right
        case 135..<225: orientation = .down
        case 225..<315: orientation = .left
        default: orientation = .up
        }

        let request = VNDetectBarcodesRequest()
        request.symbologies = ImageCodeDetector.supportedSymbologies
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])

        guard (try? handler.perform([request])) != nil else { return }
        let code = request.results?.compactMap(\.payloadStringValue).first

        // Clearing the visible value when the code leaves the frame allows the same code to be scanned again.
        guard code != lastVisibleCode else { return }
        lastVisibleCode = code
        publishDetectedCode(code)
    }

    private func publishDetectedCode(_ code: String?) {
        DispatchQueue.main.async {
            self.lastDetectedCode = code
        }
    }

    private func publishError(_ message: String) {
        DispatchQueue.main.async {
            self.cameraError = message
        }
    }

    private func observeCameraChanges() {
        let center = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            deviceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshAvailableCameras()
            })
        }
    }
}
