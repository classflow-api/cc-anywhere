---
name: Bug 报告 · Bug report
about: 报告功能不符合预期 · Report a bug
title: '[bug] '
labels: bug
assignees: ''
---

## 受影响端

- [ ] Mac 客户端（macOS 版本：）
- [ ] Android 客户端（Android 版本：）
- [ ] Server
- [ ] Hook Bridge

## 复现步骤

1.
2.
3.

## 期望行为

## 实际行为

## 日志 / 截图 / 堆栈

- Mac 端日志：`~/Library/Logs/cc-anywhere/cc-anywhere.log`
- Hook Bridge 日志：`~/Library/Logs/cc-anywhere/hook-bridge.log`
- Android adb logcat：`adb logcat -d --pid=$(adb shell pidof com.yoolines.ccanywhere.cc_anywhere) | grep flutter`
- Server 日志：`docker logs cc-anywhere --tail 100`

## 环境

- Claude Code CLI 版本：`claude --version`
- cc-anywhere git commit：`git -C cc-anywhere/ log -1 --format='%h %s'`
