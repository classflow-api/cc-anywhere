<div align="center">

# 遥指 · cc-anywhere

**跨端 Claude Code 协作客户端 — Mac 跑长任务，手机随时接管**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![macOS](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)](./MacClient)
[![Android](https://img.shields.io/badge/Android-12%2B-3DDC84?logo=android&logoColor=white)](./AndroidClient)
[![Go](https://img.shields.io/badge/Server-Go%201.21%2B-00ADD8?logo=go&logoColor=white)](./Server)

简体中文 ｜ [English](./README.en.md)

</div>

---

## 📱 这是什么

**遥指（cc-anywhere）** 让你在 Mac 上跑 [Claude Code](https://claude.com/claude-code) 长任务，同时通过手机端实时跟进、回答提问、批准危险工具调用。

- **场景**：你启动了一个会跑 1 小时的 Claude Code 任务（重构、批量改、研究），走开喝咖啡、上厕所、坐地铁，Claude 中途有问题就在手机上弹卡片让你回答
- **不是**：另一个 Claude TUI 复刻，不是网页版 Claude.ai，不是商业 SaaS
- **定位**：个人开发者工具，自托管 + 自有 VPS

## ✨ 核心特性

- 🪟 **Mac 端多 Tab 工作区**：每个 Tab 绑一个本地项目目录，自动 `claude -c` 恢复对话
- 📲 **手机端结构化卡片**：解析 Claude 的 JSONL 输出为消息流（文本 / 工具调用 / 图片 / 思考），不是 TUI 直接渲染
- ⚡ **AskUserQuestion 实时桥接**：Claude 提问 → 手机端 < 1 秒弹卡片 → 任一端答都 winner-lock 仲裁
- 🛡️ **危险工具远程批准**（M4）：Claude 想跑 `rm -rf` / Write / Edit → 推手机批准对话框
- 🔔 **系统级通知**：即便手机锁屏 / 不在 App 内也能收到震动 + 抬头提醒
- ⌨️ **手机端文字输入 + 图片上传**：继续对话，跨设备无缝
- 🪝 **基于 Claude Code 官方 Hook 机制**：不重新实现 SDK，不破坏原生 TUI 体验
- 🔌 **Dumb Proxy Server**：业务协议两端自定义，Server 只做鉴权 + 设备发现 + 透传，部署一次永久跑

## 📸 截图

> 截图占位（待补）。运行体验：Mac 端类似终端多 Tab + 偏好 + 设备管理；手机端类似 IM 卡片消息列表 + AskUserQuestion 弹层卡片。

| Mac 客户端 | 手机端 |
|---|---|
| _（main window screenshot）_ | _（chat screen screenshot）_ |
| _（ask question card）_ | _（system notification）_ |

## 🏗️ 架构

```
┌───────────────────────────────────────────┐
│  Mac App  (Swift + SwiftUI + SwiftTerm)   │
│   ├── ProcessHost: 每 Tab 一个 claude 子进程
│   ├── JSONLWatcher: FSEvents 监听 ~/.claude/projects
│   ├── HookIpcServer: Unix socket 接 Claude hook
│   └── WSClient: wss 上行 server
└───────────────────────────────────────────┘
                    ↑↓ wss + TLS
┌───────────────────────────────────────────┐
│  Server  (Go, "dumb proxy" 哑代理)         │
│   ├── auth: HMAC + master_token / sub_token
│   ├── device: phone 设备绑定 + 撤销
│   ├── image: 临时图片上传/下载中转
│   ├── presence: mac_online / phone_count 广播
│   └── router: 业务消息默认透传，加新 type 不需重部
└───────────────────────────────────────────┘
                    ↑↓ wss + TLS
┌───────────────────────────────────────────┐
│  Android App  (Flutter + Riverpod)        │
│   ├── ChatRepository: ws → 消息流
│   ├── AskQuestionController: 实时 ask 卡片
│   ├── AskNotificationService: 系统通知
│   └── DedupService: tool_use_id 去重
└───────────────────────────────────────────┘
```

详细架构 → [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md)

## 🚀 快速开始

### 三端都跑起来需要

1. 一台 Mac（macOS 14+）+ 装好 [Claude Code CLI](https://docs.claude.com/claude-code)
2. 一台 Android 手机（API 29+，Android 10+）或模拟器
3. 一台 VPS（任意 Linux，支持 Docker 即可，建议域名 + TLS）

### 部署 Server（一次性，永久跑）

```bash
# 在 VPS 上
git clone https://github.com/classflow-api/cc-anywhere.git
cd cc-anywhere/Server          # ← 后续命令都在 Server/ 目录下运行

# 1. 配置
cp config/config.yaml.example config/config.yaml
nano config/config.yaml         # 把 public_host 改为你的域名:端口

# 2. 准备 TLS 证书（Let's Encrypt 或自签）
mkdir -p config/tls
# 把 cert + key 放进 host 上的 config/tls/cert.pem 和 config/tls/key.pem
# config.yaml 里写的 /etc/cc-anywhere/tls/... 是容器内路径，**不要改**
# Docker 挂载 host 的 ./config/ 到容器内 /etc/cc-anywhere/，详见下方说明

# 3. HMAC secret
export CC_HMAC_SECRET=$(openssl rand -hex 32)
echo "CC_HMAC_SECRET=$CC_HMAC_SECRET" > .env

# 4. 构建镜像（确保此时 cwd 是 Server/，含 Dockerfile）
docker build -t cc-anywhere:latest .

# 5. 启动容器
docker run -d --name cc-anywhere --restart unless-stopped \
  -p 8443:8443 \
  -v $PWD/config:/etc/cc-anywhere:ro \
  -v cc-data:/var/lib/cc-anywhere \
  --env-file .env -e TZ=Asia/Shanghai \
  cc-anywhere:latest

# 6. 生成 master token（一次，记下来给 Mac App 用）
docker exec cc-anywhere /usr/local/bin/cc-anywhere admin reset-master-token --force
```

::: details 📁 Docker 卷挂载对照表（必看 — 防止 TLS 找不到）

`config.yaml` 里的路径是**容器内**视角，跟 host 上的真实文件夹通过 `-v` 映射：

| 容器内（config.yaml 写的） | Host 上（你 mkdir / 放文件的位置） | 映射方式 |
|---|---|---|
| `/etc/cc-anywhere/config.yaml` | `~/cc-anywhere/Server/config/config.yaml` | `-v $PWD/config:/etc/cc-anywhere:ro` |
| `/etc/cc-anywhere/tls/cert.pem` | `~/cc-anywhere/Server/config/tls/cert.pem` | 同上 |
| `/etc/cc-anywhere/tls/key.pem` | `~/cc-anywhere/Server/config/tls/key.pem` | 同上 |
| `/var/lib/cc-anywhere/cc-anywhere.db` | `<docker named volume cc-data>` | `-v cc-data:/var/lib/cc-anywhere` |
| `/var/lib/cc-anywhere/inbox/` | 同上（named volume） | 同上 |

⚠️ **常见踩坑**：把 TLS 证书放到 host 上的 `/etc/cc-anywhere/tls/`（系统目录） — 那是 docker daemon 看不到的地方。正解是放在 `Server/config/tls/` 下。

:::

### 装 Mac 客户端

```bash
cd MacClient
bash build_app.sh release
# 把 .build/遥指.app 拖到 /Applications/
open '/Applications/遥指.app'
```

首次启动 → 偏好设置 → Server → 填入 VPS 域名:端口 + 上一步生成的 master token。

### 装 Android 客户端

```bash
cd AndroidClient
flutter pub get
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

打开 App → 等 Mac App 主窗口弹设备绑定二维码 → 用手机扫码完成绑定。

完整安装与故障排查 → [docs/INSTALL.md](./docs/INSTALL.md)

## 📖 文档

| 文档 | 内容 |
|---|---|
| [docs/INSTALL.md](./docs/INSTALL.md) | 三端详细安装、依赖、TLS 自签、首次绑定 |
| [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md) | 架构原理、Hook 桥接机制、消息协议、dumb proxy 设计 |
| [docs/FAQ.md](./docs/FAQ.md) | 常见问题 |
| [docs/AskUserQuestion远程交互/](./docs/AskUserQuestion远程交互/) | AskUserQuestion / Hook 实时桥接 完整开发文档（PRD / 需求 / 技术 / 三轮 Review / 上线研判） |
| [MacClient/README.md](./MacClient/README.md) | Mac 客户端开发指南 |
| [AndroidClient/README.md](./AndroidClient/README.md) | Android 客户端开发指南 |
| [Server/README.md](./Server/README.md) | Server 开发指南 |

## 🛠️ 技术栈

| 端 | 语言 | 框架 | 关键依赖 |
|---|---|---|---|
| MacClient | Swift 5.9 | AppKit + SwiftUI | SwiftTerm（系统 PTY）/ Network.framework |
| AndroidClient | Dart 3.3 | Flutter | Riverpod / flutter_local_notifications / web_socket_channel |
| Server | Go 1.21 | 标准库 | nhooyr.io/websocket / SQLite |
| Hook Bridge | Python 3 | macOS 系统预装 `python3` | 仅标库 |

## 🔒 安全

- 所有通信走 TLS（wss）
- 鉴权用 HMAC-SHA256 + 一次性 master token + 设备绑定 sub_token
- 不存对话内容到 Server（Server 只是消息路由器）
- Mac 端 hook 写入 `~/.claude/settings.json` 时**只追加自己的条目**，不影响用户其它 plugin hooks，关闭时精准卸载
- 漏洞报告：见 [SECURITY.md](./SECURITY.md)

## 🤝 贡献

欢迎 issue 与 PR。贡献前请阅读：

- [CONTRIBUTING.md](./CONTRIBUTING.md) — 开发流程、提交规范、代码风格
- [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md) — 行为准则

本项目大部分代码由 [Claude Code](https://claude.com/claude-code) 协作完成（[完整 L4 开发流程文档](./docs/AskUserQuestion远程交互/) 可供参考）。欢迎用任何方式贡献（包括用 Claude / Cursor / Continue 等 AI 协作工具）。

## 📜 许可证

[MIT License](./LICENSE) © 2026 Beijing Yoolines Interactive Information Technology Co., Ltd. (北京友联互动信息技术有限公司)

## 🙏 致谢

- [Anthropic / Claude Code](https://claude.com/claude-code) — 本项目的底层引擎
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — Mac 端终端渲染
- [Flutter](https://flutter.dev) — 跨端 UI 框架
