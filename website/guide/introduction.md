# 介绍

**遥指（cc-anywhere）** 是一个为 [Claude Code](https://claude.com/claude-code) 量身设计的跨端协作客户端：让你在 Mac 上跑长时间的 Claude Code 任务，同时通过手机端实时跟进、回答 Claude 的提问、批准危险工具调用。

## 适用场景

::: tip 典型工作流
你启动了一个会跑 1 小时的 Claude Code 任务（重构、批量改、研究、调试），合上 Mac 走开。Claude 中途有问题就在手机上弹卡片让你回答，跑完了你回家发现任务已经做完。
:::

- ✅ **长任务期间走开**：去吃饭 / 上厕所 / 坐地铁，Claude 卡在 AskUserQuestion 的时候不再傻等
- ✅ **远程批准危险操作**：Claude 想 `rm -rf` / Write / Edit 危险路径时，推手机让你决策
- ✅ **多 Tab 并发**：Mac 同时开多个 Claude 工作区，每个 Tab 互不阻塞
- ✅ **回看长输出**：手机端结构化消息流（不是 TUI 复刻），适合移动端浏览长 reasoning

## 这不是什么

- ❌ **不是另一个 Claude TUI 端口** — Mac 上仍然跑 Anthropic 官方 CLI，遥指是旁观 + 桥接
- ❌ **不是 web Claude.ai 复刻** — 这是面向 Claude Code 重度用户的开发者工具
- ❌ **不是商业 SaaS** — 完全自托管，对话内容不上传任何第三方
- ❌ **不是多人协作工具** — 个人开发者定位，不做多租户

## 与同类项目对比

| 维度 | 遥指 cc-anywhere | tmux + SSH | cc-connect |
|---|---|---|---|
| Mac 端 Claude TUI 体验 | ✅ 保留原生 | ✅ 保留 | ❌ 失去（SDK 路线） |
| 手机端体验 | ✅ 结构化卡片 | ❌ TUI 渲染（移动端难用） | ✅ IM 风格 |
| 远程回答 AskUserQuestion | ✅ 实时弹卡 + winner lock | ⚠️ 直接键入 TUI | ✅ |
| 远程批准危险工具 | ✅ M4 红色徽章卡 | ❌ | ⚠️ |
| 系统级通知（锁屏可见） | ✅ flutter_local_notifications | ❌ | ❌ |
| 自托管 | ✅ 自有 VPS | ✅ SSH 自己服务器 | ⚠️ 各家方案不同 |
| 协议演进 | ✅ Server 是 dumb proxy，加新 type 不重部 | N/A | N/A |

## 核心设计原则

1. **不破坏 Claude TUI 原生体验** — Mac 上用户照常 typing claude，遥指是旁观 + 桥接
2. **无 Mac 端 daemon** — App 退出 = 杀子进程 + 断 ws，重启自动恢复
3. **手机端是结构化 viewer + 决策端** — 卡片消息流，不是 TUI 复刻
4. **Server 长期不动** — dumb proxy，加新协议 type 不要求重部 Server
5. **Hook 软失败永远优雅** — hook bridge 任何异常都不能比"没装 hook"更糟

详细的架构原理 → [架构](/guide/architecture)

## 技术栈

| 端 | 语言 | 框架 | 核心依赖 |
|---|---|---|---|
| **Mac Client** | Swift 5.9 | AppKit + SwiftUI | [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)（系统 PTY） |
| **Android Client** | Dart 3.3 | Flutter | Riverpod / flutter_local_notifications |
| **Server** | Go 1.21 | 标准库 | nhooyr.io/websocket / SQLite |
| **Hook Bridge** | Python 3 | macOS 系统预装 | 仅标库 |

## 项目状态

当前版本：**v0.1.0**（首个开源版本）

::: warning 实验阶段
项目刚刚开源，部分边界场景未充分压测。建议：
- 个人开发场景使用
- 不要装在共享 Mac 上
- 不要在 master_token 失窃后还继续使用（立即 reset）

欢迎 [issue 反馈](https://github.com/classflow-api/cc-anywhere/issues) 与 PR 贡献。
:::

## 下一步

- 📦 [快速开始](/guide/quick-start) — 30 分钟跑起三端
- 🛠️ [完整安装](/guide/installation) — 含 TLS / 故障排查
- 🏗️ [架构](/guide/architecture) — 理解 Hook 桥接 + Dumb Proxy
- 💡 [常见问题](/guide/faq) — 部署 / 协议 / 安全
