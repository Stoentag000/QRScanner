# 🔍 QRScanner

- ⚠️该程序由Xiaomi MiMo Claw编写
- 一款纯 Swift 编写的 macOS 菜单栏 QR 码 / 条形码扫描器，常驻菜单栏，点击即用。

## 简介

QRScanner 解决一个简单的需求：快速识别屏幕前方或图片中的二维码，结果自动复制到剪贴板。不需要打开任何 App，菜单栏点一下就够了。

## 功能

| 功能 | 说明 |
|------|------|
| 摄像头扫码 | 前置摄像头实时检测 QR 码 / 条形码，基于 Vision 框架 |
| 图片识别 | 支持 PNG / JPG / TIFF / GIF / BMP / WebP，批量识别图中所有码 |
| 拖拽上传 | 直接拖拽图片到菜单栏面板，自动识别（支持摄像头和图片模式） |
| 自动复制 | 检测到码后自动复制到剪贴板（可关闭） |
| 提示音 | 扫码成功播放系统提示音（可关闭） |
| 扫描历史 | 自动保存所有记录，支持复制 / 删除 / 清空 |
| 开机自启 | 一键设置登录时自动启动 |
| 主题切换 | 支持浅色 / 深色 / 跟随系统 |
| 扫描动画 | 蓝色扫描线动画 + 圆角视图 |

## 构建

**环境要求：** macOS 14 Sonoma + Xcode 15+

```bash
cd QRScanner
open QRScanner.xcodeproj
# Xcode → ⌘R 运行
```

## 使用

1. 运行后菜单栏出现 QR 图标
2. **左键点击** → 打开扫描面板
3. **摄像头模式**：对准 QR 码 → 自动识别并复制
4. **上传图片**：切换模式按钮 → 选择图片，或直接**拖拽图片**到面板上
5. **扫描历史**：点击时钟图标 → 查看 / 复制 / 删除
6. **设置**：点击齿轮 ⚙️ → 打开设置窗口（侧栏导航）
   - **通用** — 主题切换、开机自启
   - **扫描行为** — 提示音、自动复制
   - **关于** — 应用信息、支持的码类型
7. 点击面板外任意位置 → 自动关闭
8. **右键图标** → 查看上次结果 / 退出

首次运行需要授权摄像头权限：**系统设置 → 隐私与安全性 → 摄像头 → 允许 QRScanner**

## 项目结构

```
QRScanner/
├── QRScanner.xcodeproj/       # Xcode 项目
├── README.md
└── QRScanner/
    ├── QRScannerApp.swift       # App 入口
    ├── AppDelegate.swift        # 应用代理
    ├── MenuBarController.swift  # 菜单栏图标 + 弹窗导航
    ├── ScannerView.swift        # 扫描主界面（摄像头 / 图片 / 拖拽）
    ├── CameraScanner.swift      # 摄像头采集 + Vision 检测
    ├── ImageCodeDetector.swift  # 静态图片码检测
    ├── HistoryView.swift        # 扫描历史界面
    ├── ScanHistory.swift        # 历史记录数据模型 + 持久化
    ├── SettingsView.swift       # 设置界面（侧栏导航）
    ├── AppSettings.swift        # 设置数据模型（UserDefaults）
    ├── SoundPlayer.swift        # 扫码提示音（系统音效）
    └── QRScanner.entitlements   # 权限（摄像头）
```

## 技术栈

- **SwiftUI** — 界面框架
- **AVFoundation** — 摄像头采集
- **Vision** — QR 码 / 条形码检测
- **NSPopover** — 菜单栏弹出面板
- **NavigationSplitView** — 设置界面侧栏导航
- **Combine** — 响应式数据绑定
- **SMAppService** — 开机自启
- **JSON** — 历史记录持久化

## 已知限制

- macOS 15 Sequoia 的 `AVCaptureMetadataOutput` 存在 Tundra 引擎 bug，本项目通过 `AVCaptureVideoDataOutput` + Vision 绕开
- 需要前置摄像头（MacBook / iMac / 外接摄像头）
