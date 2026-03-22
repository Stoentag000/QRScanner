import AppKit

/// 扫码提示音播放器 — 使用系统音效
final class SoundPlayer {
    static let shared = SoundPlayer()

    func play() {
        NSSound(named: "Ping")?.play()
    }
}
