# cc-anywhere Server

跨端 Claude Code 协作客户端的中转服务器。Go 单二进制，通过 WebSocket over TLS 把 Mac 桌面客户端与 Android 客户端连起来。

## 功能

- TLS WebSocket 监听（`/ws`），按 `bind` 消息区分 Mac / Phone
- 主 Token（master_token）+ 子 Token（sub_token）双向鉴权，sha256 哈希存储
- 设备登记：sub_token 生成、首次绑定 pending→active、撤销
- 消息路由：Mac↔手机 双向转发（`msg.stream` / `input.*` / `tab.*` / `tool_use.approve`）
- presence 广播：Mac 上线/下线、手机数量变化
- 图片中转：HMAC URL token + sha256 校验 + Mac 确认后立即删除 + 5 分钟未取自动清理
- CLI admin 工具：`reset-master-token` / `list-devices` / `revoke-device`

## 目录

```
Server/
├── cmd/cc-anywhere/         # main + cobra CLI
├── internal/
│   ├── config/              # YAML 配置加载
│   ├── db/                  # SQLite + 迁移
│   │   └── migrations/
│   ├── server/              # TLS WS + HTTP + Hub + Connection
│   ├── auth/                # token 哈希 + master 校验
│   ├── device/              # sub_token 生命周期
│   ├── router/              # 消息分发
│   ├── presence/            # 在线状态广播
│   ├── image/               # 上传/下载/HMAC/GC
│   └── protocol/            # 所有 WS 消息 struct
├── config/config.yaml.example
├── Dockerfile
└── docker-compose.yml
```

## 本地开发

```bash
cd Server
go mod tidy
go build ./...
go vet ./...
gofmt -l .

# 生成自签证书
openssl req -x509 -newkey rsa:4096 -keyout config/tls/key.pem -out config/tls/cert.pem \
    -days 365 -nodes -subj "/CN=localhost"

# 准备配置
cp config/config.yaml.example config/config.yaml
# 修改 public_host

# 启动
export CC_HMAC_SECRET=$(openssl rand -hex 32)
./cc-anywhere serve --config config/config.yaml
```

## Docker 部署

```bash
# 1. 准备配置 + TLS 证书
mkdir -p config/tls
cp config/config.yaml.example config/config.yaml
# 修改 public_host

# 2. 构建并启动
export CC_HMAC_SECRET=$(openssl rand -hex 32)
docker compose build
docker compose up -d

# 3. 初始化主 Token（必须）
docker compose exec cc-anywhere cc-anywhere admin reset-master-token --force
# 复制 stderr 输出的 token 到 MacClient 配置

# 4. 健康检查
curl -k https://cc.example.com:8443/healthz
```

## CLI

```bash
cc-anywhere serve --config /etc/cc-anywhere/config.yaml
cc-anywhere admin reset-master-token --force
cc-anywhere admin list-devices
cc-anywhere admin revoke-device --id <sub_token_id>
```

## HTTP / WebSocket 端点

| Method | Path | 用途 | 鉴权 |
|--------|------|------|------|
| GET | `/ws` | WebSocket 升级 | 首条 `bind` 消息 |
| GET | `/healthz` | 健康检查 | 无 |
| POST | `/upload/{uploadID}?token=&exp=` | 手机上传图片 | HMAC URL，5 分钟过期 |
| GET | `/download/{uploadID}?token=&exp=` | Mac 下载图片 | HMAC URL，5 分钟过期 |

协议消息列表见 `docs/跨端协作客户端/需求规格说明书.md` §3.4。

## 错误码

`INVALID_TOKEN` / `TOKEN_EXPIRED` / `REVOKED` / `MAC_OFFLINE` / `TAB_NOT_FOUND` / `IMAGE_TOO_LARGE` / `SHA256_MISMATCH` / `INTERNAL`

## 数据持久化

仅 SQLite（`/var/lib/cc-anywhere/cc-anywhere.db`），表：

- `master_token`（单行）
- `sub_tokens`（设备登记）
- `schema_version`（迁移版本号）

无消息缓冲；Mac 离线时手机的 `input.*` 立即收到 `error: MAC_OFFLINE`。

## 升级

```bash
docker compose pull
docker compose up -d
```

数据库迁移自动执行（forward-only）。
