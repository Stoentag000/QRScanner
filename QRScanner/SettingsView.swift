import SwiftUI
import AppKit
import AVFoundation

// MARK: - Settings Categories

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "通用"
    case scanning = "扫描"
    case camera = "摄像头"
    case about = "关于"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .scanning: return "qrcode.viewfinder"
        case .camera: return "camera"
        case .about: return "info.circle"
        }
    }

    var title: String {
        switch self {
        case .general: return "通用"
        case .scanning: return "扫描与识别"
        case .camera: return "摄像头"
        case .about: return "关于 QRScanner"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "外观与启动行为"
        case .scanning: return "识别后的处理方式"
        case .camera: return "图像来源与设备"
        case .about: return "版本与支持的码制"
        }
    }

    var accentColor: Color {
        switch self {
        case .general: return .blue
        case .scanning: return .purple
        case .camera: return .green
        case .about: return .orange
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var selectedCategory: SettingsCategory = .general
    @State private var settingsCameras: [CameraDevice] = []

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(settings.theme.colorScheme)
        .onAppear(perform: refreshCameras)
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)) { _ in
            refreshCameras()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)) { _ in
            refreshCameras()
        }
    }

    // MARK: - Sidebar
    // Everything lives inside a single List so the system-provided sidebar
    // material extends seamlessly under the traffic-light buttons, matching
    // the macOS 26 Settings layout.
    //
    // Per HIG: sidebar icons use the system accent color by default;
    // labels are concise without subtitles; no critical info at the bottom.

    private var sidebar: some View {
        List(selection: $selectedCategory) {
            // App header — minimal, provides context since window title is hidden
            Section {
                HStack(spacing: 10) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 26, height: 26)
                    Text("QRScanner")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            // Categories — standard Label, system handles icon accent color
            Section {
                ForEach(SettingsCategory.allCases) { category in
                    Label(category.rawValue, systemImage: category.icon)
                        .tag(category)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Detail View

    private var detailView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                pageHeader

                Group {
                    switch selectedCategory {
                    case .general: generalPage
                    case .scanning: scanningPage
                    case .camera: cameraPage
                    case .about: aboutPage
                    }
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.top, 38)
            .padding(.bottom, 48)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeInOut(duration: 0.2), value: selectedCategory)
    }

    private var pageHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [selectedCategory.accentColor.opacity(0.18),
                                     selectedCategory.accentColor.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                Image(systemName: selectedCategory.icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(selectedCategory.accentColor)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selectedCategory.accentColor.opacity(0.15), lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(selectedCategory.title)
                    .font(.system(size: 24, weight: .bold))
                Text(selectedCategory.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - General Page

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsSection(
                title: "外观",
                subtitle: "主题会立即应用到主界面与设置窗口。"
            ) {
                themeRow
            }

            settingsSection(
                title: "登录与启动",
                subtitle: "管理 QRScanner 在系统中的启动行为。"
            ) {
                toggleRow(
                    icon: "power",
                    color: .green,
                    title: "登录时打开",
                    subtitle: "登录 macOS 后在菜单栏中自动启动 QRScanner。",
                    isOn: $settings.launchAtLoginEnabled
                )
            }
        }
    }

    private var themeRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                settingsIcon("circle.lefthalf.filled", color: .indigo)
                VStack(alignment: .leading, spacing: 2) {
                    Text("界面主题")
                        .font(.system(size: 13, weight: .medium))
                    Text("使用系统外观，或始终保持浅色或深色。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 16)
            }

            HStack(spacing: 10) {
                ForEach(AppTheme.allCases) { theme in
                    themePreviewButton(theme)
                }
            }
        }
        .padding(16)
    }

    private func themePreviewButton(_ theme: AppTheme) -> some View {
        let isSelected = settings.theme == theme
        let previewColors: [Color] = {
            switch theme {
            case .system: return [Color(nsColor: .controlBackgroundColor), Color(nsColor: .windowBackgroundColor)]
            case .light: return [Color(white: 0.95), Color(white: 0.88)]
            case .dark: return [Color(white: 0.18), Color(white: 0.12)]
            }
        }()

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                settings.theme = theme
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: previewColors,
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 56)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(
                                    isSelected ? Color.accentColor : Color.primary.opacity(0.1),
                                    lineWidth: isSelected ? 2 : 0.5
                                )
                        )

                    HStack(spacing: 4) {
                        Circle()
                            .fill(theme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.5))
                            .frame(width: 6, height: 6)
                        Circle()
                            .fill(theme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.3))
                            .frame(width: 6, height: 6)
                        Circle()
                            .fill(theme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.15))
                            .frame(width: 6, height: 6)
                    }
                }

                HStack(spacing: 4) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(theme.rawValue)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Scanning Page

    private var scanningPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsSection(
                title: "识别完成后",
                subtitle: "这些选项同时适用于摄像头扫描与图片识别。"
            ) {
                VStack(spacing: 0) {
                    toggleRow(
                        icon: "speaker.wave.2.fill",
                        color: .blue,
                        title: "播放提示音",
                        subtitle: "成功识别二维码或条形码时播放声音。",
                        isOn: $settings.soundEnabled
                    )
                    rowDivider
                    toggleRow(
                        icon: "doc.on.clipboard.fill",
                        color: .orange,
                        title: "自动复制结果",
                        subtitle: "识别成功后立即将内容写入剪贴板。",
                        isOn: $settings.autoCopy
                    )
                    rowDivider
                    toggleRow(
                        icon: "clock.arrow.circlepath",
                        color: .purple,
                        title: "保存扫描历史",
                        subtitle: "记录最多 200 条结果；关闭后会删除已有的本地记录。",
                        isOn: $settings.historyEnabled
                    )
                }
            }

            infoBanner(
                icon: "lock.shield.fill",
                color: .blue,
                text: "扫码结果若包含敏感信息，建议关闭历史记录功能以防泄露。"
            )
        }
    }

    // MARK: - Camera Page

    private var cameraPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsSection(
                title: "默认摄像头",
                subtitle: "切换设备后，下次打开扫描器时生效。",
                action: {
                    Button(action: refreshCameras) {
                        Label("刷新", systemImage: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            ) {
                VStack(spacing: 0) {
                    cameraOptionRow(
                        id: AppSettings.autoCameraID,
                        icon: "sparkles",
                        color: .blue,
                        name: "自动选择",
                        description: "优先使用当前可用的最佳设备"
                    )

                    if settingsCameras.isEmpty {
                        rowDivider
                        emptyCameraRow
                    } else {
                        ForEach(settingsCameras) { camera in
                            rowDivider
                            cameraOptionRow(
                                id: camera.id,
                                icon: camera.icon,
                                color: camera.isContinuityCamera ? .purple : .green,
                                name: camera.name,
                                description: cameraDescription(camera)
                            )
                        }
                    }
                }
            }

            if selectedCameraIsUnavailable {
                infoBanner(
                    icon: "exclamationmark.triangle.fill",
                    color: .orange,
                    text: "此前选择的摄像头当前不可用，扫描时将临时使用其他可用设备。"
                )
            }

            infoBanner(
                icon: "iphone.gen3",
                color: .blue,
                text: "连接 iPhone 或外接摄像头后，列表会自动更新。连续互通相机要求设备登录同一 Apple 账户。"
            )
        }
    }

    private var emptyCameraRow: some View {
        HStack(spacing: 12) {
            settingsIcon("camera.fill", color: .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("未检测到摄像头")
                    .font(.system(size: 13, weight: .medium))
                Text("请连接设备后点击刷新")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
    }

    private func cameraOptionRow(
        id: String,
        icon: String,
        color: Color,
        name: String,
        description: String
    ) -> some View {
        let isSelected = settings.selectedCameraID == id

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                settings.selectedCameraID = id
            }
        } label: {
            HStack(spacing: 12) {
                settingsIcon(icon, color: color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 16)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
                    .transition(.scale.combined(with: .opacity))
            }
            .contentShape(Rectangle())
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name)，\(isSelected ? "已选择" : "未选择")")
    }

    // MARK: - About Page

    private var aboutPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            // App info card
            appInfoCard

            // Supported code types
            settingsSection(
                title: "支持的码制",
                subtitle: "摄像头扫描和图片识别均支持以下格式。"
            ) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 130), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(supportedCodeTypes, id: \.self) { codeType in
                        codeTypeBadge(codeType)
                    }
                }
                .padding(16)
            }

            // Developer info
            HStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.pink.opacity(0.7))
                Text("由 Stoentag000 开发，Xiaomi MiMo Claw 提供支持。")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
        }
    }

    private var appInfoCard: some View {
        HStack(spacing: 20) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 5) {
                Text("QRScanner")
                    .font(.system(size: 22, weight: .bold))
                HStack(spacing: 6) {
                    Text("版本 \(shortVersion)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    Text("构建 \(buildNumber)")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                Text("轻量、快速的 macOS 菜单栏扫码工具")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.1), Color.accentColor.opacity(0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.12), lineWidth: 0.5)
        }
    }

    private func codeTypeBadge(_ codeType: String) -> some View {
        let isQR = codeType.hasPrefix("QR") || codeType == "Aztec"
        return HStack(spacing: 8) {
            Image(systemName: isQR ? "qrcode" : "barcode")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            Text(codeType)
                .font(.system(size: 11, weight: .medium))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.5)
        )
    }

    // MARK: - Reusable Components

    private func settingsSection<Content: View, Action: View>(
        title: String,
        subtitle: String,
        @ViewBuilder action: () -> Action,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
                action()
            }

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.02), radius: 6, y: 2)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        settingsSection(title: title, subtitle: subtitle, action: { EmptyView() }, content: content)
    }

    private func toggleRow(
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            settingsIcon(icon, color: color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(16)
    }

    private func settingsIcon(_ name: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color.opacity(0.12))
                .frame(width: 32, height: 32)
            Image(systemName: name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
        }
    }

    private var rowDivider: some View {
        Divider()
            .opacity(0.5)
            .padding(.leading, 60)
    }

    private func infoBanner(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 18)

            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            color.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(color.opacity(0.12), lineWidth: 0.5)
        )
    }

    // MARK: - Helpers

    private var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private var selectedCameraIsUnavailable: Bool {
        settings.selectedCameraID != AppSettings.autoCameraID
            && !settingsCameras.contains { $0.id == settings.selectedCameraID }
    }

    private let supportedCodeTypes = [
        "QR Code", "EAN-8", "EAN-13", "Code 128", "Code 39", "UPC-E", "Aztec", "PDF417"
    ]

    private func refreshCameras() {
        let cameras = CameraScanner.discoverCameras()
        withAnimation(.easeInOut(duration: 0.15)) {
            settingsCameras = cameras
        }
    }

    private func cameraDescription(_ camera: CameraDevice) -> String {
        if camera.isContinuityCamera { return "连续互通相机" }
        if camera.isExternal { return "外接摄像头" }
        return "内置摄像头"
    }
}
