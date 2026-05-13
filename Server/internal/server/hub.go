package server

import (
	"log/slog"
	"sync"

	"github.com/yoolines/cc-anywhere/internal/protocol"
)

// Hub owns the live connection registry. Exactly one Mac connection is
// allowed at a time; phones are keyed by token hash so the same sub_token
// reconnecting kicks the prior socket.
type Hub struct {
	mu         sync.RWMutex
	macConn    *Connection
	phoneConns map[string]*Connection // tokenHash -> conn
}

func NewHub() *Hub {
	return &Hub{phoneConns: make(map[string]*Connection)}
}

// AcceptMac registers conn as THE mac connection, kicking any previous one.
// Returns the previously-bound mac (or nil) so the caller can run any
// presence side effects after the hub mutex is released.
func (h *Hub) AcceptMac(conn *Connection) (previous *Connection) {
	h.mu.Lock()
	previous = h.macConn
	h.macConn = conn
	h.mu.Unlock()

	if previous != nil {
		env, _ := protocol.NewEnvelope(protocol.TypeForceDisconnect, protocol.ForceDisconnect{Reason: "new_session"})
		previous.SendAndClose(env, "new_session")
	}
	slog.Info("mac connected", "conn", conn.ID)
	return previous
}

// AcceptPhone registers a phone keyed by sub_token hash, kicking any earlier
// socket using the same token (R-S2-03).
func (h *Hub) AcceptPhone(conn *Connection) (previous *Connection) {
	h.mu.Lock()
	previous = h.phoneConns[conn.TokenHash]
	h.phoneConns[conn.TokenHash] = conn
	h.mu.Unlock()

	if previous != nil {
		env, _ := protocol.NewEnvelope(protocol.TypeForceDisconnect, protocol.ForceDisconnect{Reason: "new_session"})
		previous.SendAndClose(env, "new_session")
	}
	slog.Info("phone connected", "conn", conn.ID, "device", conn.DeviceName)
	return previous
}

// RemoveConnection drops conn from the registry if it's still the live one
// for its key. It will not unset a newer connection that has already replaced
// it (which matters when the kick-old codepath races with the old socket's
// own close).
func (h *Hub) RemoveConnection(conn *Connection) (wasMac bool) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if conn.Kind == ConnKindMac && h.macConn == conn {
		h.macConn = nil
		return true
	}
	if conn.Kind == ConnKindPhone {
		if existing, ok := h.phoneConns[conn.TokenHash]; ok && existing == conn {
			delete(h.phoneConns, conn.TokenHash)
		}
	}
	return false
}

// MacConn returns the current Mac connection (may be nil).
func (h *Hub) MacConn() *Connection {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return h.macConn
}

// PhoneConns returns a snapshot slice of phone connections.
func (h *Hub) PhoneConns() []*Connection {
	h.mu.RLock()
	defer h.mu.RUnlock()
	out := make([]*Connection, 0, len(h.phoneConns))
	for _, c := range h.phoneConns {
		out = append(out, c)
	}
	return out
}

// PhoneByHash returns the phone connection bound to tokenHash, if any.
func (h *Hub) PhoneByHash(tokenHash string) *Connection {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return h.phoneConns[tokenHash]
}

// PhoneNames returns the device_name of every active phone, in arbitrary order.
func (h *Hub) PhoneNames() []string {
	h.mu.RLock()
	defer h.mu.RUnlock()
	names := make([]string, 0, len(h.phoneConns))
	for _, c := range h.phoneConns {
		names = append(names, c.DeviceName)
	}
	return names
}

// BroadcastToPhones is best-effort — slow consumers get disconnected by
// Connection.Send, not back-pressure the hub.
func (h *Hub) BroadcastToPhones(env *protocol.Envelope) {
	for _, c := range h.PhoneConns() {
		_ = c.Send(env)
	}
}

// PhoneCount satisfies presence.Broadcaster.
func (h *Hub) PhoneCount() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.phoneConns)
}

// MacConnSend is a no-op when Mac is offline so presence callers can fire
// blindly without nil-checking.
func (h *Hub) MacConnSend(env *protocol.Envelope) {
	if c := h.MacConn(); c != nil {
		_ = c.Send(env)
	}
}

// HasMac reports whether a Mac connection is registered. Used by image and
// router via MacSink interface.
func (h *Hub) HasMac() bool {
	return h.MacConn() != nil
}
