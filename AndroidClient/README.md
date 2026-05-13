# cc-anywhere · AndroidClient

跨端 Claude Code 协作客户端的 Android 端，使用 Flutter 实现。

## 技术栈

- Flutter 3.19+ / Dart 3.3+
- 状态：`flutter_riverpod`
- 路由：`go_router`
- WebSocket：`web_socket_channel`
- 扫码：`mobile_scanner`
- 加密存储：`flutter_secure_storage`
- Markdown：`flutter_markdown`

## 目录

```
lib/
├── main.dart, app.dart            # 入口
├── routes/                        # go_router
├── theme/                         # 色板 + 主题
├── data/                          # WSClient / Repos / 持久化
├── models/                        # 数据模型
├── features/
│   ├── auth/                      # 欢迎 / 扫码 / 手动 / 命名
│   ├── tabs/                      # 会话列表
│   ├── chat/                      # 对话流 + widgets/
│   ├── settings/                  # 设置
│   └── logs/                      # 日志查看
└── widgets/                       # 通用：PulseDot / AuroraOrbs / GlassCard ...
```

## 运行

```bash
flutter pub get
flutter analyze
flutter run -d <device-id>
```

最低 Android 版本：API 29 (Android 10)。
