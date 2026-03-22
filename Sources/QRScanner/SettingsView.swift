import SwiftUI

// MARK: - Settings Categories

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "通用"
    case scanning = "扫描行为"
    case about = "关于"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .scanning: return "qrcode.viewfinder"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var selectedCategory: SettingsCategory = .scanning

    var body: some View {
        NavigationSplitView {
            // Sidebar
            sidebar
                .navigationSplitViewColumnWidth(min: 140, ideal: 160, max: 180)
        } detail: {
            // Detail
            detailView
                .navigationSplitViewColumnWidth(min: 280, ideal: 320)
        }
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Traffic light spacer
            Color.clear.frame(height: 38)

            List(selection: $selectedCategory) {
                ForEach(SettingsCategory.allCases) { category in
                    Label {
                        Text(category.rawValue)
                    } icon: {
                        Image(systemName: category.icon)
                    }
                    .tag(category)
                    .listItemTint(.cyan)
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(
            VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
        .overlay(alignment: .trailing) {
            // Right-edge divider with shadow
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        .black.opacity(0.25),
                        .black.opacity(0.08),
                        .clear
                    ],
                    startPoint: .trailing,
                    endPoint: .leading
                )
                .frame(width: 12)

                // Thin separator line
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 0.5)
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            Group {
                switch selectedCategory {
                case .general:
                    generalSettings
                case .scanning:
                    scanningSettings
                case .about:
                    aboutSettings
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    // MARK: - General Settings

    private var generalSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("启动")

                settingToggle(
                    icon: "power",
                    title: "开机自启",
                    subtitle: "登录时自动启动 QRScanner",
                    isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settings.launchAtLogin = $0 }
                    )
                )
            }
        }
    }

    // MARK: - Scanning Settings

    private var scanningSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("行为")

                settingToggle(
                    icon: "speaker.wave.2.fill",
                    title: "提示音",
                    subtitle: "扫码成功时播放提示音",
                    isOn: $settings.soundEnabled
                )

                settingToggle(
                    icon: "doc.on.clipboard",
                    title: "自动复制",
                    subtitle: "检测到码后自动复制到剪贴板",
                    isOn: $settings.autoCopy
                )
            }
        }
    }

    // MARK: - About Settings

    private var aboutSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("应用信息")

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 28))
                            .foregroundStyle(.cyan.opacity(0.7))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("QRScanner")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.85))
                            Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }

                    Text("一款纯 Swift 编写的 macOS 菜单栏二维码 / 条形码扫描器，常驻菜单栏，点击即用。")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineSpacing(3)

                    Text("由Stoentag000在Xiaomi MiMo Claw的支持下开发")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.cyan.opacity(0.45))
                }

                Divider()
                    .padding(.vertical, 4)

                sectionTitle("支持的码类型")

                VStack(spacing: 6) {
                    codeTypeRow(name: "QR Code", icon: "qrcode")
                    codeTypeRow(name: "EAN-8 / EAN-13", icon: "barcode")
                    codeTypeRow(name: "Code 128", icon: "barcode")
                    codeTypeRow(name: "Code 39", icon: "barcode")
                    codeTypeRow(name: "UPC-E", icon: "barcode")
                    codeTypeRow(name: "Aztec", icon: "qrcode")
                    codeTypeRow(name: "PDF417", icon: "qrcode")
                }
            }
        }
    }

    // MARK: - Components

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.3))
            .textCase(.uppercase)
    }

    private func settingToggle(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.cyan.opacity(0.6))
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))

                Text(subtitle)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
            }

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func codeTypeRow(name: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.cyan.opacity(0.4))
                .frame(width: 16)

            Text(name)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))

            Spacer()

            Text("支持")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.green.opacity(0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
