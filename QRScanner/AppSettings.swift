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
    @Published var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") }
    }
    @Published var selectedCameraID: String {
        didSet { UserDefaults.standard.set(selectedCameraID, forKey: "selectedCameraID") }
    }
    @Published var launchAtLoginEnabled: Bool {
        didSet {
            if #available(macOS 13.0, *) {
                do {
                    if launchAtLoginEnabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    // Revert on failure
                    DispatchQueue.main.async {
                        self.launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
                    }
                }
            }
        }
    }

    /// nil = use selectedCameraID; "auto" = pick best available
    static let autoCameraID = "auto"

    init() {
        self.soundEnabled = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
        self.autoCopy = UserDefaults.standard.object(forKey: "autoCopy") as? Bool ?? true
        if let raw = UserDefaults.standard.string(forKey: "theme"),
           let saved = AppTheme(rawValue: raw) {
            self.theme = saved
        } else {
            self.theme = .system
        }
        self.selectedCameraID = UserDefaults.standard.string(forKey: "selectedCameraID") ?? AppSettings.autoCameraID

        // Sync launch-at-login state from SMAppService
        if #available(macOS 13.0, *) {
            self.launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        } else {
            self.launchAtLoginEnabled = false
        }
    }
}
