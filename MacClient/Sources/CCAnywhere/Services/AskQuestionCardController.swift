// Copyright (c) 2026 北京友联互动信息技术有限公司. All rights reserved.
//
// AskQuestionCardController.swift
// Mac App 端 AskQuestionCard 的状态管理 + winner 锁联动。
//
// 详见 技术实施文档.md §4.6（接口规格 + 渲染分支 + winner 锁联动）。
//
// 关键设计：
// 1. 实现 `HookIpcCardSink` protocol，由 `HookIpcServer` 通过弱引用调用
//    `show(request:)` 与 `dismiss(requestId:reason:by:)`。
// 2. `@MainActor` + `ObservableObject`：UI 直接绑定 `currentRequest` /
//    `recentlyAnswered`，由 SwiftUI 自动驱动重绘。
// 3. winner 锁联动：当 `HookIpcServer` 在 actor 内部完成裁定后，调用 dismiss(by:)
//    本控制器立即清空 currentRequest 并 surface AnsweredInfo banner（3s 自动消失）。
// 4. UI 端用户点击提交时反向调用 `HookIpcServer.receiveLocalAnswerFromMacCard`
//    / `receiveLocalApprovalFromMacCard`（actor 方法，需 await）。

import Foundation

/// Mac App 端 AskQuestionCard 的控制器。
///
/// 由 `HookIpcServer` 通过 `setCardController(_:)` 弱引用持有；
/// 同时反向通过 `hookIpcServer` 弱引用，把 UI 侧的回答转发给 server。
@MainActor
public final class AskQuestionCardController: ObservableObject, HookIpcCardSink {
    @Published public private(set) var currentRequest: AskCardRequestData?
    @Published public private(set) var recentlyAnswered: AnsweredInfo?

    /// 用于反向调用 `receiveLocalAnswerFromMacCard` /
    /// `receiveLocalApprovalFromMacCard`。
    public weak var hookIpcServer: HookIpcServer?

    /// AnsweredBanner 自动消失的 TTL（秒）。
    public static let answeredBannerTTL: TimeInterval = 3

    public init() {}

    // MARK: - HookIpcCardSink

    /// HookIpcServer 在收到 hook bridge 的 ask 请求时调用，surface 到 UI。
    public func show(request: AskCardRequestData) async {
        self.currentRequest = request
        self.recentlyAnswered = nil
    }

    /// HookIpcServer 在 winner 裁定 / 超时 / 取消时调用。
    ///
    /// 仅当 `requestId` 与当前 currentRequest 匹配时才处理（防止过期消息覆盖
    /// 后续新请求）。
    public func dismiss(requestId: String,
                        reason: AskDismissReason,
                        by: String?) async {
        guard self.currentRequest?.requestId == requestId else { return }
        if reason == .answered {
            self.recentlyAnswered = AnsweredInfo(
                requestId: requestId,
                answeredBy: by ?? "unknown",
                expireAt: Date().addingTimeInterval(Self.answeredBannerTTL)
            )
        }
        self.currentRequest = nil

        // answered banner 在 TTL 后自动消失（其它 reason 不展示 banner，
        // 但仍然走 clearAnsweredBadge 以兜底）。
        let pinnedRequestId = requestId
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.answeredBannerTTL) { [weak self] in
            guard let self = self else { return }
            if self.recentlyAnswered?.requestId == pinnedRequestId {
                self.recentlyAnswered = nil
            }
        }
    }

    // MARK: - UI → Controller → HookIpcServer 反向

    /// 由 AskQuestionCardView 在用户提交 user_question 答案时调用。
    public func submitUserQuestion(requestId: String, answers: [String: String]) {
        guard let server = hookIpcServer else { return }
        Task {
            await server.receiveLocalAnswerFromMacCard(
                requestId: requestId,
                answers: answers
            )
        }
    }

    /// 由 AskQuestionCardView 在用户提交 tool_approval 决策时调用。
    public func submitToolApproval(requestId: String,
                                   decision: String,
                                   reason: String?) {
        guard let server = hookIpcServer else { return }
        Task {
            await server.receiveLocalApprovalFromMacCard(
                requestId: requestId,
                decision: decision,
                reason: reason
            )
        }
    }

    /// 手动关闭 answered banner（用户主动点 ×）。
    public func clearAnsweredBadge() {
        recentlyAnswered = nil
    }
}

/// 已被回答 banner 的展示信息（winner 锁裁定后展示 3 秒）。
public struct AnsweredInfo: Sendable, Equatable {
    public let requestId: String
    /// 形如 `"phone:<device_id>"` / `"mac"`。
    public let answeredBy: String
    public let expireAt: Date

    public init(requestId: String, answeredBy: String, expireAt: Date) {
        self.requestId = requestId
        self.answeredBy = answeredBy
        self.expireAt = expireAt
    }
}
