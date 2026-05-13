# 项目约定

## 项目信息

- 项目名称：cc-anywhere
- 项目描述：跨端 Claude Code 协作客户端 - 通过自有 VPS 桥接 Mac 桌面客户端和 Android 客户端，允许在 Mac 上管理多个 Claude Code 会话 Tab，并通过手机端以卡片消息形式实时查看和交互

## 开发规范

- 代码提交使用约定式提交格式（可用 `/yoolines-git-commit`）
- 新需求开发遵循公司标准开发流程（可用 `/yoolines-dev-workflow`）
- 提交 PR 前执行代码审查（可用 `/yoolines-code-review`）
- 下班前执行收尾流程（可用 `/yoolines-end-of-day`）

## 目录说明

- `docs/` — 需求文档、技术方案、审查报告、研判报告
- `docs/daily/` — 工作日报
- `MacClient/` — Mac 桌面客户端源码
- `AndroidClient/` — Android 客户端源码
- `Server/` — 中转服务器源码

## 技术栈

### MacClient（Mac 桌面客户端）
- 语言：Swift
- 框架：AppKit / SwiftUI
- 终端渲染：SwiftTerm + 系统 PTY
- 进程模型：单 App 进程，每个 Tab 一个 `claude -c` 子进程

### AndroidClient（Android 客户端）
- 语言：Dart
- 框架：Flutter
- UI 模式：卡片式消息列表（非完整 TUI 渲染）
- 数据源：监听 Mac 端 Claude Code 的 JSONL 对话历史

### Server（中转服务器）
- 语言：Go
- 协议：WebSocket over TLS
- 部署：自有 VPS，自定义端口（无 80/443）
- 职责：消息路由 + 设备绑定，无业务状态

## 核心架构原则

1. **无 Mac 端 daemon**：Mac 客户端 = 唯一 UI 进程；软件退出 = 杀子进程 + 断网络长连接
2. **对话持久化交给 Claude Code**：本地仅存 Tab 列表（文件夹路径）；重启时用 `claude -c` 恢复
3. **双通道输出**：
   - 通道 A（Mac 自看）：PTY 字节流 → SwiftTerm
   - 通道 B（推手机）：FSEvents 监听 `~/.claude/projects/<encoded_path>/<session>.jsonl` → 推结构化消息
4. **不用 tmux**：直接用系统 PTY（SwiftTerm 提供的 `LocalProcessTerminalView`）
5. **手机端为轻量 viewer**：仅展示结构化消息 + 接收文字/图片输入 + tool_use 批准
6. **个人工具定位**：不做端到端加密，仅 TLS；不做多租户

## 详细设计文档

完整的产品需求、技术方案、接口定义详见 `docs/` 目录（在 `/yoolines-dev-workflow` 流程中产出）。
