<div align="center">

# 遥指 · cc-anywhere

**A cross-device companion for Claude Code — kick off long tasks on Mac, follow up from your phone.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![macOS](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)](./MacClient)
[![Android](https://img.shields.io/badge/Android-12%2B-3DDC84?logo=android&logoColor=white)](./AndroidClient)
[![Go](https://img.shields.io/badge/Server-Go%201.21%2B-00ADD8?logo=go&logoColor=white)](./Server)

[简体中文](./README.md) ｜ English

</div>

---

## 📱 What is this

**遥指 (cc-anywhere)** lets you run long [Claude Code](https://claude.com/claude-code) tasks on your Mac and stay in the loop from your phone — answer Claude's clarifying questions, approve dangerous tool calls, and watch the conversation in real time.

- **Use case**: You launched a one-hour Claude Code refactor / research / batch task on your Mac, then walked away. When Claude needs to ask a question mid-flight, you get a card on your phone and can decide remotely.
- **What it is not**: another Claude TUI port, the web Claude.ai, or a commercial SaaS.
- **Positioning**: a personal developer tool, self-hosted on your own VPS.

## ✨ Features

- 🪟 **Multi-tab Mac workspace** — each tab binds a project folder and auto-resumes via `claude -c`
- 📲 **Structured cards on phone** — JSONL parsed into a message stream (text / tool use / images / thinking), not a raw TUI mirror
- ⚡ **Real-time `AskUserQuestion` bridge** — Claude asks, phone shows a card in < 1s, first answer wins
- 🛡️ **Remote approval for dangerous tools** (M4) — when Claude wants to run `rm -rf` / Write / Edit, your phone gets a dialog
- 🔔 **System-level notifications** — vibration + lock-screen heads-up even when the app is backgrounded
- ⌨️ **Phone-side text + image input** — keep the conversation going across devices
- 🪝 **Built on Claude Code's native Hook mechanism** — no SDK fork, no TUI replacement
- 🔌 **Dumb-proxy server** — protocol lives on the clients; server only handles auth + device discovery + pass-through. Deploy once, forget.

## 📸 Screenshots

> Placeholder. The Mac app feels like a multi-tab terminal with preferences and device management; the phone app looks like an IM with card-based messages plus an `AskUserQuestion` overlay.

## 🏗️ Architecture

```
┌───────────────────────────────────────────┐
│  Mac App  (Swift + SwiftUI + SwiftTerm)   │
│   ├── ProcessHost: one `claude` per tab
│   ├── JSONLWatcher: FSEvents on ~/.claude/projects
│   ├── HookIpcServer: Unix socket from Claude hooks
│   └── WSClient: wss uplink
└───────────────────────────────────────────┘
                    ↑↓ wss + TLS
┌───────────────────────────────────────────┐
│  Server  (Go, "dumb proxy")               │
│   ├── auth: HMAC + master / sub tokens
│   ├── device: phone binding & revocation
│   ├── image: temporary image upload relay
│   ├── presence: mac_online / phone_count
│   └── router: business types pass through —
│              no redeploy when adding new types
└───────────────────────────────────────────┘
                    ↑↓ wss + TLS
┌───────────────────────────────────────────┐
│  Android App  (Flutter + Riverpod)        │
│   ├── ChatRepository: ws → message stream
│   ├── AskQuestionController: realtime cards
│   ├── AskNotificationService: system notif
│   └── DedupService: tool_use_id dedup
└───────────────────────────────────────────┘
```

Deep dive → [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md)

## 🚀 Quick start

### Prerequisites

1. A Mac (macOS 14+) with [Claude Code CLI](https://docs.claude.com/claude-code) installed
2. An Android phone (API 29+ / Android 10+) or emulator
3. A VPS (any Linux with Docker, domain + TLS recommended)

### Deploy the server (one-time)

```bash
# on your VPS
git clone https://github.com/classflow-api/cc-anywhere.git
cd cc-anywhere/Server

# 1. Config
cp config/config.yaml.example config/config.yaml
# Edit config.yaml — set public_host to your domain:port

# 2. TLS certs (Let's Encrypt or self-signed)
# Place them at ./config/tls/{cert,key}.pem

# 3. HMAC secret + run
export CC_HMAC_SECRET=$(openssl rand -hex 32)
echo "CC_HMAC_SECRET=$CC_HMAC_SECRET" > .env

docker build -t cc-anywhere:latest .
docker run -d --name cc-anywhere --restart unless-stopped \
  -p 8443:8443 \
  -v $PWD/config:/etc/cc-anywhere:ro \
  -v cc-data:/var/lib/cc-anywhere \
  --env-file .env -e TZ=Asia/Shanghai \
  cc-anywhere:latest

# 4. Generate master token (once)
docker exec cc-anywhere /usr/local/bin/cc-anywhere admin reset-master-token --force
```

### Install the Mac client

```bash
cd MacClient
bash build_app.sh release
# Drag .build/遥指.app into /Applications/
open '/Applications/遥指.app'
```

First launch → Preferences → Server → enter your VPS host:port + master token.

### Install the Android client

```bash
cd AndroidClient
flutter pub get
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Open the app → scan the device-binding QR code shown on the Mac app.

Full install & troubleshooting → [docs/INSTALL.md](./docs/INSTALL.md)

## 📖 Docs

| Doc | Content |
|---|---|
| [docs/INSTALL.md](./docs/INSTALL.md) | Detailed install for all three tiers, TLS, binding |
| [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md) | Architecture, hook bridge, message protocol, dumb-proxy design |
| [docs/FAQ.md](./docs/FAQ.md) | FAQ |
| [docs/AskUserQuestion远程交互/](./docs/AskUserQuestion远程交互/) | Full L4 dev docs for the AskUserQuestion hook bridge (PRD, spec, design, three-round code review, release readiness) |
| [MacClient/README.md](./MacClient/README.md) | Mac client dev guide |
| [AndroidClient/README.md](./AndroidClient/README.md) | Android client dev guide |
| [Server/README.md](./Server/README.md) | Server dev guide |

## 🛠️ Tech stack

| Tier | Language | Framework | Key deps |
|---|---|---|---|
| MacClient | Swift 5.9 | AppKit + SwiftUI | SwiftTerm (PTY) / Network.framework |
| AndroidClient | Dart 3.3 | Flutter | Riverpod / flutter_local_notifications / web_socket_channel |
| Server | Go 1.21 | stdlib | nhooyr.io/websocket / SQLite |
| Hook Bridge | Python 3 | macOS preinstalled `python3` | stdlib only |

## 🔒 Security

- All transport over TLS (wss)
- Auth: HMAC-SHA256 + one-time master token + per-device sub tokens
- Server stores no conversation content (it's a relay)
- Mac-side hook installer **only appends** its own entries to `~/.claude/settings.json` and removes them precisely on opt-out — your other plugin hooks are untouched
- Vulnerability reports → [SECURITY.md](./SECURITY.md)

## 🤝 Contributing

Issues and PRs welcome. Before contributing, please read:

- [CONTRIBUTING.md](./CONTRIBUTING.md)
- [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md)

Most of this project was built with [Claude Code](https://claude.com/claude-code) assistance — the full L4 development trail is in [docs/AskUserQuestion远程交互/](./docs/AskUserQuestion远程交互/). Contributions via AI-assisted workflows (Claude, Cursor, Continue, etc.) are encouraged.

## 📜 License

[MIT License](./LICENSE) © 2026 Beijing Yoolines Interactive Information Technology Co., Ltd. (北京友联互动信息技术有限公司)

## 🙏 Acknowledgements

- [Anthropic / Claude Code](https://claude.com/claude-code) — the engine underneath
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — Mac terminal rendering
- [Flutter](https://flutter.dev) — cross-platform UI
