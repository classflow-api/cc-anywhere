---
title: 常见问题
---

# 常见问题 FAQ

## 关于项目

### 这跟 Claude Code 是什么关系？

cc-anywhere 是 [Claude Code](https://claude.com/claude-code)（Anthropic 官方 CLI）的**协作客户端**，不是它的替代品。Mac 上仍然跑原生 `claude` 子进程，cc-anywhere 是旁观 + 桥接。

### 为什么不直接用 Claude Code 自己的 web UI？

Claude Code 没有官方 web UI。竞品 [cc-connect](https://github.com/chenhg5/cc-connect) 走 SDK 路线，失去 Mac TUI 体验。cc-anywhere 用官方 Hook 机制，保留 Mac TUI + 加手机端。

### 跟 Tmux + SSH 比有什么优势？

Tmux+SSH 让你在远程 shell 看到 TUI 全屏渲染。问题：

- 手机上 TUI 渲染特别难用（90 字符宽屏幕渲染 200 字符的 Claude 输出）
- 没法决策性交互（按钮 / 卡片）
- 没法图片上传 / 系统通知

cc-anywhere 给手机的是**结构化卡片消息**（消息 / 工具调用 / 思考 / 图片），更适合移动端浏览 + 决策。

### 项目作者 / 维护者是谁？

[Beijing Yoolines Interactive Information Technology Co., Ltd. (北京友联互动信息技术有限公司)](https://yoolines.com)，旗下 ClassFlow 团队。

主要协作模式：项目大部分代码由 [Claude Code](https://claude.com/claude-code) 辅助完成（[完整开发流程文档](https://github.com/classflow-api/cc-anywhere/blob/master/docs/AskUserQuestion%E8%BF%9C%E7%A8%8B%E4%BA%A4%E4%BA%92/) 可供参考），由维护者审查 + 拍板。

## 部署

### 必须有 VPS 吗？局域网 / 本机能用吗？

可以。Server 是个普通 Go binary，可以：

- 跑在公网 VPS（最常见，手机在公网也能连）
- 跑在家庭 NAS（手机连家庭 WiFi 时可用）
- 跑在 Mac 本机（手机和 Mac 在同 WiFi）

仅限制：**必须 TLS**（不接受明文 ws）— 因为 Android 端 web socket lib 强制 wss。本机部署时用自签证书 + 客户端勾"信任自签证书"。

### 必须用 Docker 吗？

不必。Server 可以直接 `go build` 出二进制，systemd / launchd 管理即可。

### 用 ChatGPT 的 Codex / GitHub Copilot 行不行？

cc-anywhere 桥接的是 **Anthropic 的 Claude Code CLI**，依赖它的 Hook 机制（settings.json PreToolUse / PostToolUse / Notification）。其他 AI CLI（如 Codex、Aider、Cursor CLI）没有这套 hook，cc-anywhere 不能直接用。

理论上可以为别的 CLI 实现等价的桥接层（基于 stdin/stdout 拦截），不在本项目范围。

## 使用

### 我能跑多少个 Tab / 多少 Claude 同时？

技术上没限制。实际限制：

- 每个 Tab 一个 `claude -c` 子进程，吃内存（每个 ~200MB）
- Anthropic API rate limit / 并发限制
- 你 Mac 的 CPU / 内存

10 个 Tab 都开是完全可以的；100 个不推荐。

### 手机端能在多少个 phone 同时绑定？

无强制限制。Server 端按 `sub_token` 区分每个 phone 设备，可以同时 N 个 phone 在线。

AskUserQuestion 多端竞答时，**首回复 wins**，后到的应答被丢弃，winner banner 推到所有端。

### 答完 ask 之后 Mac 端弹窗能消失吗？

是。winner 锁仲裁后 Mac App 的卡片立即清空 + 显示 3 秒 "已被 X 回答" banner。

### 如果手机一直不答，Claude 会一直 hang 吗？

不会。两层超时：

- Mac App inner timeout（默认 30 分钟）→ 触发后 hook 返回 `{}` → Claude TUI **fallback** 弹原 AskUserQuestion 内置弹窗
- settings.json hook timeout 1800s（与 inner timeout 对齐）→ Claude SDK 自己处理超时

降级**永远是优雅的**，不会真 hang。

## 协议 / 架构

### Server 怎么知道哪些 type 该转发？

Server 走 **dumb proxy** 设计：除了 server-internal type（鉴权 / device / presence / image / error），所有其他 type 默认透传：

- Mac → Phone：BroadcastToPhones
- Phone → Mac：MacConnSend

加新业务 type **不需要重新部署 Server**。详见 [ARCHITECTURE.md §3.3](/guide/architecture#33-dumb-proxy-server)。

### 我能自己加新 type 吗？

可以。Mac App `ProtocolMessage.swift` 加 Codable struct + 任一端 send + 另一端 inbound switch case。Server 完全不需要改。

### 协议会破坏向后兼容吗？

不会强制破坏。新 type 加上不影响旧版客户端（旧端按"未识别 type" 静默丢弃）。

如果改既有 type 字段名 / 必填，会标在 CHANGELOG 的 BREAKING 区。

## 安全

### 我的对话内容会上传到你们的服务器吗？

**不会**。Server 是你自己部署在自己 VPS 上的，cc-anywhere 项目方（ClassFlow）不运营任何中心服务器。

Claude API 调用：直接 Mac → Anthropic API，cc-anywhere 不经手。

### Master Token 丢了能恢复吗？

不能恢复，只能重置：

```bash
docker exec cc-anywhere /usr/local/bin/cc-anywhere admin reset-master-token --force
```

重置后所有已绑定的 phone 也会失效，需要重新扫码绑定。

### 第三方能在我 master token 失窃的情况下做什么？

最多能：
- 假冒成你的 Mac 端连接 Server
- 推假消息给你的所有 phone
- 控制 Server 撤销 phone 绑定

不能：
- 看到你的对话内容（Server 不存对话）
- 在你的 Mac 上跑 Claude（Hook 桥接只是 Server → Mac App 的本地链路）

发现 master token 失窃 → 立即 reset-master-token。

### 别人能扫别人家的 binding 二维码吗？

QR 码内含一次性 sub_token（HMAC 签名）+ Server URL。任何人扫码后会成为该 Mac 的绑定 phone。**所以 QR 码不要随便截屏分享**。

如果误绑了，Mac App 偏好 → 设备管理 → 撤销该 sub_token。

## 故障排查

更多见 [INSTALL.md - 故障排查](/guide/installation#故障排查) 章节。

### Mac App 启动后 Dock 名字是 "CCAnywhere" 不是"遥指"

请用 `bash MacClient/build_app.sh release` 打包出 `遥指.app` 后启动，不要直接跑裸 binary `.build/<config>/CCAnywhere`。裸 binary 没有 .app Bundle 的 Info.plist，所以 Dock / launcher 没法读到中文显示名。

### Phone 进 App 后没自动滚到底部

应该会。如果没有：

- 等 0.5 秒再看（消息异步加载，初始滚动有 retry 机制）
- 仍然没动 → 提 issue 附 phone 端日志（adb logcat 抓 `flutter` 标签）

### "Claude TUI 仍然弹原 AskUserQuestion 弹窗"

证明 hook 链路出问题或主动降级。按 [INSTALL.md 故障排查](/guide/installation#claude-tui-仍然弹原-askuserquestion-弹窗)。

## 开发

### 我贡献了代码会有 CLA / DCO 要求吗？

无。MIT License 下 PR 提交即默认授权。

### 我能不能商用？

可以。MIT License 允许商业使用 / 修改 / 二次分发。保留 LICENSE 中的著作权声明即可。

### 我想 fork 一份改成支持别的 CLI（Codex / Aider / etc.）

欢迎！本项目核心是"Claude Code Hook 桥接"，换成别的 CLI 需要替换 hook 实现层。基础架构（Mac App tab 管理 / phone 端 UI / Server dumb proxy）大部分能复用。

---

没解决你的问题？请到 [Issues](https://github.com/classflow-api/cc-anywhere/issues) 搜一下或开新 issue。
