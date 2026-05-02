import SwiftUI
import AppKit
import Combine
import Foundation
import ServiceManagement

final class MenuBarController: NSObject, NSWindowDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var cameraScanner: CameraScanner?
    private var cancellables = Set<AnyCancellable>()
    private var lastCopiedValue: String?
    private var rightClickMonitor: Any?
    private var scannerIsCameraMode = true  // Track scanner mode across reopen
    let history = ScanHistory()
    let settings: AppSettings = .shared

    override init() {
        super.init()
        setupStatusItem()
    }

    deinit {
        if let monitor = rightClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else { return }

        button.image = NSImage(systemSymbolName: "qrcode.viewfinder",
                               accessibilityDescription: "QRScanner")
        button.target = self
        button.action = #selector(handleClick(_:))

        // Monitor right-click on status item — NSStatusItem's action
        // only fires for left-click, so we need this for right-click.
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseUp) {
            [weak self] event in
            guard let self, let button = self.statusItem.button,
                  event.window == button.window else { return event }
            self.showContextMenu()
            return nil // consume the event
        }
    }

    @objc private func handleClick(_ sender: Any?) {
        // If settings window is open, close it and open scanner instead
        if settingsWindow != nil {
            settingsWindow?.close()
            settingsWindow = nil
            openPopover()
            return
        }

        if popover?.isShown == true {
            closePopover()
        } else {
            openPopover()
        }
    }

    // MARK: - Popover

    private func showPopover(with view: some View) {
        let contentVC = NSHostingController(rootView: view)
        if let scheme = settings.theme.colorScheme {
            contentVC.view.appearance = scheme == .dark
                ? NSAppearance(named: .darkAqua)
                : NSAppearance(named: .aqua)
        } else {
            contentVC.view.appearance = nil
        }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 500)
        popover.behavior = .transient
        popover.contentViewController = contentVC
        popover.delegate = self

        self.popover = popover

        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func openPopover() {
        cameraScanner = CameraScanner()

        // 通过 Combine 监听 @Published 统一处理检测结果
        cameraScanner!.$lastDetectedCode
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] code in
                self?.handleDetectedCode(code)
            }
            .store(in: &cancellables)

        let scannerView = ScannerView(
            cameraScanner: cameraScanner!,
            history: history,
            settings: settings,
            initialCameraMode: scannerIsCameraMode,
            onModeChange: { [weak self] isCamera in
                self?.scannerIsCameraMode = isCamera
            },
            onShowHistory: { [weak self] in
                self?.switchToHistory()
            },
            onShowSettings: { [weak self] in
                self?.switchToSettings()
            }
        )

        showPopover(with: scannerView)
        cameraScanner?.startRunning(cameraID: settings.selectedCameraID)
    }

    // MARK: - Scanner Cleanup

    private func cleanupScanner() {
        cameraScanner?.stopRunning()
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        cameraScanner = nil
    }

    private func switchToSettings() {
        cleanupScanner()
        popover?.close()
        popover = nil

        // Reuse existing window or create new one
        if let window = settingsWindow {
            window.orderFrontRegardless()
            return
        }

        let settingsView = SettingsView(settings: settings)

        let contentVC = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: contentVC)
        window.title = "QRScanner 设置"
        window.setContentSize(NSSize(width: 580, height: 420))
        window.minSize = NSSize(width: 500, height: 360)
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self

        self.settingsWindow = window
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === settingsWindow {
            settingsWindow = nil
        }
    }

    private func switchToHistory() {
        cleanupScanner()
        popover?.close()

        let historyView = HistoryView(history: history, settings: settings) { [weak self] in
            self?.reopenScanner()
        }
        showPopover(with: historyView)
    }

    private func reopenScanner() {
        popover?.close()
        openPopover()
    }

    private func closePopover() {
        cleanupScanner()
        popover?.close()
        popover = nil
    }

    // MARK: - Popover Delegate (cleanup on auto-dismiss)

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        cleanupScanner()
        return true
    }

    // MARK: - Detected Code Handling

    private func handleDetectedCode(_ code: String) {
        lastCopiedValue = code
        history.add(code, source: .camera)

        if settings.autoCopy {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
        }

        if let button = statusItem.button {
            let origImage = button.image
            button.image = NSImage(systemSymbolName: "checkmark.circle.fill",
                                   accessibilityDescription: "Copied")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                button.image = origImage
            }
        }

        if settings.soundEnabled {
            SoundPlayer.shared.play()
        }
    }

    // MARK: - Context Menu

    private func showContextMenu() {
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "打开主界面", action: #selector(openScanner), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        let settingsItem = NSMenuItem(title: "设置", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        if let last = lastCopiedValue {
            menu.addItem(.separator())
            let preview = String(last.prefix(40)) + (last.count > 40 ? "…" : "")
            let copyItem = NSMenuItem(title: "上次: \(preview)", action: #selector(reCopy), keyEquivalent: "")
            copyItem.target = self
            menu.addItem(copyItem)
        }

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 QRScanner", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        // Show menu anchored to the status bar button
        if let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
        }
    }

    @objc private func openScanner() {
        if settingsWindow != nil {
            settingsWindow?.close()
            settingsWindow = nil
        }
        if popover?.isShown != true {
            openPopover()
        }
    }

    @objc private func openSettings() {
        closePopover()
        switchToSettings()
    }

    @objc private func reCopy() {
        if let last = lastCopiedValue {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(last, forType: .string)
        }
    }

    @objc private func quitApp() {
        cleanupScanner()
        popover?.close()
        popover = nil
        settingsWindow?.close()
        settingsWindow = nil
        NSApp.terminate(nil)
    }
}
