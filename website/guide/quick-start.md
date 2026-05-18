# 快速开始

30 分钟内跑起遥指三端。需要：

- 一台 Mac（macOS 14+）+ 已装 [Claude Code CLI](https://docs.claude.com/claude-code)
- 一台 Android 手机或模拟器（Android 10+）
- 一台 VPS（任意 Linux + Docker）或本机 Docker

::: tip 路径
完整安装含 TLS 自签证书 / 故障排查 / systemd 守护，请看 [完整安装](/guide/installation)。本页只覆盖最快上手路径。
:::

## 1. 部署 Server（5 分钟）

::: code-group

```bash [VPS / 公网]
ssh root@your-vps

git clone https://github.com/classflow-api/cc-anywhere.git
cd cc-anywhere/Server          # ← 后续 docker build / run 都在 Server/ 目录下

mkdir -p /opt/cc-anywhere/{config,tls}

# 用 Let's Encrypt 拿证书
certbot certonly --standalone -d yourdomain.com
cp /etc/letsencrypt/live/yourdomain.com/{fullchain,privkey}.pem /opt/cc-anywhere/tls/

# config.yaml
cat > /opt/cc-anywhere/config/config.yaml <<EOF
server:
  address: "0.0.0.0:8443"
  tls:
    cert_file: "/etc/cc-anywhere/tls/fullchain.pem"
    key_file: "/etc/cc-anywhere/tls/privkey.pem"
  public_host: "yourdomain.com:8443"
db:
  path: "/var/lib/cc-anywhere/cc-anywhere.db"
image:
  inbox_dir: "/var/lib/cc-anywhere/inbox"
EOF

# 生成 HMAC secret + 启动
docker build -t cc-anywhere:latest .
docker run -d --name cc-anywhere --restart unless-stopped \
  -p 8443:8443 \
  -v /opt/cc-anywhere/config:/etc/cc-anywhere:ro \
  -v cc-data:/var/lib/cc-anywhere \
  -e CC_HMAC_SECRET=$(openssl rand -hex 32) \
  -e TZ=Asia/Shanghai \
  cc-anywhere:latest

# 生成 master token（一次性，记下来）
docker exec cc-anywhere /usr/local/bin/cc-anywhere admin reset-master-token --force
```

```bash [本机 Docker / 局域网测试]
git clone https://github.com/classflow-api/cc-anywhere.git
cd cc-anywhere/Server          # ← 后续 docker build / run 都在 Server/ 目录下

mkdir -p ~/cc-anywhere-data/{config,tls}

# 自签证书（10 年）
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
  -keyout ~/cc-anywhere-data/tls/key.pem \
  -out ~/cc-anywhere-data/tls/cert.pem \
  -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,IP:192.168.1.100"

# config.yaml 跟上面一样，但 public_host 改成你局域网 IP

docker build -t cc-anywhere:latest .
docker run -d --name cc-anywhere --restart unless-stopped \
  -p 8443:8443 \
  -v ~/cc-anywhere-data/config:/etc/cc-anywhere:ro \
  -v cc-data:/var/lib/cc-anywhere \
  -e CC_HMAC_SECRET=$(openssl rand -hex 32) \
  cc-anywhere:latest

docker exec cc-anywhere /usr/local/bin/cc-anywhere admin reset-master-token --force
```

:::

把输出的 master token **立即记下**（不会再显示第二次）。

## 2. Mac 客户端（10 分钟）

```bash
cd cc-anywhere/MacClient
bash build_app.sh release
cp -R '.build/遥指.app' /Applications/
open '/Applications/遥指.app'
```

首次启动：
1. **偏好设置** → **Server**：填 `yourdomain.com` + 端口 `8443` + master token
2. 自签证书勾选「信任自签证书」
3. **主窗口** → **选择项目文件夹** → 自动 `claude -c` 启动 Tab
4. **偏好** → **远程 Hook** → 切换主开关 ON → 同意许可

## 3. Android 客户端（5 分钟）

```bash
cd cc-anywhere/AndroidClient
flutter pub get
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

打开 App → Mac 端调出绑定二维码 → 手机扫码完成绑定。

::: tip 同意通知权限
首次启动时手机会问通知权限，**点允许**。这样 Claude 触发 AskUserQuestion 时即便手机锁屏也能收到震动 + 抬头提醒。
:::

## 4. 验证

Mac 端发个 prompt 让 Claude 用 `AskUserQuestion`：

> 使用 AskUserQuestion 工具问我喜欢什么颜色

期望：

1. ✅ 手机端 ≤ 1 秒弹出实时卡片（底部弹出）
2. ✅ Mac Tab 内也弹出同一张卡片（不是 TUI 自带弹窗）
3. ✅ 任一端选答案 → 另一端立即显示「已被 X 回答」
4. ✅ Claude 拿到 answers 继续对话

跑通这 4 步就齐活了。后续可以：

- [启用工具批准远程化（M4）](/guide/architecture#m4-危险工具远程批准) — Bash / Write / Edit 走手机批准
- [架构深入](/guide/architecture) — 理解 Hook 桥接 + Dumb Proxy + Winner 锁
- [常见问题](/guide/faq) — 部署 / 协议 / 安全
