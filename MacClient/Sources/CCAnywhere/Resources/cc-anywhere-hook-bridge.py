#!/usr/bin/env python3
# Copyright (c) 2026 北京友联互动信息技术有限公司. All rights reserved.
"""
cc-anywhere hook bridge - Forwards Claude Code hooks to Mac App via Unix socket.

Subcommands:
  ask              (blocks; PreToolUse AskUserQuestion or Bash/Write/Edit approval)
  progress pre     (fire-and-forget; PreToolUse Bash/Write/Edit progress)
  progress post    (fire-and-forget; PostToolUse .* progress)
  notification     (fire-and-forget; Notification event)

软失败保护（R-F1-001 / R-F1-002 / R-F1-003 / R-F1-004）：
  - 保护 1：无 CC_ANYWHERE_TAB_ID env → 立即 echo {} 退出（透明放行）
  - 保护 2：socket connect 失败 → 返回 {}（让 Claude SDK 走 fallback）
  - 保护 3：任何外层异常 → safe_exit_with_empty() ctx manager 兜底 → echo {}

所有日志写 stderr 并落盘到 ~/Library/Logs/cc-anywhere/hook-bridge.log，绝不污染 stdout。

License: Proprietary. 仅限 cc-anywhere 项目内部使用。
"""
import json
import os
import socket
import sys
import traceback
from contextlib import contextmanager

SOCKET_PATH = os.path.expanduser(
    "~/Library/Application Support/cc-anywhere/hook.sock"
)
LOG_PATH = os.path.expanduser(
    "~/Library/Logs/cc-anywhere/hook-bridge.log"
)
SOCKET_CONNECT_TIMEOUT = 2.0       # socket connect 超时（秒）
ASK_RESPONSE_TIMEOUT = 1800.0      # ask 等待 Mac App 回写超时（与 hook timeout 一致：30 分钟）
FIRE_AND_FORGET_TIMEOUT = 0.5      # progress/notification 超时（短，绝不阻塞 Claude SDK）


def log_stderr(msg):
    """所有日志写 stderr，并落盘到 hook-bridge.log（R-F1-004）。绝不污染 stdout。"""
    try:
        sys.stderr.write(f"[cc-anywhere-hook-bridge] {msg}\n")
    except Exception:
        pass
    try:
        os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
        with open(LOG_PATH, "a", encoding="utf-8") as f:
            f.write(f"[{os.getpid()}] {msg}\n")
    except Exception:
        pass


@contextmanager
def safe_exit_with_empty():
    """三道保护的核心：任何异常都退化为 echo '{}'。"""
    try:
        yield
    except SystemExit:
        raise
    except BaseException as e:  # noqa: BLE001
        try:
            log_stderr(f"FATAL: {e}\n{traceback.format_exc()}")
        except Exception:
            pass
        try:
            sys.stdout.write("{}\n")
            sys.stdout.flush()
        except Exception:
            pass
        sys.exit(0)


def must_have_tab_id():
    """保护 1：无 CC_ANYWHERE_TAB_ID env 立即放行（R-F1-002）。返回 None 表示放行。"""
    tab_id = os.environ.get("CC_ANYWHERE_TAB_ID")
    if not tab_id:
        return None
    return tab_id


def socket_call(payload, response_timeout):
    """连接 Mac App socket 并发请求；保护 2：连不上立即返回 {}。"""
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(SOCKET_CONNECT_TIMEOUT)
    try:
        s.connect(SOCKET_PATH)
    except Exception as e:
        log_stderr(f"socket connect failed: {e}")
        try:
            s.close()
        except Exception:
            pass
        return {}
    s.settimeout(response_timeout)
    try:
        # Framing: 单行 JSON + \n，UTF-8 编码（§6.2.1）
        line = (json.dumps(payload, ensure_ascii=False) + "\n").encode("utf-8")
        s.sendall(line)
        # 读响应（同样以 \n 分帧）
        chunks = []
        while True:
            buf = s.recv(65536)
            if not buf:
                break
            chunks.append(buf)
            if b"\n" in buf:
                break
        if not chunks:
            return {}
        data = b"".join(chunks).split(b"\n", 1)[0]
        if not data:
            return {}
        return json.loads(data.decode("utf-8"))
    except Exception as e:
        log_stderr(f"socket call failed: {e}")
        return {}
    finally:
        try:
            s.close()
        except Exception:
            pass


def cmd_ask(stdin_json, tab_id):
    """阻塞，输出 updatedInput 或 deny（§6.2.2）。"""
    tool_input = stdin_json.get("tool_input", {}) or {}
    tool_name = stdin_json.get("tool_name", "") or ""
    tool_use_id = stdin_json.get("tool_use_id", "") or ""
    session_id = stdin_json.get("session_id", "") or ""
    payload = {
        "kind": "ask",
        "tab_id": tab_id,
        "session_id": session_id,
        "tool_use_id": tool_use_id,
        "tool_name": tool_name,
        "tool_input": tool_input,
        # ask_kind 由 Mac App 根据 tool_name 判定（user_question vs tool_approval）
    }
    response = socket_call(payload, ASK_RESPONSE_TIMEOUT)
    if not response:
        # 软失败：socket 不可达 / Mac App 没响应 → 让 SDK 走 fallback
        return {}
    if response.get("error"):
        # 关键软失败语义（NFR-U1/U2）：任何 error（含 timeout / unknown tab / decode 失败）
        # 都不能让 cc-anywhere 比"没装 hook"更糟，必须返回 {} 让 SDK 走 TUI fallback。
        # 历史误实现：曾翻译为 permissionDecision: deny → 会被 SDK 解读为"工具被拒绝"，
        # 实际场景：用户 phone 离线 timeout → Claude 拒绝执行工具（错），应让 TUI fallback 弹原问题。
        log_stderr(f"ask path soft-fail: {response['error']}")
        return {}
    # tool_approval 分支
    if response.get("ask_kind") == "tool_approval":
        decision = response.get("decision", "deny")
        return {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": decision,  # allow | deny
                "permissionDecisionReason": response.get("reason", "")
            }
        }
    # AskUserQuestion 分支：返回 updatedInput 让 SDK 跳过 TUI 弹窗
    answers = response.get("answers", {}) or {}
    questions = tool_input.get("questions", [])
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "updatedInput": {
                "questions": questions,
                "answers": answers
            }
        }
    }


def cmd_progress(stdin_json, tab_id, phase):
    """fire-and-forget。无论是否成功都返回 {}。"""
    payload = {
        "kind": f"progress_{phase}",  # progress_pre / progress_post
        "tab_id": tab_id,
        "tool_use_id": stdin_json.get("tool_use_id", "") or "",
        "tool_name": stdin_json.get("tool_name", "") or "",
        "tool_input": stdin_json.get("tool_input", {}) or {},
    }
    if phase == "post":
        payload["tool_response"] = stdin_json.get("tool_response", {}) or {}
    socket_call(payload, FIRE_AND_FORGET_TIMEOUT)
    return {}


def cmd_notification(stdin_json, tab_id):
    """fire-and-forget。"""
    payload = {
        "kind": "notification",
        "tab_id": tab_id,
        "notification": stdin_json.get("message", "") or "",
        "title": stdin_json.get("title", "Claude") or "Claude",
        "notification_type": stdin_json.get("type", "idle") or "idle",
    }
    socket_call(payload, FIRE_AND_FORGET_TIMEOUT)
    return {}


def main():
    with safe_exit_with_empty():
        # 保护 1：env 不存在立即放行（R-F1-002）
        tab_id = must_have_tab_id()
        if tab_id is None:
            sys.stdout.write("{}\n")
            sys.stdout.flush()
            return

        # 子命令路由
        args = sys.argv[1:]
        if not args:
            sys.stdout.write("{}\n")
            sys.stdout.flush()
            return

        # 读 stdin（hook 协议 stdin 是 JSON）
        try:
            stdin_data = sys.stdin.read()
            stdin_json = json.loads(stdin_data) if stdin_data.strip() else {}
        except Exception as e:
            log_stderr(f"stdin parse failed: {e}")
            sys.stdout.write("{}\n")
            sys.stdout.flush()
            return

        cmd = args[0]
        if cmd == "ask":
            result = cmd_ask(stdin_json, tab_id)
        elif cmd == "progress" and len(args) >= 2:
            phase = args[1]  # "pre" or "post"
            if phase not in ("pre", "post"):
                result = {}
            else:
                result = cmd_progress(stdin_json, tab_id, phase)
        elif cmd == "notification":
            result = cmd_notification(stdin_json, tab_id)
        else:
            result = {}

        sys.stdout.write(json.dumps(result, ensure_ascii=False) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
