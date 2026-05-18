# 项目约定 · Project Conventions

> 这份文档面向用 AI 编程助手（[Claude Code](https://claude.com/claude-code) / Cursor / Continue / Aider 等）协作开发本项目的开发者。
> 它说明项目结构、技术栈、核心设计原则，让 AI 助手能快速建立项目上下文。

## 项目信息

- **项目名称**：cc-anywhere（产品名：遥指）
- **定位**：跨端 Claude Code 协作客户端 — 通过自有 VPS 桥接 Mac 桌面客户端和 Android 客户端
- **架构**：三端（Mac App / Android App / Server）+ Python hook bridge
- **License**：MIT
- **公司**：Beijing Yoolines Interactive Information Technology Co., Ltd. (北京友联互动信息技术有限公司)

详细介绍 → [README.md](./README.md) / [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md)

## 目录结构

```
cc-anywhere/
├── MacClient/         # Mac 桌面客户端（Swift + SwiftUI + SwiftTerm）
├── AndroidClient/     # Android 客户端（Flutter + Riverpod）
├── Server/            # 中转服务器（Go + WebSocket）
├── docs/              # 设计文档 / 开发演进记录
├── README.md          # 主入口（中文）
├── README.en.md       # 英文版
├── LICENSE            # MIT
├── CONTRIBUTING.md    # 贡献指南
├── CODE_OF_CONDUCT.md
├── SECURITY.md
└── CHANGELOG.md
```

## 技术栈

| 端 | 语言 | 框架 | 关键依赖 |
|---|---|---|---|
| **MacClient** | Swift 5.9 | AppKit + SwiftUI | SwiftTerm（系统 PTY）/ Network.framework |
| **AndroidClient** | Dart 3.3 | Flutter | Riverpod / flutter_local_notifications / web_socket_channel |
| **Server** | Go 1.21 | 标准库 | nhooyr.io/websocket / SQLite |
| **Hook Bridge** | Python 3 | macOS 系统预装 | 标库 |

## 核心架构原则（修改代码前必读）

1. **无 Mac 端 daemon**：Mac App 单 UI 进程；App 退出 = 杀 Tab 内 claude 子进程 + 断 ws
2. **对话持久化交给 Claude Code**：本地仅存 Tab 列表（folder 路径），重启时用 `claude -c` 恢复
3. **双通道输出**：
   - 通道 A（Mac 自看）：PTY 字节流 → SwiftTerm
   - 通道 B（推手机）：FSEvents 监听 `~/.claude/projects/<encoded>/<session>.jsonl` → 解析 → ws 推
   - 通道 C（实时桥接，本次 L4 引入）：Claude Hook → Unix socket → Mac App → ws 推
4. **不用 tmux**：直接系统 PTY（SwiftTerm 的 `LocalProcessTerminalView`）
5. **手机端是轻量 viewer + 决策端**：仅卡片消息 / Other 输入 / tool_use 批准 / 图片上传
6. **个人工具定位**：不做多租户、不做 E2EE、TLS 足够
7. **Server 是 dumb proxy**：业务消息默认透传，业务协议两端自定义；加新 type 不要求重部 Server
8. **Hook 软失败原则**：hook bridge 任何异常都不能比"没装 hook"更糟（NFR-U1/U2 硬规则）

## 提交规范

- 采用 [Conventional Commits](https://www.conventionalcommits.org/)
- Type: `feat` / `fix` / `docs` / `style` / `refactor` / `perf` / `test` / `chore` / `ci`
- Scope: `mac` / `phone` / `server` / `hook-bridge` / `docs`
- 中英文 commit message 都可，单 PR 内尽量统一

## 编码风格

| 语言 | 风格 |
|---|---|
| Swift | swift-format defaults |
| Dart | `dart format lib/` |
| Go | `gofmt + go vet` |
| Python | Black + Ruff |

**通用约定**：

- 必要时写注释解释 **为什么**（why），不解释**做什么**（what 让代码自解释）
- 复杂业务逻辑 / 边界处理加注释；细分到"为什么这么做" + "曾经在 XX 出过 bug，所以这里这么写"
- 文件 header 保留版权声明（MIT 与公司著作权兼容）

## 不会做的事（Out of Scope）

- 真 token 级 streaming（hook 不支持 content_block_delta）
- 跨平台 Mac 端（仅 macOS 14+）
- iOS 客户端（当前仅 Android，未来可能）
- 多租户 SaaS（个人工具定位）
- 端到端加密（TLS + 自托管够用）

## 详细文档

- [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md) — 完整架构、双通道数据流、Hook 软失败原则、Winner 锁、Dumb Proxy
- [docs/INSTALL.md](./docs/INSTALL.md) — 三端部署
- [docs/FAQ.md](./docs/FAQ.md) — 常见问题
- [docs/AskUserQuestion远程交互/](./docs/AskUserQuestion远程交互/) — 完整 L4 流程产物（PRD / 需求 / 技术 / 三轮 Review / 上线研判），AI 协作开发的全套样板

## 给 AI 助手的提示

如果你（AI 助手）正在协助修改本项目：

- **改 Mac 端代码** → 优先读 `MacClient/README.md` + `docs/ARCHITECTURE.md` §4 关键文件索引
- **改 Phone 端代码** → 优先读 `AndroidClient/README.md` + chat_screen / ask_question_controller
- **改 Server 代码** → 优先读 `Server/README.md` + `Server/internal/router/router.go` 顶部 dumb proxy 注释
- **改协议** → 同步改 Mac `ProtocolMessage.swift` + Phone `protocol_message.dart`（**Server 通常不需要改**，dumb proxy）
- **改 hook 行为** → 同时改 `cc-anywhere-hook-bridge.py` + `HookIpcServer.swift`，并保证三道软失败保护不破坏
