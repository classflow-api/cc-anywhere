# 贡献指南 · Contributing

[English](#english) ｜ 中文

感谢你对 **遥指（cc-anywhere）** 的兴趣！本项目欢迎 issue、PR、文档改进、bug 报告、功能建议。

---

## 🧭 在动手之前

1. **搜一下既有 issue / PR**，避免重复工作
2. **大改动先开 issue 讨论**（架构变更、协议变更、UI 重做） — 避免你写完发现方向跟主线不一致
3. **小修小补直接 PR** 即可（bug 修复、错别字、文档补充）

## 🛠️ 开发环境

### MacClient

```bash
cd MacClient
swift package resolve
swift build         # 裸 binary
bash build_app.sh   # 打包成 遥指.app
open '.build/遥指.app'
```

要求：macOS 14+ / Swift 5.9+ / Xcode 15+。

### AndroidClient

```bash
cd AndroidClient
flutter pub get
flutter run         # debug 模式真机/模拟器
```

要求：Flutter 3.3+ / Dart 3.3+ / Android SDK 34+ / minSdk 29。

### Server

```bash
cd Server
go build ./...
go vet ./...
# 本地运行
CC_HMAC_SECRET=$(openssl rand -hex 32) \
  go run ./cmd/cc-anywhere --config ./config/config.yaml
```

要求：Go 1.21+。

## 📝 提交规范

采用 [Conventional Commits](https://www.conventionalcommits.org/) 格式：

```
<type>(<scope>): <subject>

[optional body]

[optional footer]
```

**Type**：

- `feat` — 新功能
- `fix` — bug 修复
- `docs` — 文档变更
- `style` — 代码格式（不影响行为）
- `refactor` — 重构（非 feat/fix）
- `perf` — 性能优化
- `test` — 测试
- `chore` — 构建 / 工具变更
- `ci` — CI/CD

**Scope**（可选）：模块名，如 `mac`、`phone`、`server`、`hook-bridge`、`docs`。

**示例**：

```
feat(phone): 系统级通知（ask.question.pending 到达时弹通知）

收到 hook 桥接的实时提问时，phone 端弹 high-priority 系统通知，
即便 App 不在前台也能及时看到。answered/timeout 时自动 cancel。

Closes #42
```

中英文 commit message 都可以接受，但同一 PR 内尽量统一。

## 🎨 代码风格

| 语言 | 风格 | 工具 |
|---|---|---|
| Swift | swift-format 默认 | Xcode 自带 |
| Dart | dart format | `dart format lib/` |
| Go | gofmt + go vet | `go fmt ./... && go vet ./...` |
| Python | Black + Ruff | `black hook_bridge.py` |

**通用约定**：

- 必要时写注释解释 **为什么**（why），别解释**做什么**（what 让代码自解释）
- 复杂业务逻辑 / 边界处理加注释；细分到"为什么这么做" + "曾经在 XX 出过 bug，所以这里这么写"
- 文件 header 保留版权声明（公司著作权与 MIT 不冲突）

## 🧪 测试

本项目以集成测试为主，单测覆盖率不强求。提交 PR 时请：

- 自己跑通对应端的构建（swift build / flutter build / go test）
- 描述清楚改动影响范围，PR 描述里写"如何复现 / 如何验证"

## 🔁 PR 流程

1. Fork 仓库
2. 新建分支 `git checkout -b feat/your-feature`
3. 提交（按上面的 commit 规范）
4. Push 到你的 fork
5. 在 GitHub 上开 PR 到 `master`
6. 描述 **改了什么 / 为什么 / 如何测试**
7. 等 review、按 review 反馈调整
8. CI 通过 + 至少 1 个 approve 后由维护者合并

## 🐛 报告 Bug

请使用 [Bug Report 模板](./.github/ISSUE_TEMPLATE/bug_report.md)，包含：

- 环境（macOS / Android / Server 版本）
- 复现步骤
- 期望行为 vs 实际行为
- 日志 / 截图 / 错误堆栈

## 💡 提交功能建议

请使用 [Feature Request 模板](./.github/ISSUE_TEMPLATE/feature_request.md)，描述使用场景。

## 📖 文档贡献

- 修错别字、补充示例、翻译 — 直接 PR
- 新章节 / 重写 — 先开 issue 讨论结构

## 🤖 AI 辅助贡献

本项目欢迎用 [Claude Code](https://claude.com/claude-code)、Cursor、Continue 等 AI 工具协作。完整的 L4 开发流程示例见 [docs/AskUserQuestion远程交互/](./docs/AskUserQuestion远程交互/)。

PR 描述里**不必披露**你用了哪些 AI 工具，但要确保：

- 自己理解每一行代码（PR review 时维护者可能会问"为什么这么写"）
- 跑过对应端的构建 + 基本验证（不能纯靠 AI 输出未经验证就 PR）

## 📜 许可证

提交 PR 即表示你同意你的贡献以 [MIT License](./LICENSE) 授权。

---

## English

Thanks for your interest in **遥指 (cc-anywhere)**! Issues, PRs, docs improvements, and bug reports are all welcome.

### Before you start

1. Search existing issues / PRs to avoid duplicates
2. For large changes (architecture, protocol, major UI rework), open an issue first
3. Small fixes (bugs, typos, doc additions) — go straight to PR

### Development setup

See the Chinese section above — commands are identical.

### Commit convention

[Conventional Commits](https://www.conventionalcommits.org/). Types: `feat` `fix` `docs` `style` `refactor` `perf` `test` `chore` `ci`. Scope: `mac` `phone` `server` `hook-bridge` `docs`.

Chinese or English commit messages both accepted; keep one PR consistent.

### Code style

| Language | Style | Tool |
|---|---|---|
| Swift | swift-format defaults | Xcode |
| Dart | dart format | `dart format lib/` |
| Go | gofmt + vet | `go fmt ./... && go vet ./...` |
| Python | Black + Ruff | `black hook_bridge.py` |

Keep the copyright header in existing files. The company copyright + MIT license is fully compatible.

### PR flow

1. Fork → branch → commit → push → open PR to `master`
2. PR description: **what / why / how to test**
3. At least one maintainer approval + CI green before merge

### AI-assisted contributions

Welcome. We don't require disclosure of which AI tool you used, but:

- Make sure you understand every line you submit
- Build the affected tier locally before opening the PR

### License

By submitting a PR, you agree your contribution is licensed under the [MIT License](./LICENSE).
