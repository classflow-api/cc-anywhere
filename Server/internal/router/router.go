// Package router dispatches authenticated envelopes between Mac and phones.
//
// 设计原则（dumb proxy / "哑代理"）：
// Server 只负责注册（bind / 鉴权 / 设备绑定）、发现（presence / device.*）、
// 内部能力（image upload/download）。**业务协议完全由 Mac/Phone 端自己定义**，
// Server 对未知 type 一律透传：
//   - Mac → 任意 type → BroadcastToPhones
//   - Phone → 任意 type → MacConnSend（mac 离线返回 MAC_OFFLINE）
//
// 收益：Mac/Phone 加任何新 type / 协议演进都**不需要**重新部署 Server。
// 上次本需求 L4 加 7 个 type 时必须 docker rebuild，将来不会再发生。
//
// 安全性：Server 内部处理的 type（bind/device/image/presence/force_disconnect/error）
// 已由 server.go 的 dispatchFromMac / dispatchFromPhone 在 `default` 分支 *之前*
// case 拦截掉，不会进入本 router。即便 Mac/Phone 误发这些 type 进 router，对端
// 收到也只是把它当作未知 type 默默丢弃（不影响协议）。
package router

import (
	"context"
	"log/slog"

	"github.com/yoolines/cc-anywhere/internal/protocol"
)

// MacSink / PhoneSink are the bits of the hub that the router needs.
type MacSink interface {
	MacConnSend(env *protocol.Envelope)
	HasMac() bool
}

type PhoneSink interface {
	BroadcastToPhones(env *protocol.Envelope)
}

// ImageHook lets the router notify the image service when a Mac confirms a
// fetch (image.fetched) so the temp file is deleted immediately.
type ImageHook interface {
	HandleFetched(ctx context.Context, uploadID string)
}

// Router fans envelopes in the appropriate direction.
type Router struct {
	mac   MacSink
	phone PhoneSink
	image ImageHook
}

func New(mac MacSink, phone PhoneSink, image ImageHook) *Router {
	return &Router{mac: mac, phone: phone, image: image}
}

// RouteFromMac broadcasts any Mac-originated business envelope to all phones.
// 不再为每个新 type 维护白名单 —— 未识别 type 也无脑透传（dumb proxy）。
// Server-internal types (bind/device/image/presence/force_disconnect/error)
// 在 server.go dispatchFromMac 内部已先行处理，不会进入这里。
func (r *Router) RouteFromMac(env *protocol.Envelope) *protocol.Envelope {
	r.phone.BroadcastToPhones(env)
	return nil
}

// RouteFromPhone forwards any phone-originated business envelope to the Mac.
// 不再为每个新 type 维护白名单。Mac 离线则返回 MAC_OFFLINE error 给 phone。
// Server-internal types 同上由 dispatchFromPhone 前置处理。
func (r *Router) RouteFromPhone(ctx context.Context, env *protocol.Envelope) *protocol.Envelope {
	if !r.mac.HasMac() {
		slog.Debug("phone msg dropped: mac offline", "type", env.Type)
		return errorEnvelope(protocol.CodeMacOffline, "mac is offline")
	}
	r.mac.MacConnSend(env)
	return nil
}

// RouteImageFetched is called when the router sees image.fetched from Mac.
// 这是 server-internal 路径（清理 inbox 临时文件），不走 RouteFromMac。
func (r *Router) RouteImageFetched(ctx context.Context, env *protocol.Envelope) {
	if r.image == nil {
		return
	}
	var payload protocol.ImageFetched
	if err := env.DecodeData(&payload); err != nil {
		slog.Warn("image.fetched decode", "err", err)
		return
	}
	r.image.HandleFetched(ctx, payload.UploadID)
}

func errorEnvelope(code, message string) *protocol.Envelope {
	env, _ := protocol.NewEnvelope(protocol.TypeError, protocol.ErrorPayload{
		Code: code, Message: message,
	})
	return env
}

// HasMacWrapper is a thin Adapter so Hub.MacConn() != nil satisfies MacSink.
// Implemented as a helper here rather than another file just to keep package
// dependencies tidy.
type macSinkAdapter struct {
	send   func(*protocol.Envelope)
	hasMac func() bool
}

func (a macSinkAdapter) MacConnSend(env *protocol.Envelope) { a.send(env) }
func (a macSinkAdapter) HasMac() bool                       { return a.hasMac() }

// NewMacSink wraps a (send, hasMac) pair into the MacSink interface.
func NewMacSink(send func(*protocol.Envelope), hasMac func() bool) MacSink {
	return macSinkAdapter{send: send, hasMac: hasMac}
}
