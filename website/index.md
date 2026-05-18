---
layout: home

hero:
  name: 遥指
  text: 跨端 Claude Code 协作客户端
  tagline: Mac 跑长任务，手机随时接管 — 基于 Claude Code 原生 Hook 实时桥接
  image:
    src: /hero-illustration.svg
    alt: cc-anywhere
  actions:
    - theme: brand
      text: 快速开始
      link: /guide/quick-start
    - theme: alt
      text: 完整安装
      link: /guide/installation
    - theme: alt
      text: GitHub
      link: https://github.com/classflow-api/cc-anywhere

features:
  - icon: 🪟
    title: Mac 多 Tab 工作区
    details: 每个 Tab 绑一个本地项目目录，自动 claude -c 恢复对话。一窗口管多个长任务。
  - icon: 📲
    title: 手机结构化卡片
    details: 把 Claude 的 JSONL 解析成消息流（文本 / 工具调用 / 思考 / 图片），不是 TUI 复刻。
  - icon: ⚡
    title: AskUserQuestion 实时桥接
    details: Claude 提问 → 手机端 ≤ 1 秒弹卡片。任一端答都 winner-lock 仲裁。
  - icon: 🛡️
    title: 危险工具远程批准
    details: Claude 想跑 rm -rf / Write / Edit → 推手机批准。安全又不影响节奏。
  - icon: 🔔
    title: 系统级通知
    details: 手机锁屏 / 不在 App 内也能收到震动 + 抬头提醒，重要决策不错过。
  - icon: 🪝
    title: Native Hook 桥接
    details: 用 Claude Code 官方 Hook 机制，不重新实现 SDK，不破坏原生 TUI 体验。
  - icon: 🔌
    title: Dumb Proxy Server
    details: 业务协议两端自定义，Server 只做鉴权 + 设备发现 + 透传。部署一次永久跑。
  - icon: 🔒
    title: 自托管 + TLS
    details: 装在你自己 VPS 上，对话内容不经手任何第三方。HMAC + 设备绑定 sub-token。
---

<style>
.VPHero .name {
  background: linear-gradient(135deg, #59CFE7 0%, #4F7BE6 100%);
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}
</style>

<div style="max-width: 960px; margin: 64px auto 0; padding: 0 24px;">

## 一图看懂

```
  ┌─────────────────┐       ┌──────────────┐       ┌─────────────────┐
  │   Mac Client    │ ◄───► │ Dumb Proxy   │ ◄───► │ Android Client  │
  │   (SwiftUI)     │  wss  │ (Go)         │  wss  │  (Flutter)      │
  │ Claude Code     │       │ TLS + HMAC   │       │ 卡片 + 实时通知  │
  │ + Hook Bridge   │       │ 不解析业务   │       │                 │
  └─────────────────┘       └──────────────┘       └─────────────────┘
       本地 PTY                你的 VPS               iOS/Android
```

## 30 秒了解

```bash
# 1. VPS 上启动 Server（一次性，永久跑）
docker run -d --name cc-anywhere -p 8443:8443 \
  -v $PWD/config:/etc/cc-anywhere:ro \
  -e CC_HMAC_SECRET=$(openssl rand -hex 32) \
  cc-anywhere:latest

# 2. Mac 上启动遥指（拖到 /Applications）
open '/Applications/遥指.app'

# 3. 手机扫码绑定，从此 Claude 跑哪里你都知道
```

[📖 完整安装指南 →](/guide/installation)　[🏗️ 架构深入 →](/guide/architecture)　[💬 加入讨论 →](https://github.com/classflow-api/cc-anywhere/discussions)

</div>
