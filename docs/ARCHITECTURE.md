# 架构

本文档面向想要了解 cc-anywhere 设计原理 / 修改协议 / 加新功能的开发者。

## 1. 设计目标

| # | 目标 | 体现 |
|---|---|---|
| 1 | **不破坏 Claude TUI 原生体验** | Mac 上用户照常 typing claude，cc-anywhere 是旁观 + 桥接 |
| 2 | **无 Mac 端 daemon** | App 退出 = 杀子进程 + 断 ws，重启自动恢复 |
| 3 | **手机端是结构化 viewer + 决策端**，不是 TUI 复刻 | 卡片消息 / Tool Use 卡 / AskUserQuestion 实时弹卡 / 工具批准 |
| 4 | **Server 长期不动** | dumb proxy，业务协议两端定义，加新 type 不重部 |
| 5 | **个人工具定位** | 不做多租户、不做端到端加密、TLS 足够 |
| 6 | **降级永不致命** | hook 任何异常都软失败，回到没装 hook 的原生体验 |

## 2. 系统拓扑

```
┌──────────────────────────────────────────────────────────┐
│  Mac 端                                                   │
│  ┌────────────────────────────────────────────────────┐  │
│  │ 遥指.app (SwiftUI + AppKit)                        │  │
│  │                                                     │  │
│  │  ┌─────────┐   ┌────────────┐   ┌──────────────┐  │  │
│  │  │ Tab #1  │   │ Tab #2     │   │  Tab #N      │  │  │
│  │  │ claude  │   │ claude     │   │  claude      │  │  │
│  │  │  -c     │   │  -c        │   │   -c         │  │  │
│  │  │ ENV:    │   │ ENV:       │   │  ENV:        │  │  │
│  │  │  TAB=1  │   │  TAB=2     │   │   TAB=N      │  │  │
│  │  └────┬────┘   └─────┬──────┘   └──────┬───────┘  │  │
│  │       │              │                  │           │  │
│  │       │  PreToolUse / PostToolUse / Notification 钩子│  │
│  │       ▼              ▼                  ▼           │  │
│  │  hook-bridge.py (Python, 三道软失败保护)            │  │
│  │       │                                              │  │
│  │       ▼ Unix socket                                  │  │
│  │  HookIpcServer (Swift actor)                         │  │
│  │   ├─ 接 hook 请求 (ask / progress pre/post / notif)  │  │
│  │   ├─ 路由到对应 tab 的 cardController                 │  │
│  │   └─ 通过 WSClient 推到 server → phone                │  │
│  └──────────────┬───────────────────────────────────────┘  │
│                 │                                          │
│  ┌──────────────▼───────────────────────────────────┐    │
│  │ JSONLWatcher (FSEvents)                          │    │
│  │  监听 ~/.claude/projects/<encoded>/*.jsonl       │    │
│  │  → 解析 → ws 推 phone（结构化消息 + 去重）        │    │
│  └──────────────────────────────────────────────────┘    │
└────────────────────────────────┬─────────────────────────┘
                                 │ wss + TLS
                                 ▼
┌──────────────────────────────────────────────────────────┐
│  Server (Go, "dumb proxy")                               │
│  ┌────────────────────────────────────────────────────┐  │
│  │ auth: HMAC-SHA256 / master_token / sub_token       │  │
│  │ device: 绑定 / 撤销 / 列表                          │  │
│  │ presence: mac_online / phone_count 广播            │  │
│  │ image: 临时图片 upload + signed download URL       │  │
│  │ router: 业务消息默认透传（无 type 白名单）          │  │
│  └────────────────────────────────────────────────────┘  │
└────────────────────────────────┬─────────────────────────┘
                                 │ wss + TLS
                                 ▼
┌──────────────────────────────────────────────────────────┐
│  Android 端                                              │
│  ┌────────────────────────────────────────────────────┐  │
│  │ 遥指.apk (Flutter + Riverpod)                      │  │
│  │  WsClient (web_socket_channel) ←─ inbound 流       │  │
│  │   ├─ ChatRepository（消息流 + 历史补拉 + dedup）   │  │
│  │   ├─ AskQuestionController（实时 ask 卡片状态）    │  │
│  │   ├─ AskNotificationService（系统通知）             │  │
│  │   └─ DedupService（tool_use_id 24h 持久）          │  │
│  └────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

## 3. 关键设计

### 3.1 双通道数据流：JSONL 旁观 + Hook 实时

**通道 A（JSONL 旁观 / 事后）**：

- Mac App 的 `JSONLWatcher` 用 FSEvents 监听 `~/.claude/projects/<encoded_path>/<session>.jsonl`
- Claude SDK 完成一段 message / tool_use / tool_result 后才落盘
- 优势：能拿到 Claude 完整的 message 结构（assistant / user / thinking / tool_use / tool_result / 附件等）
- 劣势：滞后，看到的总是事后历史

**通道 B（Hook 实时）**：

- 通过 `~/.claude/settings.json` 注册 PreToolUse / PostToolUse / Notification hook
- Claude SDK 在执行 hook event 之前 fork hook bridge 脚本，**同步阻塞**等响应
- hook bridge 通过 Unix socket 连 Mac App `HookIpcServer`
- Mac App 通过 ws 推 phone，等回答 → 再回写 socket → SDK 解阻塞
- 优势：实时、可决策（AskUserQuestion 答案 / 工具批准）
- 劣势：受 hook 超时限制（默认 30 分钟）

两个通道**互补**，通过 `tool_use_id` 在 JSONLWatcher 和 phone 两侧去重。

### 3.2 Hook 软失败原则（NFR-U1/U2）

hook bridge 永远不能让 Claude 比"没装 hook"更糟。**三道保护**：

```python
1. CC_ANYWHERE_TAB_ID env 不存在 → echo {} 退出
   （用户在终端直接跑 claude，env 未注入 → 完全无感）
2. Unix socket 连不上 Mac App → echo {} 退出
   （Mac App 没启动 / socket 文件被删 → Claude 走 TUI fallback）
3. Python 任何异常 → safe_exit_with_empty ctx manager → echo {}
   （脚本本身 bug → 不打断 Claude）
```

`{}` 等价于 hook "无意见"，Claude SDK 按默认逻辑继续。

### 3.3 Dumb Proxy Server

历史：早期 Server 有完整的 type 路由白名单（`router.go` 内 switch case），每加一个业务 type 都要重新部署 Server。

现状：Server 只识别 **server-internal type**（bind / device / image / presence / force_disconnect / error）。所有其他 type 默认透传：

- `Mac → Phone`：任何 type 都 BroadcastToPhones
- `Phone → Mac`：任何 type 都 MacConnSend（Mac 离线 → MAC_OFFLINE 错误）

后果：

- ✅ Mac / Phone 加新协议 type、改字段、加 hook 类型都**不需要重部 Server**
- ✅ Server 只在以下情况升级：鉴权机制 / 设备管理 schema / image 流程 / 安全补丁
- ✅ Server 体积小（≈ 2.5K LOC Go）、维护轻

实现见 [Server/internal/router/router.go](../Server/internal/router/router.go)。

### 3.4 多 Tab 路由：CC_ANYWHERE_TAB_ID

挑战：一个 Mac 上多个 Tab 同时跑 claude（每 Tab 一个独立 claude 子进程），hook bridge 被 fork 时怎么知道是哪个 Tab？

方案：**Mac App 启动每个 Tab 的 claude 子进程时注入环境变量 `CC_ANYWHERE_TAB_ID=<uuid>`**。

- claude 子进程及其 fork 出的 hook bridge 进程都继承此 env
- 用户在终端直接跑 `claude` 时**没有这个 env** → hook bridge 第一步软失败放行（保护 1）

实现见 [ProcessHost.makeEnvironment](../MacClient/Sources/CCAnywhere/Services/ProcessHost.swift)。

### 3.5 Winner 锁（多端竞答）

场景：用户有多个 phone 同时在线 + Mac App 自己也有卡片，三端可能并发回答 AskUserQuestion。

方案：HookIpcServer 是 Swift `actor`，所有 `pendingRequests[reqId]` 的访问都串行化。`resolveAsk` 是唯一入口：

```swift
private func resolveAsk(...) async {
    guard var req = pendingRequests[requestId] else { return }
    if req.answered {
        // 后到的应答直接丢弃
        return
    }
    req.answered = true
    pendingRequests[requestId] = req
    // ... resume continuation + 广播 ask.question.answered
}
```

Actor 模型天然保证 winner 锁无竞态。

### 3.6 BSD Socket vs NWListener

Mac App 的 `HookIpcServer` 没用 Network.framework `NWListener.unix(...)` — macOS 上 NWListener 对 Unix domain SOCK_STREAM 监听返回 EINVAL（framework 限制：`.unix` endpoint 只支持 client 侧 `NWConnection`）。

改用 BSD `socket(2) + bind(2) + listen(2)` + `DispatchSourceRead` 实现 accept loop。详见 [HookIpcServer.swift](../MacClient/Sources/CCAnywhere/Services/HookIpcServer.swift) 顶部注释。

### 3.7 协议（WebSocket Envelope）

```json
{
  "type": "msg.stream",
  "id": "uuid",
  "ts": "2026-05-18T10:30:00Z",
  "data": { /* 任意 type-specific JSON */ }
}
```

**Server-internal type**（不透传）：

- `bind` / `bind.ack` / `bind.error`
- `ping` / `pong`
- `force_disconnect`
- `device.*`
- `image.upload.begin` / `image.upload.url` / `image.fetched` / `image.upload.expired` / `image.download.url` / `image.download.url.response`
- `presence.mac_online` / `presence.mac_offline` / `presence.phone_count`
- `error`

**业务 type**（透传，两端定义）：

- `msg.stream` / `msg.raw` / `msg.history.*`
- `tab.list` / `tab.list.*` / `tab.changed`
- `input.text` / `input.image` / `tool_use.approve`
- `ask.question.pending` / `ask.question.answer` / `ask.question.answered` / `ask.question.timeout`
- `ask.tool_approval.answer`
- `tool.progress.pre` / `tool.progress.post`
- `notification`
- 未来任何新 type，无需 Server 升级

## 4. 关键文件索引

| 关注点 | 文件 |
|---|---|
| Mac App 入口 / DI | `MacClient/Sources/CCAnywhere/App/{AppDelegate,DependencyContainer}.swift` |
| Hook 桥接 | `MacClient/Sources/CCAnywhere/Services/HookIpcServer.swift`、`MacClient/Sources/CCAnywhere/Resources/cc-anywhere-hook-bridge.py` |
| settings.json 安装 | `MacClient/Sources/CCAnywhere/Services/SettingsJsonInstaller.swift` |
| JSONL 监听 | `MacClient/Sources/CCAnywhere/Services/JSONLWatcher.swift` |
| Tab 进程管理 | `MacClient/Sources/CCAnywhere/Services/ProcessHost.swift` |
| ws 客户端 | `MacClient/Sources/CCAnywhere/Services/WSClient.swift` |
| Phone 主聊天 | `AndroidClient/lib/features/chat/chat_screen.dart` |
| Phone ask 控制器 | `AndroidClient/lib/services/ask_question_controller.dart` |
| Phone 通知 | `AndroidClient/lib/services/ask_notification_service.dart` |
| Server 路由 | `Server/internal/router/router.go` |
| Server 鉴权 | `Server/internal/auth/auth.go` |
| Server hub | `Server/internal/server/{server,hub}.go` |
| 协议常量 | `Server/internal/protocol/messages.go` |

## 5. 演进路线 / 不在范围

**不打算做**：

- 真 token 级 streaming（逐字流式 assistant 文本） — hook 不支持 `content_block_delta`，要做必须重构成 SDK 路线，会失去 Mac TUI 体验
- 跨 Mac / iOS 客户端的统一 hook 中继 — 当前只覆盖 Mac
- 多租户 SaaS — 个人工具定位
- 端到端加密 — TLS + 自托管已足够

**可能演进**：

- Linux / Windows Mac 端等价品（替换 SwiftTerm / 用 wezterm / xterm.js + Electron）
- iOS 客户端（Flutter 复用 AndroidClient）
- macOS App 上架（需要 Apple notarization + entitlements）
- Server 多语言重写（Rust / Bun.js）

## 6. 历史决策

完整的 L4 需求开发过程（含 7 个 hook type 的设计 / 三轮代码审查 / 上线研判）保存在：

[docs/AskUserQuestion远程交互/](./AskUserQuestion远程交互/)

包含：
- 产品需求文档 (PRD)
- 需求规格说明书（业务规则编号 R-F1-001 到 R-F6-004）
- 技术实施文档（含 hook bridge Python 完整伪代码 + HookIpcServer actor 接口）
- 第一/二/三轮代码审查报告 + 复审
- 上线研判报告

对外部贡献者来说**不必读完**，但想理解"为什么这么设计"时是最完整的索引。
