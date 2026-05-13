# cc-anywhere

> Copyright (c) 2026 北京友联互动信息技术有限公司. All rights reserved.

## 项目简介

cc-anywhere 是一个跨端 Claude Code 协作客户端，通过自有 VPS 桥接 Mac 桌面客户端和 Android 客户端，让你可以：

- 在 Mac 上以多 Tab 方式管理多个 Claude Code 会话（每个 Tab 绑定一个本地文件夹，自动启动 `claude -c` 恢复历史对话）
- 在 Android 手机上以卡片式消息列表实时查看任意 Tab 的对话进展
- 在手机上输入文字、上传图片继续与 Claude Code 对话
- 在手机上批准/拒绝 Claude Code 的工具调用请求

适用于"在 Mac 上跑长任务，离开桌面后用手机查看与干预"的个人开发场景。

## 项目结构

```
cc-anywhere/
├── docs/              # 需求文档、技术方案、审查报告
├── MacClient/         # Mac 桌面客户端（Swift + SwiftTerm + PTY）
├── AndroidClient/     # Android 客户端（Flutter + 卡片消息）
└── Server/            # 中转服务器（Go + WebSocket）
```

## 开发环境

| 端 | 要求 |
|----|------|
| MacClient | macOS 13+ / Xcode 15+ / Swift 5.9+ |
| AndroidClient | Flutter 3.x / Android SDK 33+ |
| Server | Go 1.21+ / 自有 VPS（任意可绑域名 + TLS 的服务器）|

## 快速开始

> 各端详细开发指南请参阅对应目录下的 README（开发流程中陆续产出）。

整体工作流：

1. 部署 Server 到 VPS，记下域名、端口、主 Token
2. 安装 MacClient，在设置页填写 Server 地址 + 端口 + 主 Token 绑定
3. 在 MacClient 创建第一个 Tab，选择项目文件夹，自动启动 Claude Code
4. 在 MacClient 设备管理页生成手机绑定 QR 码
5. 安装 AndroidClient，扫码完成绑定，即可远程查看与对话

## 核心设计要点

- **无 daemon**：Mac 端单 UI 进程；软件关闭 = 网络断联 + 子进程退出
- **对话持久化交给 Claude Code 自己**：本地仅保存 Tab 列表，重启用 `claude -c` 自动恢复
- **手机端是结构化 viewer**：通过监听 Claude Code 的 JSONL 对话日志拿到完美结构化的消息
- **不用 tmux**：直接系统 PTY，少一层中间层

更多设计细节见 `CLAUDE.md` 与 `docs/` 内的产品/技术文档。

## 许可证

Copyright (c) 2026 北京友联互动信息技术有限公司. All rights reserved.

本项目为公司内部项目，未经授权不得对外分发。
