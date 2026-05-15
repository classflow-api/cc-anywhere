# L4 待开发需求 — Hook 实时桥接基础设施

> **需求级别**:L4 - 中大型需求
> **预估工作量**:5-7 人日(包含 AskUserQuestion + 工具进度推送 + 通知推送 三个能力)
> **建议优先级**:P0(影响 cc-anywhere 远程协作核心定位)
> **依赖**:已完成的 L2 修复(零散需求 #1-#37)
> **创建日期**:2026-05-15

---

## 1. 需求背景

零散需求批次完成后,验收测试([测试指引](../手机端消息类型全覆盖测试/测试指引.md))暴露 cc-anywhere 当前架构的核心限制:

- **AskUserQuestion 决策只能在 Mac 端做**(手机端只看到事后记录)
- **长文本/工具进度无实时反馈**(手机端傻等到 JSONL 落盘才看到结果)

根因:cc-anywhere 当前是 **JSONL 旁观者** 架构,JSONL 在 Claude 完成一段完整 message / 工具调用 / SDK 暂停回调答完之后才落盘。手机端拿到的永远是事后历史。

研究 [Claude Code Agent SDK Hooks 机制](https://code.claude.com/docs/en/agent-sdk/hooks) 后发现,Claude CLI **原生支持** 通过 `~/.claude/settings.json` 注册 PreToolUse 等 hook,且这些 hook **同步阻塞** 直到返回 — 这是绕过 JSONL 滞后、实现"实时桥接"的关键。

---

## 2. 需求目标(产品视角)

让手机端真正成为"远程决策端",而不只是"事后查看器":

| 能力 | 改善前(当前) | 改善后(本需求) |
|---|---|---|
| AskUserQuestion 决策 | ❌ Mac 端做完才推手机查看记录 | ✅ Claude 提问的**瞬间**手机弹问题卡片,手机选项即决策 |
| 工具调用进度 | ❌ JSONL 落盘后才知道发生了 | ✅ "Claude 正在 Read xxx.md"、"正在执行 bash" 实时显示在手机 |
| 待批准的 Bash/Write | ❌ Mac 端弹"是否允许"对话框,手机看不到 | ✅ 危险操作权限请求直接推手机,远程批准/拒绝 |
| Claude 状态变化 | ❌ 只能看消息流推断 | ✅ "Claude idle / 等待用户输入" 等系统通知实时可见 |

---

## 3. 技术方案

### 3.1 总架构

```
Mac 端
┌──────────────────────────────────────────────────────────┐
│  Claude CLI (TUI 模式 — 用户照常 typing)                  │
│       ↓ Claude SDK 内部触发 hook                          │
│  PreToolUse / Notification / PostToolUse hook 命令脚本    │
│  (`~/.local/bin/cc-anywhere-hook-bridge`)                │
│       ↓ Unix socket IPC                                   │
│  cc-anywhere Mac App (Hook IPC Server)                   │
│       ↓ ws                                                │
└──────────────────────────────────────────────────────────┘
                                ↓ wss
                          ┌─────────────┐
                          │  Server     │
                          └─────────────┘
                                ↓ wss
┌──────────────────────────────────────────────────────────┐
│ Phone 端                                                  │
│  接收 ask.question.pending → 弹交互卡片                  │
│  接收 tool.progress → 显示"正在 Read xxx"             │
│  用户选项 → 发 ask.question.answer 回 Server → Mac       │
│  Mac IPC server → hook 脚本 → SDK 继续                  │
└──────────────────────────────────────────────────────────┘
```

### 3.2 hook 配置(用户 settings.json)

Mac App 启动时自动写入(用户允许后):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "AskUserQuestion",
        "timeout": 1800,
        "hooks": [
          { "type": "command",
            "command": "/usr/local/bin/cc-anywhere-hook-bridge ask" }
        ]
      },
      {
        "matcher": "Bash|Write|Edit",
        "timeout": 600,
        "hooks": [
          { "type": "command",
            "command": "/usr/local/bin/cc-anywhere-hook-bridge progress pre" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": ".*",
        "hooks": [
          { "type": "command",
            "command": "/usr/local/bin/cc-anywhere-hook-bridge progress post" }
        ]
      }
    ],
    "Notification": [
      {
        "hooks": [
          { "type": "command",
            "command": "/usr/local/bin/cc-anywhere-hook-bridge notification" }
        ]
      }
    ]
  }
}
```

### 3.3 Hook bridge 脚本职责

单一脚本,通过 subcommand 复用通道:

| 子命令 | 行为 | 阻塞? |
|---|---|---|
| `ask` | 把 questions 通过 Unix socket POST 给 Mac App,阻塞等 answers,输出 `{hookSpecificOutput: {permissionDecision: "allow", updatedInput: {questions, answers}}}` | ✅ 是,直到 phone 答 |
| `progress pre` | 把 `{tool_name, tool_input}` async POST 给 Mac App(only logging,不影响决策),立即返回 `{}` | ❌ 否 |
| `progress post` | 把 `{tool_name, tool_input, tool_output}` async POST,立即返回 `{}` | ❌ 否 |
| `notification` | 转发 notification message,立即返回 `{}` | ❌ 否 |

### 3.4 协议新增

| 协议 type | 方向 | payload |
|---|---|---|
| `ask.question.pending` | server → phone | `{ request_id, tab_id, questions: [...] }` |
| `ask.question.answer` | phone → server → mac | `{ request_id, answers: { question: label, ... } }` |
| `ask.question.timeout` | server → phone | `{ request_id, reason }`(超时通知 UI 撤销卡片)|
| `tool.progress.pre` | mac → server → phone | `{ tab_id, tool_use_id, tool_name, tool_input }` |
| `tool.progress.post` | mac → server → phone | `{ tab_id, tool_use_id, tool_name, success, error? }` |
| `notification` | mac → server → phone | `{ tab_id, type, title, message }` |

### 3.5 Mac App Hook IPC Server

新组件 `HookIpcServer.swift`(约 200 行):

- 监听 `~/Library/Application Support/cc-anywhere/hook.sock`
- 收到 `ask` 请求:
  1. 生成 `request_id`
  2. 通过 ws 发 `ask.question.pending` 广播给所有 phone
  3. 在内存登记 `request_id → continuation`
  4. 收到 `ask.question.answer` 时 resolve continuation,把 answers 通过 socket 写回 hook 进程
  5. 超时 / phone 全离线 → 写 timeout error 给 hook,hook 输出 deny 决策
- 收到 `progress pre/post`:直接 ws 推 phone(不阻塞)
- 收到 `notification`:直接 ws 推 phone

### 3.6 Phone 端 UI

- **AskUserQuestionCard**(已有,改造)— 接收 `ask.question.pending` 时**主动弹出**(不依赖 JSONL),首个回复 wins,后续 phone 显示"已被回答"
- **ToolProgressIndicator**(新)— 在消息列表底部显示"正在执行 Read /xxx" 进度条,PostToolUse 收到后消失
- **NotificationToast**(新)— Notification 类事件用 snackbar/toast 提示(idle / permission_prompt 等)

### 3.7 错误处理 & 兼容

| 场景 | 行为 |
|---|---|
| Phone 全部离线 | hook 等待 `prefer_remote_timeout` 后 deny,Claude 自行处理 |
| 第一个 phone 回复后,第二个还在选 | 第二个 phone 卡片显示"已被 X 回答(label)" |
| hook 脚本崩溃 | settings.json 不会让 SDK 死,SDK 走 fallback(原 TUI 弹问题/弹批准) |
| 用户不希望开启远程接管 | Mac App 偏好里"启用远程 hook"开关,关闭时自动卸载 settings.json 里 cc-anywhere 那几条 |
| 多 tab(同时多 Claude 实例) | hook input 含 `cwd / session_id`,Mac App 通过 cwd 反查 tab_id,推给该 tab 对应 phone |

---

## 4. 阶段拆解(增量交付)

每个阶段独立可用,**每阶段都是一个可上线的 milestone**:

### M1 — Hook 基础设施 + AskUserQuestion(3-4 人日)
- [ ] cc-anywhere-hook-bridge 脚本(Python/Go,~200 行)
- [ ] Mac App HookIpcServer
- [ ] settings.json 自动注册/卸载逻辑 + 偏好开关
- [ ] 协议 `ask.question.pending` / `ask.question.answer` / `ask.question.timeout`
- [ ] Phone 端 AskUserQuestionCard 改造为实时模式
- [ ] 验证:30 分钟 echo hook 实验先做,再开始
- [ ] 测试:Mac 触发 AskUserQuestion → phone 端 ≤1s 内弹卡片 → 选项 → Claude 收到 → 继续

### M2 — 工具进度推送(1.5-2 人日)
- [ ] hook bridge `progress pre/post` 子命令
- [ ] 协议 `tool.progress.pre/post`
- [ ] Phone 端 ToolProgressIndicator widget
- [ ] settings.json 增加 PostToolUse 的 .* matcher

### M3 — Notification 推送(0.5-1 人日)
- [ ] hook bridge `notification` 子命令
- [ ] 协议 `notification`
- [ ] Phone 端 NotificationToast

### M4 — 危险工具远程批准(可选,1-2 人日)
- [ ] PreToolUse hook 的 Bash/Write 走 ask 通道
- [ ] 复用 AskUserQuestionCard 渲染"是否允许 `bash -c ...`"
- [ ] 用户选 allow/deny → hook 返回相应 permissionDecision

---

## 5. 验证清单(M1 上线条件)

- [ ] 30 分钟前置验证:settings.json 写 echo hook,触发 AskUserQuestion 后日志写入 → 证明路径打通
- [ ] M1 端到端:Mac 端跑 `用 AskUserQuestion 问我喜欢什么颜色` → phone 弹卡片 → 选"蓝色" → Claude 收到 → 继续对话
- [ ] phone 离线时 hook 走 timeout 路径 → Claude 收到 deny,自然继续
- [ ] 关闭 Mac App "启用远程 hook" 开关 → settings.json 中 cc-anywhere 那几条被卸载,Claude TUI 恢复内置弹窗
- [ ] 多 phone 时,首个回复 wins,其他 phone 显示"已被回答"
- [ ] 跟现有 yoolines-dev-workflow / superpowers 等 plugin 的 hook 不冲突(共存,按 array append)

---

## 6. 风险与开工前验证

### 关键风险 — Claude CLI TUI 模式是否真触发 settings.json hook?

证据(强):
- yoolines-dev-workflow / superpowers / episodic-memory 等 plugin 已经通过 settings.json hooks 工作,用户日常在用 — 证明 Claude CLI **会**执行 settings hooks
- Claude Code Hooks 文档明确说 settings.json hooks 跟 SDK callback hooks 等价

但 AskUserQuestion 触发的具体回路(canUseTool ↔ settings hook 优先级)在文档中没明示,**建议开工前先做 30 分钟 echo 实验**:

```bash
mkdir -p /tmp/cc-anywhere-hook-test
cat > /tmp/cc-anywhere-hook-test/echo.sh <<'EOF'
#!/bin/bash
input=$(cat)
echo "$(date +%H:%M:%S) $input" >> /tmp/cc-anywhere-hook-test/log.txt
echo '{}'
EOF
chmod +x /tmp/cc-anywhere-hook-test/echo.sh
```

加入 `~/.claude/settings.json`(临时):
```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "AskUserQuestion",
        "hooks": [{ "type": "command", "command": "/tmp/cc-anywhere-hook-test/echo.sh" }] }
    ]
  }
}
```

在任意 Claude session 让 Claude 调 `AskUserQuestion`,看 `/tmp/cc-anywhere-hook-test/log.txt` 是否写入。

- ✅ 写入 → 完全打通,可以 M1 开工
- ❌ 没写入 → 需要进一步研究 SDK vs CLI hook 加载差异(可能要用 `claude --setting-sources user`)

### 次要风险

| 风险 | 对策 |
|---|---|
| Hook timeout 60s 默认不够 | settings.json 设 `timeout: 1800`(30 分钟) |
| Phone 全部离线 | Mac App 端设 5 分钟 inner timeout,超时 deny |
| 用户不想被打断 TUI | 偏好开关 + 一键卸载 settings.json |
| Plugin hook 冲突 | append 模式,不覆盖现有数组 |
| hook 进程数过多 | hook bridge 用 Unix socket,Mac App 是单 instance,无 fork |

---

## 7. 后续 / 不在本需求范围

- **真 token 级 streaming**(逐字流式 assistant 文本)— hook 不支持 content_block_delta,必须重构成 SDK 路线(失去 TUI)。本需求**不包含**。
- **跨 Mac/iOS 客户端的统一 hook 中继**(本需求只针对 cc-anywhere Mac 客户端)

---

## 8. 参考资料

- [Claude Code Agent SDK - Hooks](https://code.claude.com/docs/en/agent-sdk/hooks)
- [Claude Code Agent SDK - Handle approvals and user input](https://code.claude.com/docs/en/agent-sdk/user-input)
- [Claude Code Hooks JSON Reference](https://code.claude.com/docs/en/hooks)
- 已完成的 L2 修复批次:`docs/零散需求/需求修改报告-2026-05-15.md`
- 验收报告:`docs/手机端消息类型全覆盖测试/验收报告.md`
- 可行性评估初稿:`docs/AskUserQuestion远程交互/可行性评估.md`
