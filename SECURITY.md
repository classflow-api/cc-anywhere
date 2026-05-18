# 安全策略 · Security Policy

[English](#english) ｜ 中文

## 报告漏洞

如果你发现 **遥指（cc-anywhere）** 存在安全漏洞，请通过下列方式负责任地披露：

1. **不要**在公开 issue 里直接讨论漏洞细节
2. 发邮件到 **security@yoolines.com**，主题前缀 `[security]`
3. 邮件内容包含：
   - 漏洞类型（鉴权 / 注入 / 信息泄漏 / RCE / DoS / 其他）
   - 受影响的端（Mac App / Android App / Server / Hook Bridge）
   - 受影响版本
   - 复现步骤（POC 优先）
   - 你认为的影响范围
   - 你期望的署名（致谢列表）

我们会在 **3 个工作日内** 给出初步回复，**14 个工作日内** 给出修复时间表（或拒绝理由）。

## 处理流程

1. 我们 ack 你的邮件，并讨论严重性
2. 进入私下修复阶段，期间 issue / commit 不公开提及漏洞
3. 修复完成 → 发布带 patch 的版本
4. 公开 CVE / advisory（如适用），署名报告者

## 范围

**在范围内**：

- Server 的 ws 协议处理、TLS、HMAC 鉴权、设备绑定流程
- Mac App 的 hook 安装 / settings.json 写入路径校验、socket 文件权限
- Android App 的 ws / 系统通知 / 本地存储（FlutterSecureStorage）
- Hook Bridge 的 stdin / socket 输入解析

**不在范围内**：

- 第三方依赖的已知漏洞（请直接报给上游：SwiftTerm / Flutter / Go 等）
- 用户自己 VPS 的网络配置错误（如 8443 端口对全网开放）
- 用户私下泄漏自己的 master token 后被恶意使用
- 任何需要物理接触 Mac 或 phone 才能触发的攻击

## 安全设计参考

- 鉴权：HMAC-SHA256 + 一次性 master token + 设备绑定 sub_token，详见 [Server/internal/auth/auth.go](./Server/internal/auth/auth.go)
- 传输：仅 wss（TLS），不允许 ws 明文
- Hook 软失败原则：hook bridge 任何异常都不能比"没装 hook"更糟（NFR-U1/U2）
- settings.json 写入：原子 rename + backup 5 份轮转 + 精准识别（不误删用户的其他 plugin hooks）
- socket 文件权限：0600（仅 owner 读写）
- tool_input 截断：推送给 phone 时长字段截断 200 / 500 字符（带宽 + 隐私保护）

## 致谢

感谢以下安全研究者负责任地披露过漏洞：

_（暂无；如果你是第一个，名字会写在这里 🥇）_

---

## English

If you find a security vulnerability in **遥指 (cc-anywhere)**, please disclose responsibly:

1. **Do not** open a public issue describing the vulnerability
2. Email **security@yoolines.com** with subject prefix `[security]`
3. Include: type, affected tier, version, reproduction steps (PoC preferred), impact analysis, desired credit name

We aim to respond within **3 business days** and provide a fix timeline within **14 business days**.

### Process

1. We ack your email, discuss severity
2. Private fix phase — no public issue/commit reference to the vuln
3. Patched release published
4. Public CVE / advisory with credit (if applicable)

### Scope

**In scope**: Server ws/auth/binding, Mac hook installer & socket, Android ws/notifications/local storage, hook bridge stdin/socket parsing.

**Out of scope**: third-party deps (report upstream), user VPS misconfigs, user's leaked master token, attacks requiring physical access.

### Acknowledgements

_None yet — first reporter goes here 🥇_
