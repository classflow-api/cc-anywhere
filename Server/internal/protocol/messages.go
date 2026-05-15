// Package protocol defines the WebSocket message envelope, all message type
// constants, error codes and helper constructors shared by Mac/Phone/Server.
//
// On-wire format (every message): {"type":"...","id":"uuid","ts":"ISO8601","data":{...}}.
// Data payload is kept as json.RawMessage so the router can forward without
// double-decoding; concrete handlers unmarshal into the typed structs below.
package protocol

import (
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"time"

	"github.com/google/uuid"
)

// Message type constants — must match needs-spec §3.4 exactly. The three
// clients depend on these string values.
const (
	// 4.1 鉴权与连接
	TypeBind            = "bind"
	TypeBindAck         = "bind.ack"
	TypeBindError       = "bind.error"
	TypePing            = "ping"
	TypePong            = "pong"
	TypeForceDisconnect = "force_disconnect"

	// 4.2 设备管理
	TypeDeviceCreateSubtoken  = "device.create_subtoken"
	TypeDeviceSubtokenCreated = "device.subtoken.created"
	TypeDeviceBound           = "device.bound"
	TypeDeviceList            = "device.list"
	TypeDeviceListResponse    = "device.list.response"
	TypeDeviceRevoke          = "device.revoke"
	TypeDeviceRevoked         = "device.revoked"
	TypeDeviceSelfUnbind      = "device.self_unbind"

	// 4.3 Tab 管理
	TypeTabList         = "tab.list"
	TypeTabListRequest  = "tab.list.request"
	TypeTabListResponse = "tab.list.response"
	TypeTabChanged      = "tab.changed"

	// 4.4 消息流
	TypeMsgStream          = "msg.stream"
	TypeMsgHistoryRequest  = "msg.history.request"
	TypeMsgHistoryResponse = "msg.history.response"
	TypeMsgRaw             = "msg.raw"

	// 4.5 输入
	TypeInputText          = "input.text"
	TypeImageUploadBegin   = "image.upload.begin"
	TypeImageUploadURL     = "image.upload.url"
	TypeInputImage         = "input.image"
	TypeImageFetched       = "image.fetched"
	TypeImageUploadExpired   = "image.upload.expired"
	TypeImageDownloadRequest = "image.download.url"          // phone -> server, by upload_id
	TypeImageDownloadResp    = "image.download.url.response" // server -> phone, with signed url
	TypeSlashListRequest     = "slash.list.request"           // phone -> mac via server
	TypeSlashListResponse    = "slash.list.response"          // mac -> phone via server
	TypeToolUseApprove       = "tool_use.approve"
	TypeInputError         = "input.error"

	// 4.6 presence
	TypePresenceMacOnline  = "presence.mac_online"
	TypePresenceMacOffline = "presence.mac_offline"
	TypePresencePhoneCount = "presence.phone_count"

	// 4.7 Hook 实时桥接（cc-anywhere AskUserQuestion 远程交互）
	TypeAskQuestionPending    = "ask.question.pending"
	TypeAskQuestionAnswer     = "ask.question.answer"
	TypeAskQuestionAnswered   = "ask.question.answered"
	TypeAskQuestionTimeout    = "ask.question.timeout"
	TypeAskToolApprovalAnswer = "ask.tool_approval.answer"
	TypeToolProgressPre       = "tool.progress.pre"
	TypeToolProgressPost      = "tool.progress.post"
	TypeNotification          = "notification"

	// 通用错误
	TypeError = "error"
)

// Error codes — clients pattern-match on these strings.
const (
	CodeInvalidToken   = "INVALID_TOKEN"
	CodeTokenExpired   = "TOKEN_EXPIRED"
	CodeRevoked        = "REVOKED"
	CodeMacOffline     = "MAC_OFFLINE"
	CodeTabNotFound    = "TAB_NOT_FOUND"
	CodeImageTooLarge  = "IMAGE_TOO_LARGE"
	CodeSha256Mismatch = "SHA256_MISMATCH"
	CodeInternal       = "INTERNAL"
)

// Pre-allocated sentinel errors so handlers can return early without
// constructing a new Envelope; the server's write path wraps these into
// proper error envelopes.
var (
	ErrInvalidToken   = errors.New(CodeInvalidToken)
	ErrTokenExpired   = errors.New(CodeTokenExpired)
	ErrRevoked        = errors.New(CodeRevoked)
	ErrMacOffline     = errors.New(CodeMacOffline)
	ErrTabNotFound    = errors.New(CodeTabNotFound)
	ErrImageTooLarge  = errors.New(CodeImageTooLarge)
	ErrSha256Mismatch = errors.New(CodeSha256Mismatch)
	ErrInternal       = errors.New(CodeInternal)
)

// Envelope is the on-wire shape of every message. Data is kept raw so the
// router can forward Mac<->Phone without parsing payload internals.
type Envelope struct {
	Type string          `json:"type"`
	ID   string          `json:"id"`
	TS   string          `json:"ts"`
	Data json.RawMessage `json:"data,omitempty"`
}

// NewEnvelope builds an envelope with a fresh UUID and current UTC timestamp.
// Pass nil data to omit the data field on the wire.
func NewEnvelope(msgType string, data any) (*Envelope, error) {
	env := &Envelope{
		Type: msgType,
		ID:   uuid.NewString(),
		TS:   time.Now().UTC().Format(time.RFC3339Nano),
	}
	if data != nil {
		raw, err := json.Marshal(data)
		if err != nil {
			return nil, fmt.Errorf("marshal data: %w", err)
		}
		env.Data = raw
	}
	return env, nil
}

// MustEnvelope panics on marshal failure; used only for fixed, controlled payloads.
func MustEnvelope(msgType string, data any) *Envelope {
	env, err := NewEnvelope(msgType, data)
	if err != nil {
		panic(err)
	}
	return env
}

// DecodeData unmarshals env.Data into out. Returns nil if Data is empty
// so callers can use ack-style messages.
func (e *Envelope) DecodeData(out any) error {
	if len(e.Data) == 0 {
		return nil
	}
	return json.Unmarshal(e.Data, out)
}

// ---- 4.1 鉴权 ----

// BindRequest payload for both "mac" and "phone" bind types.
// Phone bind populates DeviceName/Model/OSVersion.
type BindRequest struct {
	Type        string `json:"type"`
	Token       string `json:"token"`
	DeviceName  string `json:"device_name,omitempty"`
	DeviceModel string `json:"device_model,omitempty"`
	OSVersion   string `json:"os_version,omitempty"`
}

type BindAck struct {
	AgentID      string `json:"agent_id,omitempty"`
	SessionToken string `json:"session_token,omitempty"`
}

type BindError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type ForceDisconnect struct {
	Reason string `json:"reason"`
}

type ErrorPayload struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// ---- 4.2 设备 ----
//
// sub_token id is serialized as a JSON *string* on the wire to keep the
// contract identical across Go (int64), Swift (String) and Dart (String).
// The DB still stores INTEGER PRIMARY KEY; SubTokenID is the decimal repr
// of that integer. Use FormatSubTokenID / ParseSubTokenID helpers.

type DeviceSubtokenCreated struct {
	SubToken  string `json:"sub_token"` // 原文，仅此次返回
	ID        string `json:"id"`        // decimal repr of int64
	ExpiresAt string `json:"expires_at"`
}

type DeviceBound struct {
	SubTokenID  string `json:"sub_token_id"` // decimal repr of int64
	DeviceName  string `json:"device_name"`
	DeviceModel string `json:"device_model"`
	OSVersion   string `json:"os_version"`
	BoundAt     string `json:"bound_at"`
}

type DeviceListResponse struct {
	Devices []DeviceInfo `json:"devices"`
}

type DeviceInfo struct {
	ID          string `json:"id"` // decimal repr of int64
	DeviceName  string `json:"device_name"`
	DeviceModel string `json:"device_model"`
	OSVersion   string `json:"os_version"`
	Status      string `json:"status"`
	BoundAt     string `json:"bound_at,omitempty"`
	LastSeenAt  string `json:"last_seen_at,omitempty"`
	Online      bool   `json:"online"`
}

type DeviceRevoke struct {
	SubTokenID string `json:"sub_token_id"` // decimal repr of int64
}

type DeviceRevoked struct {
	SubTokenID string `json:"sub_token_id"` // decimal repr of int64
}

// FormatSubTokenID converts the DB int64 id to its on-wire string form.
func FormatSubTokenID(id int64) string {
	return strconv.FormatInt(id, 10)
}

// ParseSubTokenID parses an on-wire string id back to int64 for DB use.
// Returns an error if the string is empty or not a valid integer.
func ParseSubTokenID(s string) (int64, error) {
	if s == "" {
		return 0, fmt.Errorf("empty sub_token_id")
	}
	return strconv.ParseInt(s, 10, 64)
}

// ---- 4.3 Tab ----

type TabSummary struct {
	ID             string `json:"id"`
	Name           string `json:"name"`
	Folder         string `json:"folder"`
	ClaudeStatus   string `json:"claude_status,omitempty"`
	LastActivityAt string `json:"last_activity_at,omitempty"`
}

type TabList struct {
	Tabs []TabSummary `json:"tabs"`
}

type TabChanged struct {
	Tab    TabSummary `json:"tab"`
	Action string     `json:"action"` // added | removed | renamed
}

// ---- 4.4 消息流 ----

type MsgStream struct {
	TabID    string            `json:"tab_id"`
	Messages []json.RawMessage `json:"messages"`
}

type MsgHistoryRequest struct {
	TabID  string `json:"tab_id"`
	Limit  int    `json:"limit"`
	Before string `json:"before,omitempty"`
}

type MsgHistoryResponse struct {
	TabID    string            `json:"tab_id"`
	Messages []json.RawMessage `json:"messages"`
	HasMore  bool              `json:"has_more"`
}

type MsgRaw struct {
	TabID      string `json:"tab_id"`
	Line       string `json:"line"`
	ParseError string `json:"parse_error"`
}

// ---- 4.5 输入 / 图片 ----

type InputText struct {
	TabID string `json:"tab_id"`
	Text  string `json:"text"`
}

type ImageUploadBegin struct {
	TabID    string `json:"tab_id"`
	Filename string `json:"filename"`
	Size     int64  `json:"size"`
	Sha256   string `json:"sha256"`
}

type ImageUploadURL struct {
	UploadID  string `json:"upload_id"`
	UploadURL string `json:"upload_url"`
}

type InputImage struct {
	TabID    string `json:"tab_id"`
	ImageURL string `json:"image_url"`
	Filename string `json:"filename"`
	Sha256   string `json:"sha256"`
	UploadID string `json:"upload_id"`
}

type ImageFetched struct {
	UploadID string `json:"upload_id"`
}

type ImageUploadExpired struct {
	UploadID string `json:"upload_id"`
}

type ImageDownloadRequest struct {
	UploadID string `json:"upload_id"`
}

type ImageDownloadResponse struct {
	UploadID string `json:"upload_id"`
	ImageURL string `json:"image_url"` // 空表示 server 上图片已不存在(过期/未上传)
	Filename string `json:"filename"`
}

type SlashCommand struct {
	Name        string `json:"name"`        // 不带前导 "/",如 "clear"
	Description string `json:"description"` // 可选简短描述(若 .md 有 frontmatter description 则填)
	Source      string `json:"source"`      // "builtin" | "user" | "project" | "plugin:<name>"
}

type SlashListRequest struct {
	TabID string `json:"tab_id"`
}

type SlashListResponse struct {
	TabID    string         `json:"tab_id"`
	Commands []SlashCommand `json:"commands"`
}

type ToolUseApprove struct {
	TabID  string `json:"tab_id"`
	Action string `json:"action"` // approve | reject | always_approve
}

type InputError struct {
	TabID   string `json:"tab_id"`
	Message string `json:"message"`
}

// ---- 4.6 presence ----

type PresencePhoneCount struct {
	Count int      `json:"count"`
	Names []string `json:"names"`
}

// ---- 4.7 Hook 实时桥接 ----
//
// 这些 payload 仅用于 Server 路由识别字段名，实际编解码在 Mac App 与 Phone
// 端完成；Server 不解析内层结构，原样转发 Envelope.Data。

// AskQuestionPending 由 Mac App 发起，Server 广播到所有 phone（及未来回流给
// Mac App 自身的副本由客户端本地直接渲染，不走 Server）。
// AskKind 取值：user_question | tool_approval。
// AllowOther 控制 phone 端"自定义回答"输入框可见性。
type AskQuestionPending struct {
	RequestID  string                   `json:"request_id"`
	TabID      string                   `json:"tab_id"`
	ToolUseID  string                   `json:"tool_use_id"`
	AskKind    string                   `json:"ask_kind"`
	AllowOther bool                     `json:"allow_other"`
	Questions  []map[string]interface{} `json:"questions,omitempty"`
	ToolName   string                   `json:"tool_name,omitempty"`
	ToolInput  map[string]interface{}   `json:"tool_input,omitempty"`
}

// AskQuestionAnswer 由 phone（或 Mac App 自身）回传给 mac 端 HookIpcServer，
// 由 mac 端做 winner 锁仲裁。
type AskQuestionAnswer struct {
	RequestID string            `json:"request_id"`
	Answers   map[string]string `json:"answers"`
}

// AskToolApprovalAnswer phone → server → mac，工具批准决策回执。
// Mac 端 hook bridge 收到后翻译为 PreToolUse permissionDecision: allow|deny。
// Reason 为可选用户附加拒绝原因（R-F4-005）；server 仅转发不解析内层结构。
type AskToolApprovalAnswer struct {
	RequestID string `json:"request_id"`
	Decision  string `json:"decision"`         // "allow" | "deny"
	Reason    string `json:"reason,omitempty"` // 用户附加的拒绝原因（可选）
}

// AskQuestionAnswered 由 mac 端在某 endpoint winner 确认后广播给所有 phone，
// 让其他 phone 把卡片切到"已被回答"状态。
type AskQuestionAnswered struct {
	RequestID  string            `json:"request_id"`
	AnsweredBy string            `json:"answered_by"`
	Answers    map[string]string `json:"answers"`
}

// AskQuestionTimeout 由 mac 端在 5 分钟内无人回答时广播，所有 phone 撤销卡片。
type AskQuestionTimeout struct {
	RequestID string `json:"request_id"`
	Reason    string `json:"reason"` // timeout | cancelled
}

// ToolProgressPre 由 mac 端在 PreToolUse hook 触发时推送给 phone。
type ToolProgressPre struct {
	TabID     string                 `json:"tab_id"`
	ToolUseID string                 `json:"tool_use_id"`
	ToolName  string                 `json:"tool_name"`
	ToolInput map[string]interface{} `json:"tool_input"`
}

// ToolProgressPost 由 mac 端在 PostToolUse hook 触发时推送给 phone。
type ToolProgressPost struct {
	TabID     string `json:"tab_id"`
	ToolUseID string `json:"tool_use_id"`
	ToolName  string `json:"tool_name"`
	Success   bool   `json:"success"`
	Error     string `json:"error,omitempty"`
}

// Notification 由 mac 端在 Notification hook 触发时推送给 phone。
type Notification struct {
	TabID            string `json:"tab_id"`
	NotificationType string `json:"notification_type"` // idle | permission_prompt | error
	Title            string `json:"title"`
	Message          string `json:"message"`
}
