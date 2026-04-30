import SwiftUI
import AVFoundation
import AudioToolbox

// MARK: - Environment Key for Close Action

struct CloseWindowKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var closeWindow: () -> Void {
        get { self[CloseWindowKey.self] }
        set { self[CloseWindowKey.self] = newValue }
    }
}

// MARK: - Scanner View

struct ScannerView: View {
    @ObservedObject var cameraScanner: CameraScanner
    @ObservedObject var history: ScanHistory
    @ObservedObject var settings: AppSettings
    var initialCameraMode: Bool = true
    var onModeChange: (Bool) -> Void = { _ in }
    var onShowHistory: () -> Void = {}
    var onShowSettings: () -> Void = {}
    @State private var detectedCode: String?
    @State private var copied = false
    @State private var pulse = false
    @State private var uploadedImage: NSImage?
    @State private var imageCodes: [String] = []
    @State private var showFilePicker = false
    @State private var isCameraMode: Bool = true
    @Environment(\.closeWindow) var closeWindow

    var body: some View {
        ZStack {
            // Solid background
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.background)

            VStack(spacing: 0) {
                // Header
                header

                // Mode toggle buttons
                modeToggle
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                // Content area (camera or image)
                if isCameraMode {
                    cameraArea
                } else {
                    imageArea
                }

                // Status bar
                statusBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                    .padding(.top, 12)
            }

            // Global drag overlay — only in camera mode (image mode has its own)
            if isDragging && isCameraMode {
                dragHighlight
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.15), value: isDragging)
            }
        }
        .frame(width: 380, height: isCameraMode ? 500 : 460)
        .onAppear {
            if !initialCameraMode {
                isCameraMode = false
                cameraScanner.stopRunning()
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers: providers)
        }
        .onChange(of: cameraScanner.lastDetectedCode) { _, newValue in
            guard let code = newValue else { return }
            showDetectedCode(code)
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.png, .jpeg, .tiff, .bmp, .gif, .webP],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    // MARK: - Mode Toggle

    private var modeToggle: some View {
        HStack(spacing: 0) {
            modeButton("摄像头", icon: "camera.fill", active: isCameraMode) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCameraMode = true
                    onModeChange(true)
                    uploadedImage = nil
                    imageCodes = []
                    detectedCode = nil
                    cameraScanner.startRunning()
                }
            }

            modeButton("上传图片", icon: "photo.on.rectangle", active: !isCameraMode) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCameraMode = false
                    onModeChange(false)
                    cameraScanner.stopRunning()
                    showFilePicker = true
                }
            }
        }
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func modeButton(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
            .foregroundStyle(active ? .primary : .secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                active ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Camera Area

    private var cameraArea: some View {
        ZStack {
            // Camera feed
            CameraPreviewView(session: cameraScanner.captureSession)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(scanFrame)

            // Detected code popup
            if let code = detectedCode {
                codePopup(code)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Drag & Drop

    @State private var isDragging = false

    // MARK: - Image Area

    private var imageArea: some View {
        ZStack {
            VStack(spacing: 0) {
                if isDragging {
                    // During drag: show consistent dragHighlight in both states
                    dragHighlight
                } else if let image = uploadedImage {
                    // Show uploaded image with results
                    VStack(spacing: 10) {
                        // Image preview
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(.separator, lineWidth: 0.5)
                            )

                        // Detected codes list
                        if !imageCodes.isEmpty {
                            VStack(spacing: 6) {
                                ForEach(imageCodes, id: \.self) { code in
                                    codeResultRow(code)
                                }
                            }
                        } else {
                            VStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.secondary)
                                Text("未检测到二维码")
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 20)
                        }

                        // Re-upload button
                        Button(action: { showFilePicker = true }) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10, weight: .medium))
                                Text("重新选择")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                } else {
                    dropZone
                }
            }

            // Detected code popup overlay
            if let code = detectedCode {
                codePopup(code)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
    }

    // MARK: - Drag Highlight (replaces dropZone during drag)

    private var dragHighlight: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor.opacity(0.8))

            VStack(spacing: 4) {
                Text("放开以识别图片")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
                Text("支持 PNG / JPG / TIFF / GIF")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(Color.accentColor.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 2, antialiased: true)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
    }



    // MARK: - Drop Zone

    private var dropZone: some View {
        Button(action: { showFilePicker = true }) {
            VStack(spacing: 14) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)

                VStack(spacing: 4) {
                    Text("点击或拖拽图片到此处")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("支持 PNG / JPG / TIFF / GIF")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]),
                        antialiased: true
                    )
                    .foregroundStyle(.secondary)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Code Result Row

    private func codeResultRow(_ code: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "qrcode")
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor.opacity(0.7))

            Text(code)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(2)
                .foregroundStyle(.primary)

            Spacer()

            Button(action: {
                copyToClipboard(code)
            }) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }

    // MARK: - Helpers

    private func showDetectedCode(_ code: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            detectedCode = code
            copied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { copied = false }
        }
    }

    private func copyToClipboard(_ code: String) {
        if settings.autoCopy {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
        }
        withAnimation {
            detectedCode = code
            copied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copied = false }
        }
    }

    // MARK: - Unified Image Import

    /// Single entry point: switch to image mode, load the file, detect codes.
    private func importImage(from url: URL) {
        if isCameraMode {
            isCameraMode = false
            cameraScanner.stopRunning()
        }

        // Try security-scoped access (needed in sandbox), but don't bail out
        // if it fails — the URL might still be readable (e.g. non-sandboxed,
        // or the drag source already granted access).
        let hasSecurityAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityAccess { url.stopAccessingSecurityScopedResource() }
        }

        guard let image = NSImage(contentsOf: url) else {
            print("[QRScanner] Could not load image from URL: \(url)")
            return
        }

        uploadedImage = image
        imageCodes = ImageCodeDetector.detectCodes(in: image)
        for code in imageCodes {
            history.add(code, source: .image)
        }
        if let first = imageCodes.first {
            showDetectedCode(first)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { detectedCode = nil; copied = false }
            }
        }
        if !imageCodes.isEmpty && settings.soundEnabled {
            SoundPlayer.shared.play()
        }
    }

    /// fileImporter callback — extracts URL and forwards to importImage.
    private func handleFileImport(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result, let url = urls.first {
            importImage(from: url)
        }
    }

    /// onDrop callback — parses NSItemProvider, forwards to importImage.
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        // Try NSFilePromiseReceiver first (sandboxed apps, Finder, Photos, etc.)
        if provider.hasItemConformingToTypeIdentifier("public.file-url") {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                if let error = error {
                    print("[QRScanner] loadItem error: \(error)")
                    return
                }

                var url: URL?

                // NSItemProvider may return NSURL directly (common for file drags)
                if let nsURL = item as? NSURL {
                    url = nsURL as URL
                }
                // Or it may return raw Data (bookmark data)
                else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                }
                // Or a URL string
                else if let urlString = item as? String {
                    url = URL(string: urlString)
                }

                guard let resolvedURL = url else {
                    print("[QRScanner] Could not resolve dropped item to URL: \(String(describing: item))")
                    return
                }

                DispatchQueue.main.async {
                    self.importImage(from: resolvedURL)
                }
            }
            return true
        }

        return false
    }

    private var header: some View {
        HStack(spacing: 8) {
            // Settings gear button
            Button(action: { onShowSettings() }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(.quaternary, in: Circle())
            }
            .buttonStyle(.plain)

            Text("QRScanner")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer()

            // History button
            Button(action: { onShowHistory() }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(.quaternary, in: Circle())

                    if !history.entries.isEmpty {
                        Text("\(min(history.entries.count, 99))")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.accentColor, in: Capsule())
                            .offset(x: 6, y: -4)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Scan Frame Overlay

    private var scanFrame: some View {
        ZStack {
            // Corner brackets
            let s: CGFloat = 24
            let t: CGFloat = 3
            let c = Color.accentColor.opacity(0.5)

            VStack {
                HStack {
                    c.frame(width: s, height: t)
                    Spacer()
                    c.frame(width: s, height: t)
                }
                Spacer()
                HStack {
                    c.frame(width: s, height: t)
                    Spacer()
                    c.frame(width: s, height: t)
                }
            }
            .padding(24)

            VStack {
                Spacer()
                HStack { Spacer() }
            }

            // Vertical corners
            VStack {
                HStack {
                    c.frame(width: t, height: s)
                    Spacer()
                    c.frame(width: t, height: s)
                }
                Spacer()
                HStack {
                    c.frame(width: t, height: s)
                    Spacer()
                    c.frame(width: t, height: s)
                }
            }
            .padding(24)

            // Scanning line animation
            scanLine
        }
    }

    // MARK: - Animated Scan Line

    @State private var scanLineY: CGFloat = 0

    private var scanLine: some View {
        GeometryReader { geo in
            let minY: CGFloat = 30
            let maxY = geo.size.height - 30

            LinearGradient(
                colors: [.clear, Color.accentColor.opacity(0.8), Color.accentColor, Color.accentColor.opacity(0.8), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 2)
            .shadow(color: Color.accentColor.opacity(0.5), radius: 6)
            .offset(y: scanLineY)
            .onAppear {
                withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: true)) {
                    scanLineY = maxY - minY
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Code Popup

    private func codePopup(_ code: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 28))
                .foregroundStyle(.green.gradient)

            Text(code)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)

            if copied {
                Text("已复制到剪贴板")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 6) {
            // Live indicator
            Circle()
                .fill(.red.gradient)
                .frame(width: 6, height: 6)
                .shadow(color: .red.opacity(0.5), radius: 3)
                .opacity(pulse ? 1 : 0.4)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }

            Text("前置摄像头 · 扫描中")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer()

            Text("⌘Q 退出")
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(.tertiary)
        }
    }
}

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


