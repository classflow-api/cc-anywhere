# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 与 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [1.1.0] - 2026-05-20

跨端任务可见性大版本 · Cross-end Task Visibility Major Release

### 新增 Added

- **手机端任务进度面板（TodoPanel）** Tab 顶部固定折叠 panel,实时显示 Claude Code Task 工具创建的任务清单(N/M 进度 + 当前 in_progress 任务名),展开看完整 todos 列表(pending/in_progress/completed 三态 icon)
  - *Task progress panel on Android, mirroring Mac TUI Update Todos: real-time N/M progress with current in-progress item; tap to expand full todos list*
- **手机端 sub-agent 运行状态栏（SubAgentRunnerBar）** 输入框上方固定显示活跃 sub-agent,实时显示工具调用数 + 当前在跑的工具名,点击进 SubAgentDetailScreen 查看完整 prompt + thinking/tool 时间线
  - *Bottom sub-agent status bar above the input field, similar to Mac TUI "Running N agents…"; tap to drill into a full timeline view*
- **Sub-agent 详情页（SubAgentDetailScreen）** 显示子 agent 完整 prompt、运行状态、children 时间线(thinking/tool_use/tool_result)、最终结果
  - *Sub-agent detail screen with full prompt, status, children timeline and final result*
- **AppLogger 文件 mirror** 启动时初始化 `/sdcard/Android/data/<pkg>/files/cc-anywhere.log` 文件 sink,所有日志同步落盘,`adb pull` 可直接拉取,便于 release 模式诊断
  - *AppLogger file-mirror to app-specific external storage; `adb pull` works without manual clipboard copy for release-mode diagnostics*
- **Claude Code 2.0+ Task 三件套适配** ChatRepository 增量识别 TaskCreate/TaskUpdate/TaskList,按 taskId 维护 Map<String, TodoItem>,实时更新顶部 panel
  - *Native Claude Code 2.0+ TaskCreate/TaskUpdate/TaskList incremental state machine driving the top panel*

### 变更 Changed

- **ToolUseCard 默认状态文案** "待批准" → "运行中";仅 Bash/Write/Edit/NotebookEdit 4 个危险工具的 pending 才显示"批准/拒绝/总是"按钮 + "待批准";Agent/Read/Glob/Task\* 等无 hook 拦截的工具直接显示"运行中"
  - *ToolUseCard default state label changed from "awaiting approval" to "running"; approve buttons only shown for Bash/Write/Edit/NotebookEdit*
- **Sub-agent UI 重构** 运行中 sub-agent 从消息流折叠块移到底部 RunnerBar,完成态留消息流原位置作为折叠 done 卡片;消息流不再被多条 sub-agent 卡片污染
  - *Running sub-agents now live in the bottom bar, only completed ones stay in the message stream as folded cards*
- **消息流降噪** TaskCreate/TaskUpdate/TaskList + Agent/Task 的 tool_use 与 tool_result 卡片全部消音(关键信息已在顶部 TodoPanel / 底部 RunnerBar)
  - *Mute TaskCreate/TaskUpdate/TaskList/Agent/Task tool_use + tool_result cards from the message stream (info already shown in panels)*
- **TodoPanel 自动隐藏** 所有 task 都 completed 时 panel 自动隐藏(不再占用屏幕显示"5/5 已完成"),新增 task 时自动重新出现
  - *TodoPanel auto-hides when all tasks completed, re-appears on next TaskCreate*
- **`/clear` 命令同步清空** 手机端 `/clear` 现在一并清空 TodoPanel + SubAgentRunnerBar + sub-agent buffer + pending TaskCreate 匹配状态
  - *`/clear` now also wipes TodoPanel, SubAgentRunnerBar, sub-agent buffer and pending TaskCreate matchers*

### 修复 Fixed

- **Mac JSONLWatcher hook-dedup 误吞 Task\* 工具 raw** Task\* 系列(TaskCreate/TaskUpdate/TaskList/TaskGet)按 [Claude Code #20243](https://github.com/anthropics/claude-code/issues/20243) bypass PreToolUse/PostToolUse,但 PostToolUse matcher=`.*` 仍把这些 tool_use_id 加进 hookPushedToolUseIds 触发 JSONL dedup,导致手机端拿不到真实 TaskUpdate raw,panel 看似"卡住"。修复:`extractToolUseIds` 内排除 Task\* 工具
  - *JSONLWatcher hook-dedup was incorrectly skipping Task\* JSONL rows because PostToolUse matcher=`.*` still marked them in hookPushedToolUseIds even though Task\* tools bypass hooks (Claude Code issue #20243). Now Task\* tools are excluded from the dedup set so phone gets real raw rows*
- **手机端时间显示错乱（UTC 没转本地）** jsonl 时间是 ISO 8601 UTC,DateTime.parse 后 isUtc=true,time_separator 取 `.year/.hour` 拿 UTC 值显示 "今天 00:32"(实际本地 08:32)。修复:`Message._parseTs` 统一 `toLocal()`
  - *Time separators were showing UTC times instead of local; `Message._parseTs` now calls `toLocal()`*
- **HistoryBridge 跨会话 agent-\*.jsonl 污染** 同 project 目录下多个旧 session 的 agent-\*.jsonl 全部纳入历史回放,promptHash 表跨会话匹配可能误关联。修复:24h mtime cutoff 仅取与父 session 时间相近的 agent-\*
  - *HistoryBridge now applies a 24h mtime cutoff so stale agent-\*.jsonl files from older sessions no longer pollute history replay*
- **HistoryBridge limit 截断 Task\* 状态** 历史回放按 tail limit 取最近 N 条,导致 TaskCreate 落在 limit 之外而 TaskUpdate 在 limit 内 → 手机端 `_applyTaskUpdate` 找不到 existing。修复:Task\* raw 单独 union 不受 limit 截断 + 按 uuid 与 tail dedup
  - *Task\* JSONL rows are now extracted in addition to the tail limit so TaskUpdate can always find its TaskCreate during history replay*
- **Claude Code 预热 sub-agent 噪音** Claude Code 启动时预热 N 个 dummy subagent(agent-\*.jsonl 首条 content == "Warmup"),手机端按孤儿 SubAgentBlock 显示"Task 子 agent 运行中"误导用户。修复:`_isWarmupSidechain` 检测首条 content == "Warmup" → 整条丢弃
  - *Warmup sub-agents (first message content == "Warmup") are now filtered out from the runner bar*
- **flutter build 增量编译 cache bug** 触发条件:部分 dart 改动后 flutter build 显示 Built / install Success,但实际 widget 未更新。Workaround:`flutter clean` + `flutter pub get` + `flutter build`。本次修复路径中多次踩坑,已记录到 docs
  - *Hit a flutter build incremental-compile cache issue where dart changes weren't actually included in the APK despite a successful build/install. Workaround: `flutter clean` before rebuilding*

## [1.0.0] - 2026-05-18

首个正式开源版本。

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
