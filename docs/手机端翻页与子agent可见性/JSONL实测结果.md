# JSONL 实测结果（任务 0 产出）

> 日期：2026-05-19
> 实测样本：`~/.claude/projects/-Users-liangliyu-project-classflow/` 真实 Task subagent 调用

## 实测 1：agent-*.jsonl 文件名规则

**结论**：文件名格式 = `agent-<agentId>.jsonl`，agentId 是 **7 字符 hex hash**（如 `a1cce99`），存于 record 的 `agentId` 字段。

agentId 与父 Task tool_use_id（如 `toolu_01JSjxaSxbLxGYBzuc7twnL4`）**没有可见的语法映射**。

## 实测 2：agent-*.jsonl record 字段

第一条 record 字段：

```json
{
  "parentUuid": null,            // 首条无父
  "isSidechain": true,           // ✓ 区分主 vs 子
  "userType": "external",
  "cwd": "/Users/liangliyu/project/classflow",
  "sessionId": "<独立 uuid>",     // 子 agent 独立 sessionId
  "version": "2.0.77",
  "gitBranch": "main",
  "agentId": "a1cce99",          // ✓ 与文件名后缀一致
  "type": "user",
  "uuid": "<message uuid>",
  "timestamp": "2026-05-09T02:28:50.292Z",
  "message": { "role": "user", "content": "<prompt 原文>" }
}
```

**关键**：

- **没有** `parentToolUseId` / `parent_tool_use_id` 字段
- **agentId** 是 sidechain 内的唯一标识
- **首条 message.content** = 父 Task tool_use 的 `input.prompt`（**这是唯一可靠的父子关联线索**）

## 实测 3：父 session 中的 Task tool_use

```json
{
  "type": "tool_use",
  "name": "Task",
  "id": "toolu_01JSjxaSxbLxGYBzuc7twnL4",
  "input": {
    "subagent_type": "general-purpose",
    "description": "...",
    "prompt": "项目要做权限体系改造..."
  }
}
```

时间对照：

- 父 Task tool_use ts: `2026-05-09T02:28:50.263Z`
- agent-a1cce99.jsonl 首条 ts: `2026-05-09T02:28:50.292Z`（**晚 29ms**）

## 实测 4：Hook stdin & permission mode 继承

**实测 4 未跑（需触发实际 Claude 进程）**。按推理：

- Hook bridge 是父 claude 子进程 fork 的子进程，**CC_ANYWHERE_TAB_ID env 必然继承**
- HookIpcServer.handleAsk 的 auto-allow 走 `tabRouter.permissionMode(forTabIdString:)`，查的是父 tab 的 mode → **permission mode 继承默认成立**

R-F7-001：开发期补一次集成测试触发验证，**默认按已成立设计**，不写代码改动。

---

## 决策结论与代码路径影响

### 决策 A：parentToolUseId 提取路径

**走"两阶段内容匹配"机制**：

1. JSONLWatcher 在父 session.jsonl 看到 Task tool_use → 记录 `(toolUseId, promptHash, ts)` 到 `pendingTaskMatches`
2. JSONLWatcher 在 agent-X.jsonl 看到首条 user message → 提取 content 算 `promptHash` → 跟 `pendingTaskMatches` 匹配（promptHash 相等 + ts 相邻 5 秒内）
3. 匹配成功 → 建立 `agentId → parentToolUseId` 双向映射，把映射写入 activeSubAgents 索引；并把 parentToolUseId 注入后续所有 agent-X 的 msg.stream payload

**Race 处理**：

- 子 agent 首条比父 Task tool_use 晚 29ms 到达是常态
- 但 FSEvents 触发顺序不保证一致 — 可能 agent-X 文件先被监听到
- pendingAgentMatches 与 pendingTaskMatches 双 buffer 互查（任一方先到，另一方到达时 match）
- 30 秒超时 → 孤儿 agentId（仍可显示折叠块但无 parentToolUseId 链接）

### 决策 B：协议字段调整

技术实施文档 §4.1 原设计 `parentToolUseId` 字段保留，**新增** `agentId` 字段：

- mac 端透传 agentId（便于手机端按 agentId 聚合，作为 parentToolUseId 的 fallback key）
- 手机端 ChatRepository 聚合优先级：`parentToolUseId` > `agentId`（前者关联到主流的 Task 折叠块，后者作为独立子 agent 块）

### 决策 C：hook tool_approval 上下文反查

`HookIpcServer.handleAsk` 中按 `req.sessionId`（hook stdin 的 sessionId 字段）查 `activeSubAgents[tabId]` 中对应的 SubAgentMeta（matchKey: `agentSessionId == sessionId`）。

这要求 JSONLWatcher 在监听 agent-X.jsonl 时把首条 record 的 sessionId 填入 SubAgentMeta.agentSessionId。

### 决策 D：permission mode 继承

R-F7 默认成立，不写代码。开发阶段补一次集成测试验证（详见后续 R-F7-001）。

---

## 技术实施文档 §4.1 / §4.2 同步更新点

**§4.1 协议字段补丁**：

```swift
public struct MsgStreamPayload: Codable {
    // ... 现有
    public let sessionId: String?
    public let parentUuid: String?
    public let isSidechain: Bool?
    public let parentToolUseId: String?
    public let agentId: String?   // ⊕ 新增：子 agent 短 hash，sidechain 内唯一

    // CodingKeys 加 case agentId = "agent_id"
}
```

**§4.2 JSONLWatcher 实现补丁**：

```swift
// SubAgentMeta 加 promptHash 字段
public struct SubAgentMeta {
    let parentToolUseId: String?     // 匹配成功才有，未匹配可能 nil
    let agentId: String              // 始终有
    let agentSessionId: String       // agent-X.jsonl 内 record.sessionId
    let promptHash: String           // 用于匹配
    let promptSummary: String        // 截断 60 字符 - tool_approval chip
    let createdAt: Date
}

// pendingTaskMatches: 父 Task tool_use 等子 agent 出现
private var pendingTaskMatches: [String /* promptHash */: (toolUseId: String, ts: Date)] = [:]
// pendingAgentMatches: 子 agent 等父 Task tool_use 出现
private var pendingAgentMatches: [String /* promptHash */: (agentId: String, ts: Date)] = [:]

// 接收父 session Task tool_use 时
func onTaskToolUse(toolUseId: String, prompt: String, ts: Date) {
    let hash = sha1(prompt)
    if let pending = pendingAgentMatches.removeValue(forKey: hash) {
        // 子已在等 → 建立映射
        finalizeMatch(toolUseId: toolUseId, agentId: pending.agentId, hash: hash)
    } else {
        // 暂存等子到达
        pendingTaskMatches[hash] = (toolUseId, ts)
        scheduleTimeout(hash, 30)
    }
}

// 接收 agent-X.jsonl 首条时
func onAgentFirstMessage(agentId: String, firstContent: String, sessionId: String, ts: Date) {
    let hash = sha1(firstContent)
    if let pending = pendingTaskMatches.removeValue(forKey: hash) {
        finalizeMatch(toolUseId: pending.toolUseId, agentId: agentId, hash: hash)
    } else {
        pendingAgentMatches[hash] = (agentId, ts)
        scheduleTimeout(hash, 30)
    }
}
```

---

## 风险提示（更新到 PRD R 列表）

- **新增 R**：promptHash 匹配失败的场景 — 比如 Claude 内部对 prompt 做了 truncation 才落盘到 agent-X.jsonl 首条，导致内容跟父 Task tool_use 的 input.prompt 不完全一致
- **缓解**：实际样本验证两侧内容完全一致（实测 3 已验证）；如未来 Claude SDK 改变行为，用前 N 字符 hash 容错
