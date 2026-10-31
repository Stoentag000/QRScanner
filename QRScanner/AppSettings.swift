import Foundation
import ServiceManagement
import SwiftUI
import Combine

// MARK: - Theme

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "跟随系统"
    case light = "浅色"
    case dark = "深色"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }
    @Published var autoCopy: Bool {
        didSet { UserDefaults.standard.set(autoCopy, forKey: "autoCopy") }
    }
    @Published var historyEnabled: Bool {
        didSet { UserDefaults.standard.set(historyEnabled, forKey: "historyEnabled") }
    }
    @Published var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") }
    }
    @Published var selectedCameraID: String {
        didSet { UserDefaults.standard.set(selectedCameraID, forKey: "selectedCameraID") }
    }
    @Published var launchAtLoginEnabled: Bool {
        didSet {
            // didSet fires even when re-assigning the same value. Without this
            // guard a failed register/unregister would revert, re-enter didSet,
            // fail again, and loop forever.
            guard !isRevertingLaunchAtLogin else { return }
            applyLaunchAtLogin(launchAtLoginEnabled)
        }
    }

    /// 系统把登录项判为「待批准」时，`register()` 会成功返回但服务并未生效，
    /// 用户必须去系统设置里放行，界面需要把这件事讲明白。
    @Published private(set) var launchAtLoginNeedsApproval = false

    private var isRevertingLaunchAtLogin = false

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            isRevertingLaunchAtLogin = true
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            isRevertingLaunchAtLogin = false
        }
        launchAtLoginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    /// nil = use selectedCameraID; "auto" = pick best available
    static let autoCameraID = "auto"

    init() {
        self.soundEnabled = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
        self.autoCopy = UserDefaults.standard.object(forKey: "autoCopy") as? Bool ?? true
        self.historyEnabled = UserDefaults.standard.object(forKey: "historyEnabled") as? Bool ?? true
        if let raw = UserDefaults.standard.string(forKey: "theme"),
           let saved = AppTheme(rawValue: raw) {
            self.theme = saved
        } else {
            self.theme = .system
        }
        self.selectedCameraID = UserDefaults.standard.string(forKey: "selectedCameraID") ?? AppSettings.autoCameraID

        // Sync launch-at-login state from SMAppService. 「待批准」时开关保持打开，
        // 与「系统设置 > 通用 > 登录项」里显示的待批准状态一致。
        let loginItemStatus = SMAppService.mainApp.status
        self.launchAtLoginEnabled = (loginItemStatus == .enabled || loginItemStatus == .requiresApproval)
        self.launchAtLoginNeedsApproval = (loginItemStatus == .requiresApproval)
    }
}
