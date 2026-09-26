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
    private var keyMonitor: Any?
    private var scannerIsCameraMode = true  // Track scanner mode across reopen
    private var statusIconRestoreWorkItem: DispatchWorkItem?
    private static let statusIconSymbol = "qrcode.viewfinder"
    let settings: AppSettings = .shared
    lazy var history = ScanHistory(settings: settings)

    override init() {
        super.init()
        setupStatusItem()
        cameraScanner = CameraScanner()
    }

    deinit {
        if let monitor = rightClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else { return }

        button.image = NSImage(systemSymbolName: Self.statusIconSymbol,
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

        // Monitor Command+Q while popover has focus (NSPopover steals keyboard events)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "q" {
                self?.quitApp()
                return nil
            }
            return event
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
        // Clear any stale subscriptions before creating new ones
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()

        guard let scanner = cameraScanner else { return }

        // 通过 Combine 监听 @Published 统一处理检测结果
        //
        // ⚠️ dropFirst 必须最先：
        // @Published 订阅时会立刻重放当前值。若上次扫码结果还留在
        // lastDetectedCode 里（stopRunning 异步清 nil 尚未完成），重开面板
        // 会把旧码再处理一遍（重复历史/复制/响铃）。
        //
        // ⚠️ 去重必须在 compactMap 之前：
        // CameraScanner 在“码离开画面”时会发布 nil 以便同一码可再次识别，
        // 帧序是 "A" → nil → "A"。如果先 compactMap 再 removeDuplicates，
        // nil 被丢掉后两次 "A" 会被误判为重复，导致第二次扫描不复制/不记录/不响铃。
        // 在 Optional 上去重，让 nil 参与比较，即可放行合法的重复扫描。
        scanner.$lastDetectedCode
            .dropFirst()
            .removeDuplicates()
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] code in
                self?.handleDetectedCode(code)
            }
            .store(in: &cancellables)

        let scannerView = ScannerView(
            cameraScanner: scanner,
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
        // Only start the camera in camera mode. Starting unconditionally then
        // stopping from ScannerView.onAppear races with requestAccess and can
        // leave the session running (and scanning) while the UI shows image mode.
        if scannerIsCameraMode {
            cameraScanner?.startRunning(cameraID: settings.selectedCameraID)
        } else {
            cameraScanner?.stopRunning()
        }
    }

    // MARK: - Scanner Cleanup

    private func cleanupScanner() {
        cameraScanner?.stopRunning()
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
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
        window.setContentSize(NSSize(width: 760, height: 540))
        window.minSize = NSSize(width: 680, height: 480)
        // Let the split view extend through the titlebar.  This keeps the
        // standard window controls visually within the sidebar, matching the
        // macOS 26 Settings-style liquid glass layout.
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.titlebarSeparatorStyle = .none
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
        self.popover = nil
        return true
    }

    // MARK: - Detected Code Handling

    private func handleDetectedCode(_ code: String) {
        lastCopiedValue = code
        history.add(code, source: .camera)

        if settings.autoCopy {
            _ = Clipboard.copy(code)
        }

        if let button = statusItem.button {
            // Cancel any pending restore and always reset to the known base
            // symbol. Capturing button.image and restoring it later breaks when
            // two codes arrive within the delay: the second capture is already
            // the checkmark, so the icon sticks on "Copied".
            statusIconRestoreWorkItem?.cancel()
            button.image = NSImage(systemSymbolName: "checkmark.circle.fill",
                                   accessibilityDescription: "Copied")
            let work = DispatchWorkItem {
                button.image = NSImage(systemSymbolName: Self.statusIconSymbol,
                                       accessibilityDescription: "QRScanner")
            }
            statusIconRestoreWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
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
            _ = Clipboard.copy(last)
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
