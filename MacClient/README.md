# cc-anywhere · MacClient

Swift Package–based macOS app for the cc-anywhere project (Mac side).

## 依赖

- macOS 14 (Sonoma) +
- Swift 5.9 / Xcode 15+
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (拉取自 SPM)
- Claude Code CLI (`claude` 可执行文件) 已安装在 `PATH` 或下列默认位置之一：
  - `/usr/local/bin/claude`
  - `/opt/homebrew/bin/claude`
  - `~/.local/bin/claude`
  - `~/.bun/bin/claude`

## 目录结构

```
MacClient/
├── Package.swift
├── Sources/CCAnywhere/
│   ├── App/                   # 入口、AppDelegate、依赖注入容器
│   ├── Models/                # Tab / ServerConfig / Device / ParsedMessage / ProtocolMessage
│   ├── Services/              # TabManager / ProcessHost / JSONLWatcher / WSClient /
│   │                          # DeviceManager / InputInjector / ImageDownloader /
│   │                          # PreferencesService / ThemeManager / PIDTracker / Logger
│   ├── Views/                 # 主窗口、Tab 栏、终端容器、活动面板、偏好窗口、日志窗口
│   │   ├── Components/        # PulseDot / StatusPill / GlassCard / DotGridBackground / AuroraOrbs / SectionLabel
│   │   └── Preferences/       # General / Server / Devices / Themes / Security / Logs
│   ├── Theme/                 # ColorTokens / TerminalThemes / Typography
│   └── Resources/Info.plist
└── README.md
```

## 构建

```bash
cd MacClient
swift package resolve
swift build
```

会产出可执行 `MacClient/.build/<arch>/debug/CCAnywhere`。直接运行该文件即可
在终端中启动 App（注意：作为命令行启动时，没有 Info.plist bundle，部分
macOS 特性可能受限）。

## 运行（推荐）

把这个 SPM 工程导入 Xcode：

```bash
open Package.swift
```

然后 Run 即可。Xcode 会以 App bundle 形式启动，菜单栏、偏好窗口、键盘快
捷键等都正常。

## 配置数据存放路径

- `~/Library/Application Support/cc-anywhere/tabs.json`
- `~/Library/Application Support/cc-anywhere/server-config.json`
- `~/Library/Application Support/cc-anywhere/preferences.json`
- `~/Library/Application Support/cc-anywhere/last-pids.json`
- `~/Library/Application Support/cc-anywhere/inbox/`
- `~/Library/Logs/cc-anywhere/cc-anywhere.log`

## 设计稿映射

视觉参照 `docs/跨端协作客户端/UI设计稿/cc-anywhere/project/mac-client.jsx`，
要点：

- 默认 dark 主题（背景 `#0b0e14`, accent oklch(0.78 0.13 200) ~ cyan）
- 玻璃面板使用 `.ultraThinMaterial` + 自定义边框模拟 backdrop-filter blur
- 状态点（PulseDot）使用 1.6s ease-out 无限循环
- DotGridBackground 使用 Canvas + TimelineView 实现 30s 漂移效果
- AuroraOrbs 使用 3 个 80px blur 的 Circle，周期 18/22/28s 漂移
- 6 个终端主题 1:1 映射 tokens.js 的 TERMINAL_THEMES（颜色完全一致）

## 已知限制

- 终端的 24-bit 真彩色 ANSI 调色板尚未完全按主题重映射（仅前景、背景、
  光标和选区已切换）；6 个主题的代码块语法高亮在 Claude Code TUI 中由
  Claude 端控制颜色，不在 MacClient 范畴。
- 由于 macOS sandbox 默认会阻止 `LocalProcessTerminalView` 启动子进程，
  作为命令行运行时不需要 entitlements；如用 Xcode 打包，请在 Capabilities
  中关闭沙盒。
