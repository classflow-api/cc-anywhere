# 安装指南

完整的三端部署与首次使用流程。如果只想快速体验，主 [README](../README.md#-快速开始) 的简版即可；这里覆盖：

- TLS 自签证书（本地 / 内网测试场景）
- 防火墙 / 域名 / 端口规划
- 首次设备绑定
- 不同发行版的依赖
- 故障排查

## 前置准备

| 端 | 最低要求 |
|---|---|
| **Server** | Linux（任意发行版）/ Docker 20+ / 公网 IP 或域名 / 一个非 80/443 端口（建议 8443）|
| **Mac 客户端** | macOS 14 Sonoma+ / Apple Silicon 或 Intel / 已安装 [Claude Code CLI](https://docs.claude.com/claude-code) |
| **Android 客户端** | Android 10+ (API 29+) / 能扫码或粘贴绑定信息 |

## 第一步：部署 Server

### 选项 A：Docker（推荐）

```bash
# 在 VPS 上
ssh root@your-vps

# 1. 安装 Docker（如未装）
curl -fsSL https://get.docker.com | sh

# 2. 拉代码
git clone https://github.com/classflow-api/cc-anywhere.git
cd cc-anywhere

# 3. 配置目录
mkdir -p ~/cc-anywhere-data/{config,tls}

# 4. 写 config.yaml
cat > ~/cc-anywhere-data/config/config.yaml <<'EOF'
server:
  address: "0.0.0.0:8443"
  tls:
    cert_file: "/etc/cc-anywhere/tls/cert.pem"
    key_file: "/etc/cc-anywhere/tls/key.pem"
  # public_host：手机 / Mac 客户端连接你时用的地址
  public_host: "yourdomain.com:8443"

db:
  path: "/var/lib/cc-anywhere/cc-anywhere.db"

image:
  inbox_dir: "/var/lib/cc-anywhere/inbox"
EOF
```

### TLS 证书（两种方式）

**方式 1：Let's Encrypt（推荐生产）**

```bash
# 装 certbot
apt install -y certbot                      # Debian/Ubuntu
# 或 yum install -y certbot                 # CentOS/RHEL

# 申请证书（要求 80/443 端口暂时空闲）
certbot certonly --standalone -d yourdomain.com

# 复制到 cc-anywhere 目录
cp /etc/letsencrypt/live/yourdomain.com/fullchain.pem ~/cc-anywhere-data/tls/cert.pem
cp /etc/letsencrypt/live/yourdomain.com/privkey.pem    ~/cc-anywhere-data/tls/key.pem

# 自动续期 cron：
echo "0 3 * * * certbot renew --quiet && cp /etc/letsencrypt/live/yourdomain.com/fullchain.pem ~/cc-anywhere-data/tls/cert.pem && cp /etc/letsencrypt/live/yourdomain.com/privkey.pem ~/cc-anywhere-data/tls/key.pem && docker restart cc-anywhere" | crontab -
```

**方式 2：自签证书（本地 / 内网测试）**

```bash
# 生成 CA + 服务器证书（10 年有效）
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
  -keyout ~/cc-anywhere-data/tls/key.pem \
  -out ~/cc-anywhere-data/tls/cert.pem \
  -subj "/CN=yourdomain.com" \
  -addext "subjectAltName=DNS:yourdomain.com,IP:192.168.1.100"
```

⚠️ 自签证书 Mac / Android 端默认会拒绝连接，需要：

- Mac App 偏好里勾"信任自签证书"
- Android：把 cert.pem 装进系统信任锚（设置 → 安全 → 证书 → 安装）

### 构建 + 运行容器

```bash
cd cc-anywhere/Server

# 生成 HMAC secret（一次性，记下来 — 不再可见）
export CC_HMAC_SECRET=$(openssl rand -hex 32)
echo "记下这个 secret：$CC_HMAC_SECRET"
echo "CC_HMAC_SECRET=$CC_HMAC_SECRET" > ~/cc-anywhere-data/.env

# 构建 image
docker build -t cc-anywhere:latest .

# 启动容器
docker run -d --name cc-anywhere --restart unless-stopped \
  -p 8443:8443 \
  -v ~/cc-anywhere-data/config:/etc/cc-anywhere:ro \
  -v cc-data:/var/lib/cc-anywhere \
  --env-file ~/cc-anywhere-data/.env \
  -e TZ=Asia/Shanghai \
  cc-anywhere:latest

# 检查启动
docker logs cc-anywhere --tail 20
# 看到 'server listening addr=0.0.0.0:8443' 即成功
```

### 生成 master token（一次性）

```bash
docker exec cc-anywhere /usr/local/bin/cc-anywhere admin reset-master-token --force
# 输出形如：
# === NEW MASTER TOKEN — copy now, it will not be shown again ===
# <64 hex chars — copy this line and save it securely>
# === save it somewhere safe ===
```

**这个 token 立即记下来**，用于 Mac App 首次绑定。丢了只能重置（重置后 phone 也需要重新扫码绑定）。

### 选项 B：直接跑 Go binary（不用 Docker）

```bash
cd Server
go build -o cc-anywhere ./cmd/cc-anywhere
CC_HMAC_SECRET=$(openssl rand -hex 32) ./cc-anywhere --config ../local-deploy/config/config.yaml
```

适合 ARM 树莓派等不易跑 Docker 的环境。需要 systemd 自启可参考 [Server/README.md](../Server/README.md#systemd)。

## 第二步：安装 Mac 客户端

```bash
# 在你的 Mac 上
git clone https://github.com/classflow-api/cc-anywhere.git
cd cc-anywhere/MacClient

# 1. 确认 Claude Code CLI 已装
which claude    # 应该输出路径，如 /usr/local/bin/claude

# 2. 打包成 .app
bash build_app.sh release

# 3. 装到 Applications
cp -R '.build/遥指.app' /Applications/

# 4. 启动
open '/Applications/遥指.app'
```

### 首次启动配置

1. **偏好设置 → Server**：
   - Host: `yourdomain.com`
   - Port: `8443`
   - Master Token: 粘贴第一步生成的 token
   - 自签证书：勾选"信任自签证书"
2. **首页 → 选择项目文件夹**：选一个本地项目目录，自动 `claude -c` 启动 Tab
3. **（可选）启用远程 hook**：偏好 → 远程 Hook → 开启"启用远程 hook（M1-M3）"
   - 第一次开启会弹许可弹窗，确认后会向 `~/.claude/settings.json` 追加 hook 条目
   - 不影响你已有的其他 plugin hooks

## 第三步：装 Android 客户端

```bash
cd AndroidClient

# 1. 装依赖
flutter pub get

# 2. 构建 APK
flutter build apk --release

# 3. 安装到手机（先开 USB 调试 + adb 连接）
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

模拟器装包同样用 adb（先 `adb connect 127.0.0.1:<emu-port>`）。

### 首次启动绑定

1. **Mac App** → 顶部 → 设备管理 → 生成绑定二维码
2. **手机 App** → 打开 → 自动跳到"扫码绑定"页 → 扫 Mac App 的二维码
3. 绑定成功 → 看到 Mac 上的 Tab 列表 → 点进任一 Tab 看消息流

## 第四步：（可选）启用系统通知

Phone 端第一次启动会弹"允许通知"权限请求 → 允许。之后 Claude 在 Mac 端触发 AskUserQuestion 时，手机收到系统通知（即便 App 在后台 / 锁屏也能看到）。

如错过权限申请：手机设置 → 应用 → 遥指 → 通知 → 允许。

## 故障排查

### `phone connected` 后立即 `INVALID_TOKEN`

**原因**：master_token 不一致 — 通常是 Server 容器 volume 被重置，token 丢了。

**修复**：

```bash
docker exec cc-anywhere /usr/local/bin/cc-anywhere admin reset-master-token --force
# 把新 token 在 Mac App 偏好里重新粘贴
```

### Mac App 连不上 Server

按顺序检查：

1. `nc -zv yourdomain.com 8443` — 端口可达吗？
2. `curl -k https://yourdomain.com:8443/` — TLS 握手成功吗？应该返回 `404 page not found`
3. Mac App console log（菜单 → 日志） — 看具体错误
4. Server log：`docker logs cc-anywhere --tail 50`

### 手机收不到 ask 卡片

按顺序检查：

1. Mac App 偏好里"启用远程 hook" 是 ON 吗？
2. `cat ~/.claude/settings.json | grep cc-anywhere-hook-bridge` — 有 4 个匹配吗？
3. `ls -la ~/Library/Application\ Support/cc-anywhere/hook.sock` — socket 存在吗？
4. Mac App console log 看 `HookIpcServer started` 出现没

### Claude TUI 仍然弹原 AskUserQuestion 弹窗

这是降级行为。可能原因：

- Mac App 内的 inner timeout（默认 30 分钟）触发了 — 手机端不答会降级
- hook bridge 脚本崩溃 — 看 `~/Library/Logs/cc-anywhere/hook-bridge.log`
- claude 子进程的 env 没注入 `CC_ANYWHERE_TAB_ID` — 确认是 Mac App 内启动的 Tab，不是终端直接跑的 `claude`

### Docker Engine 频繁停（开发本机用 OrbStack）

OrbStack 默认会 idle suspend docker engine。改设置：

- OrbStack → Settings → 关闭 "Pause Docker engine when no containers running"
- 或者用 `colima` / Docker Desktop 替代

生产 VPS 用纯 docker daemon（systemd 管理）不会有此问题。

## 更新

```bash
# Server
cd cc-anywhere
git pull
cd Server
docker build -t cc-anywhere:latest .
docker rm -f cc-anywhere
docker run -d --name cc-anywhere --restart unless-stopped \
  -p 8443:8443 \
  -v ~/cc-anywhere-data/config:/etc/cc-anywhere:ro \
  -v cc-data:/var/lib/cc-anywhere \
  --env-file ~/cc-anywhere-data/.env \
  cc-anywhere:latest

# Mac
cd cc-anywhere/MacClient
git pull
bash build_app.sh release
# 拖到 /Applications 覆盖

# Android
cd cc-anywhere/AndroidClient
git pull
flutter pub get && flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

> 由于 Server 是 [dumb proxy 设计](./ARCHITECTURE.md#dumb-proxy-server)，Mac / Android 升级不要求 Server 同步升级。Server 只在以下情况才需要重部：鉴权、设备管理、image 上传、TLS、依赖升级。
