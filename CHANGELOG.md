# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 与 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### 新增 Added

- Mac App 打包脚本 `MacClient/build_app.sh`，输出 `遥指.app` 标准 macOS Bundle（含 Info.plist + AppIcon.icns）
- Android 应用显示名改为"遥指"
- Phone 端系统级通知（`AskNotificationService`）— ask.question.pending 到达时即便 App 在后台也弹通知 + 震动
- Phone 端进入聊天界面自动多帧 retry 滚到底部
- AskQuestion 卡片改为按 Tab 内嵌底部弹出（替代全局浮层），多 Tab 互不阻塞
- Server `republishPendingToPhone` — phone 重连时自动重发未答 ask 卡片
- Hook IPC 改用 BSD socket（绕开 macOS `NWListener.unix` 的 EINVAL 限制）
- AskUserQuestion 远程交互 M1-M4（hook 基础设施 + 工具进度 + Notification + 危险工具批准）
- Phone 端 AskUserQuestionCard 支持自定义文字回答（对齐 AskUserQuestion 工具自带 Other 选项）
- 浅色模式下用户气泡 / 发送按钮使用白色前景

### 变更 Changed

- **Server 改为 dumb proxy**：业务消息默认透传，加新协议 type 不再要求重部 Server
- Mac App inner ask timeout：5 分钟 → 30 分钟（与 settings.json hook timeout 对齐）
- Phone 消息流的 AskUserQuestionCard：pending 时不显示，已答时显示精简"已回答"记录卡（避免双卡）
- JSONLWatcher 双推去重：仅按 `assistant.tool_use.id` 跳过，`user.tool_result` 仍正常推（保证 phone 看到答案落地）

### 修复 Fixed

- Mac App "选择项目文件夹"按钮无响应（EmptyStateView 的 notification 没有 listener）
- HookIpcServer 重启时 `socket file did not appear within 2s` 警告
- multiSelect 字段 JSON tag 三端对齐（保留 camelCase 而非 snake_case，与 AskUserQuestion 工具原生 schema 一致）
- hook bridge 任何 error 路径都返回 `{}` 软失败（之前 timeout 误翻译为 deny 会阻断 Claude）
- 31+ 项手机端 / Mac 端零散 bug（见 docs/零散需求/）

### 安全 Security

- settings.json 写入采用 atomic rename + 5 份 backup 轮转 + 精准识别（不误删其他 plugin hook）
- Hook bridge 软失败三道保护：env 缺失 / socket 不可达 / 任意异常 → 返回 `{}` 让 SDK 走 fallback
- socket 文件权限 0600

### 文档 Docs

- 完整的 L4 开发流程文档归档（docs/AskUserQuestion远程交互/）
- 三端 README、INSTALL、ARCHITECTURE、FAQ、CONTRIBUTING、SECURITY、CODE_OF_CONDUCT、CHANGELOG

## [0.1.0-pre] - 2026-05 项目初版

- 三端初版开发完成（MacClient + AndroidClient + Server）
- 跨端 Claude Code 协作核心能力：Tab 管理、JSONL 消息流、消息历史、图片上传、tool_use 批准
- 设备扫码绑定 + sub_token 鉴权
- 6 套终端主题
- TLS + HMAC 鉴权 + master_token

详细历史见 [git log](../../commits/master)。
