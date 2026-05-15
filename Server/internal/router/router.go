// Package router dispatches authenticated envelopes between Mac and phones.
// It owns no state — pure forwarding plus a few type-specific side effects
// (e.g. image.fetched → image.Service cleanup).
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

// RouteFromMac forwards a Mac-originated envelope to phones. Returns an
// error envelope if the type is unroutable; otherwise nil.
func (r *Router) RouteFromMac(env *protocol.Envelope) *protocol.Envelope {
	switch env.Type {
	case protocol.TypeMsgStream,
		protocol.TypeMsgRaw,
		protocol.TypeMsgHistoryResponse,
		protocol.TypeTabList,
		protocol.TypeTabListResponse,
		protocol.TypeSlashListResponse,
		protocol.TypeTabChanged,
		protocol.TypeInputError,
		// 4.7 Hook 实时桥接：mac→phone
		protocol.TypeAskQuestionPending,
		protocol.TypeAskQuestionAnswered,
		protocol.TypeAskQuestionTimeout,
		protocol.TypeToolProgressPre,
		protocol.TypeToolProgressPost,
		protocol.TypeNotification:
		r.phone.BroadcastToPhones(env)
		return nil
	}
	// Anything else from Mac is silently ignored (could be device.* handled
	// elsewhere or an unknown type). We don't error out the connection.
	return nil
}

// RouteFromPhone forwards a phone-originated envelope to the Mac. Returns an
// error envelope (caller sends to the phone) when Mac is offline or msg is
// unroutable.
func (r *Router) RouteFromPhone(ctx context.Context, env *protocol.Envelope) *protocol.Envelope {
	switch env.Type {
	case protocol.TypeInputText,
		protocol.TypeToolUseApprove,
		protocol.TypeMsgHistoryRequest,
		protocol.TypeTabListRequest,
		protocol.TypeSlashListRequest,
		// 4.7 Hook 实时桥接：phone→mac
		protocol.TypeAskQuestionAnswer,
		protocol.TypeAskToolApprovalAnswer:
		if !r.mac.HasMac() {
			return errorEnvelope(protocol.CodeMacOffline, "mac is offline")
		}
		r.mac.MacConnSend(env)
		return nil
	}
	slog.Debug("unroutable from phone", "type", env.Type)
	return nil
}

// RouteImageFetched is called when the router sees image.fetched from Mac.
// It still gets forwarded as a normal "from-mac" event (in case a phone wants
// to know), but the real work is image cleanup.
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
