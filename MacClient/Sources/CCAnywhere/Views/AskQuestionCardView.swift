// Copyright (c) 2026 北京友联互动信息技术有限公司. All rights reserved.
//
// AskQuestionCardView.swift
// Mac App 端 AskUserQuestion / Tool Approval 卡片 UI。
//
// 详见：
//   - 技术实施文档.md §4.6.3 渲染分支
//   - 需求规格说明书.md §3.4.1 Mac App AskQuestionCardView 布局
//   - 场景 F1-S6（自定义回答输入项）
//   - R-F1-012（始终展示自定义回答输入项）
//   - R-F1-013（winner 锁仲裁后展示 AnsweredBanner）
//   - R-F1-014（answers 值类型可为 label 或自定义字符串）
//   - NFR-C5（自定义输入框限长 200 字符）
//
// 关键设计：
// 1. ZStack 叠 CardOverlay（pending）与 AnsweredBanner（recentlyAnswered），
//    由 controller 的 @Published 触发 SwiftUI 重绘。
// 2. user_question vs tool_approval 两条独立 UI 分支，提交动作走不同 controller
//    入口（submitUserQuestion / submitToolApproval）。
// 3. 自定义回答输入项：每个 question 末尾固定渲染一个 "Other" 选项，与预设 options
//    并列（radio/checkbox 中的一项）；选中后展开一个 NSTextField（限长 200）。
// 4. 多 question 纵向堆叠；multiSelect=true 用 checkbox 列表 + 分号拼接（仅对
//    本次 Mac 端实现，与 AskUserQuestion 工具语义对齐）。
// 5. 不允许用户主动取消卡片（只能等 phone 答 / 超时 / 重启），cancel 闭包保留为
//    扩展点。

import SwiftUI

// MARK: - 顶层 View

/// Tab 内嵌的 AskQuestion 卡片（用户反馈：原全局弹窗在多 tab 时阻塞所有交互，
/// 改为按 tab 内嵌底部弹出 — A tab 的卡片不影响 B tab 操作）。
///
/// 用法：在 TabContentView 内 ZStack 底部叠加 `AskQuestionCardView(controller:, tabId:)`。
/// pending == nil 时透明不占空间也不拦截 hit-test；非 nil 时从底部弹出卡片但
/// **不遮罩整个 tab**（用户可点上方终端区域、切到别的 tab 等）。
public struct AskQuestionCardView: View {
    @ObservedObject var controller: AskQuestionCardController
    let tabId: UUID
    @EnvironmentObject var themeManager: ThemeManager

    public init(controller: AskQuestionCardController, tabId: UUID) {
        self.controller = controller
        self.tabId = tabId
    }

    public var body: some View {
        let palette = themeManager.palette
        let pending = controller.pending(forTab: tabId)
        let answered = controller.answered(forTab: tabId)
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            if let req = pending {
                CardOverlay(
                    request: req,
                    palette: palette,
                    onSubmitUserQuestion: { answers in
                        controller.submitUserQuestion(
                            requestId: req.requestId,
                            answers: answers
                        )
                    },
                    onSubmitToolApproval: { decision, reason in
                        controller.submitToolApproval(
                            requestId: req.requestId,
                            decision: decision,
                            reason: reason
                        )
                    }
                )
                .frame(maxWidth: 520)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .shadow(color: Color.black.opacity(0.35), radius: 18, y: 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let info = answered {
                AnsweredBanner(
                    info: info,
                    palette: palette,
                    onClose: { controller.clearAnsweredBadge(forTab: tabId) }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: pending?.requestId)
        .animation(.easeInOut(duration: 0.2), value: answered?.requestId)
        .allowsHitTesting(pending != nil || answered != nil)
    }
}

// MARK: - 卡片本体

private struct CardOverlay: View {
    let request: AskCardRequestData
    let palette: ColorPalette
    let onSubmitUserQuestion: ([String: String]) -> Void
    let onSubmitToolApproval: (_ decision: String, _ reason: String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider().background(palette.line)
            content
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.bgElev)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 8)
    }

    // MARK: header

    @ViewBuilder
    private var header: some View {
        if request.askKind == "tool_approval" {
            HStack(spacing: 8) {
                Text("⚠ 工具批准")
                    .font(AppFont.ui(size: 11.5, weight: .bold))
                    .foregroundColor(palette.danger)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(palette.danger.opacity(0.12))
                    )
                Spacer()
            }
            Text("Claude 想执行 \(request.toolName ?? "(未知工具)")")
                .font(AppFont.ui(size: 15, weight: .bold))
                .foregroundColor(palette.text)
        } else {
            Text("Claude 想问您：")
                .font(AppFont.ui(size: 15, weight: .bold))
                .foregroundColor(palette.text)
        }
    }

    // MARK: content

    @ViewBuilder
    private var content: some View {
        if request.askKind == "tool_approval" {
            ToolApprovalBody(
                request: request,
                palette: palette,
                onAllow: { onSubmitToolApproval("allow", nil) },
                onDeny: { onSubmitToolApproval("deny", nil) }
            )
        } else {
            UserQuestionBody(
                request: request,
                palette: palette,
                onSubmit: onSubmitUserQuestion
            )
        }
    }
}

// MARK: - tool_approval 分支

private struct ToolApprovalBody: View {
    let request: AskCardRequestData
    let palette: ColorPalette
    let onAllow: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("调用参数")
                    .font(AppFont.ui(size: 11.5, weight: .semibold))
                    .foregroundColor(palette.textMuted)
                ScrollView {
                    Text(summarizeToolInput(request.toolInput))
                        .font(AppFont.mono(size: 12))
                        .foregroundColor(palette.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                        .background(palette.bgInset)
                        .cornerRadius(8)
                }
                .frame(maxHeight: 180)
            }
            HStack(spacing: 12) {
                Spacer()
                Button(action: onDeny) {
                    Text("拒绝")
                        .font(AppFont.ui(size: 13, weight: .semibold))
                        .foregroundColor(palette.danger)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(palette.danger.opacity(0.10))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                Button(action: onAllow) {
                    Text("允许")
                        .font(AppFont.ui(size: 13, weight: .semibold))
                        .foregroundColor(palette.accentFg)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(palette.accent)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// tool_input 摘要：截断到 500 字符，保持 JSON 可读。
    private func summarizeToolInput(_ input: AnyJSON?) -> String {
        guard let input = input else { return "(无)" }
        let s: String
        switch input {
        case .string(let str):
            s = str
        default:
            // 编码成 pretty JSON
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                let data = try encoder.encode(input)
                s = String(data: data, encoding: .utf8) ?? "(unencodable)"
            } catch {
                s = "(encode failed: \(error.localizedDescription))"
            }
        }
        if s.count > 500 {
            let idx = s.index(s.startIndex, offsetBy: 500)
            return s[..<idx] + "…(截断)"
        }
        return s
    }
}

// MARK: - user_question 分支

private struct UserQuestionBody: View {
    let request: AskCardRequestData
    let palette: ColorPalette
    let onSubmit: ([String: String]) -> Void

    /// 每个 question 的选中 label 集合（multiSelect=false 时只允许一项）。
    @State private var selections: [Int: Set<String>] = [:]
    /// 每个 question 的自定义回答输入框内容（始终展示，对齐 R-F1-012）。
    @State private var otherTexts: [Int: String] = [:]
    /// 翻页改造：当前显示的问题索引（永远启用单题视图；N=1 时步进控件自动隐藏）。
    @State private var currentIndex: Int = 0
    /// 卡片整体的键盘焦点。仅用于接收 ← → 翻页事件；用户点击 TextField 时
    /// TextField 自动接管焦点，左右键退还给文本编辑（避免与翻页冲突）。
    @FocusState private var keyboardFocused: Bool

    /// 自定义回答的特殊 sentinel label。
    private static let otherSentinel = "__cc_anywhere_other__"
    /// 自定义回答输入框最大长度（NFR-C5）。
    private static let otherMaxLength = 200

    private var questions: [AskQuestionItem] { request.questions ?? [] }
    private var totalCount: Int { questions.count }
    private var isFirst: Bool { currentIndex <= 0 }
    private var isLast: Bool { currentIndex >= max(0, totalCount - 1) }
    /// 是否需要显示翻页步进控件（≥ 2 题）。单题场景退化为现有体验。
    private var showStepper: Bool { totalCount >= 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showStepper {
                progressIndicator
            }
            if let q = currentQuestion {
                questionBlock(index: currentIndex, question: q)
                    .id(currentIndex)
            }
            navigationBar
        }
        .focusable()
        .focused($keyboardFocused)
        .onAppear {
            // 多题场景自动获焦，让用户立即可用键盘 ← → 翻页；单题不抢焦点，
            // 避免不必要地把焦点从终端拉走。
            if showStepper { keyboardFocused = true }
        }
        .onKeyPress(.leftArrow) {
            goPrev()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            goNext()
            return .handled
        }
        .onKeyPress(.return) {
            // 末题且已答完所有问题时 Enter 触发提交；其他情况让事件冒泡
            // （含 TextField 获焦时按 Enter — 此时焦点不在卡片父层，
            // onKeyPress 不会被调用）。
            if isLast && canSubmit {
                submit()
                return .handled
            }
            return .ignored
        }
        .animation(.easeInOut(duration: 0.15), value: currentIndex)
    }

    // MARK: 翻页辅助

    /// index 越界的单点防御（getter 内 guard 兜底）。
    /// questions 数组来自 `let request`，view 生命周期内不可变，因此不再
    /// 用 `onChange(of: totalCount)` 做 clamp（避免死分支）。
    private var currentQuestion: AskQuestionItem? {
        guard currentIndex >= 0, currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    private func goPrev() {
        guard !isFirst else { return }
        currentIndex -= 1
    }

    private func goNext() {
        guard !isLast else { return }
        currentIndex += 1
    }

    // MARK: 顶部进度指示

    private var progressIndicator: some View {
        HStack(spacing: 0) {
            Spacer()
            Text("\(currentIndex + 1) / \(totalCount)")
                .font(AppFont.ui(size: 12, weight: .semibold))
                .foregroundColor(palette.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(palette.bgInset)
                .cornerRadius(10)
        }
    }

    // MARK: 底部导航栏

    @ViewBuilder
    private var navigationBar: some View {
        HStack(spacing: 12) {
            if showStepper {
                Button(action: goPrev) {
                    Text("← 上一题")
                        .font(AppFont.ui(size: 13, weight: .semibold))
                        .foregroundColor(isFirst ? palette.textFaint : palette.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(palette.bgInset.opacity(isFirst ? 0.5 : 1.0))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(isFirst)
                Spacer()
                if isLast {
                    submitButton
                } else {
                    Button(action: goNext) {
                        Text("下一题 →")
                            .font(AppFont.ui(size: 13, weight: .semibold))
                            .foregroundColor(palette.accentFg)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(palette.accent)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Spacer()
                submitButton
            }
        }
    }

    private var submitButton: some View {
        Button(action: submit) {
            Text("提交")
                .font(AppFont.ui(size: 13, weight: .semibold))
                .foregroundColor(palette.accentFg)
                .padding(.horizontal, 22)
                .padding(.vertical, 9)
                .background(canSubmit ? palette.accent : palette.accent.opacity(0.4))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    // MARK: 单条 question 渲染

    @ViewBuilder
    private func questionBlock(index: Int, question: AskQuestionItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(question.question)
                    .font(AppFont.ui(size: 14, weight: .semibold))
                    .foregroundColor(palette.text)
                if !question.header.isEmpty {
                    Text("(\(question.header))")
                        .font(AppFont.ui(size: 11.5))
                        .foregroundColor(palette.textFaint)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { (_, opt) in
                    optionRow(
                        index: index,
                        label: opt.label,
                        description: opt.description,
                        multiSelect: question.multiSelect
                    )
                }
                // R-F1-012：始终展示"自定义回答"选项
                optionRow(
                    index: index,
                    label: Self.otherSentinel,
                    description: "用键盘输入",
                    multiSelect: question.multiSelect,
                    displayLabel: "自定义回答"
                )
                if isOtherSelected(index: index) {
                    otherInput(index: index)
                }
            }
        }
        .padding(12)
        .background(palette.bgInset)
        .cornerRadius(10)
    }

    @ViewBuilder
    private func optionRow(index: Int,
                           label: String,
                           description: String?,
                           multiSelect: Bool,
                           displayLabel: String? = nil) -> some View {
        let selected = (selections[index]?.contains(label)) ?? false
        Button(action: { toggle(index: index, label: label, multiSelect: multiSelect) }) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: indicatorImageName(selected: selected, multiSelect: multiSelect))
                    .font(.system(size: 13))
                    .foregroundColor(selected ? palette.accent : palette.textMuted)
                    .frame(width: 16, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayLabel ?? label)
                        .font(AppFont.ui(size: 13))
                        .foregroundColor(palette.text)
                    if let d = description, !d.isEmpty {
                        Text(d)
                            .font(AppFont.ui(size: 11.5))
                            .foregroundColor(palette.textFaint)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(selected ? palette.accent.opacity(0.10) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func otherInput(index: Int) -> some View {
        TextField(
            "请输入自定义回答（最多 \(Self.otherMaxLength) 字符）",
            text: Binding(
                get: { otherTexts[index] ?? "" },
                set: { newValue in
                    if newValue.count > Self.otherMaxLength {
                        otherTexts[index] = String(newValue.prefix(Self.otherMaxLength))
                    } else {
                        otherTexts[index] = newValue
                    }
                }
            )
        )
        .textFieldStyle(.plain)
        .font(AppFont.ui(size: 13))
        .foregroundColor(palette.text)
        .padding(8)
        .background(palette.bgElev)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(palette.line, lineWidth: 1)
        )
        .cornerRadius(6)
    }

    // MARK: 状态辅助

    private func indicatorImageName(selected: Bool, multiSelect: Bool) -> String {
        if multiSelect {
            return selected ? "checkmark.square.fill" : "square"
        } else {
            return selected ? "largecircle.fill.circle" : "circle"
        }
    }

    private func toggle(index: Int, label: String, multiSelect: Bool) {
        var set = selections[index] ?? []
        if multiSelect {
            if set.contains(label) {
                set.remove(label)
            } else {
                set.insert(label)
            }
        } else {
            set = [label]
        }
        selections[index] = set
    }

    private func isOtherSelected(index: Int) -> Bool {
        (selections[index]?.contains(Self.otherSentinel)) ?? false
    }

    /// 是否允许提交：每个 question 都必须至少有一个选择；若选了"自定义回答"，
    /// 则自定义输入框非空。
    private var canSubmit: Bool {
        let qs = request.questions ?? []
        guard !qs.isEmpty else { return false }
        for (idx, _) in qs.enumerated() {
            let set = selections[idx] ?? []
            if set.isEmpty { return false }
            if set.contains(Self.otherSentinel) {
                let txt = (otherTexts[idx] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if txt.isEmpty { return false }
            }
        }
        return true
    }

    /// 提交：组装 answers map。
    ///
    /// answers 的 key 是 question 原文；value 是选择的 label 或自定义字符串。
    /// multiSelect 情形将多个 label 用 `; ` 连接。
    /// R-F1-014：value 可以是 label 也可以是任意自定义字符串。
    private func submit() {
        guard canSubmit else { return }
        var answers: [String: String] = [:]
        for (idx, q) in (request.questions ?? []).enumerated() {
            let set = selections[idx] ?? []
            var parts: [String] = []
            // 预设 options 按原顺序输出（保持稳定）
            for opt in q.options where set.contains(opt.label) {
                parts.append(opt.label)
            }
            if set.contains(Self.otherSentinel) {
                let txt = (otherTexts[idx] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !txt.isEmpty {
                    parts.append(txt)
                }
            }
            answers[q.question] = parts.joined(separator: "; ")
        }
        onSubmit(answers)
    }
}

// MARK: - AnsweredBanner（winner 锁联动）

private struct AnsweredBanner: View {
    let info: AnsweredInfo
    let palette: ColorPalette
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(palette.success)
            Text(message)
                .font(AppFont.ui(size: 12.5))
                .foregroundColor(palette.text)
            Spacer(minLength: 12)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(palette.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.bgElev)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 16)
    }

    private var message: String {
        let by = info.answeredBy
        if by.hasPrefix("phone:") {
            return "已被手机端回答（\(by)）"
        }
        if by == "mac" || by == "mac:local" {
            return "已由本机回答"
        }
        return "已被回答（\(by)）"
    }
}
