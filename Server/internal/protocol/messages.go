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
