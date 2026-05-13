package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"sync"
	"sync/atomic"
	"time"

	"nhooyr.io/websocket"

	"github.com/yoolines/cc-anywhere/internal/protocol"
)

// ConnKind identifies whether a Connection represents the single Mac or a phone.
type ConnKind int

const (
	ConnKindUnbound ConnKind = iota
	ConnKindMac
	ConnKindPhone
)

const (
	pingInterval  = 15 * time.Second
	writeTimeout  = 10 * time.Second
	bindTimeout   = 60 * time.Second
	readSizeLimit = 4 << 20 // 4 MiB; well above any normal msg.stream batch
)

// Connection is the per-WebSocket actor: a goroutine reads frames, another
// drains the out channel and writes them. All writes go through Send so the
// caller never blocks the read loop.
type Connection struct {
	ID         string // random short id for logs
	Kind       ConnKind
	TokenHash  string // for phones; empty for mac/unbound
	DeviceName string // for phones

	ws     *websocket.Conn
	out    chan *protocol.Envelope
	closed atomic.Bool

	closeOnce sync.Once
	closeCh   chan struct{}
}

func newConnection(ws *websocket.Conn, id string) *Connection {
	ws.SetReadLimit(readSizeLimit)
	return &Connection{
		ID:      id,
		ws:      ws,
		out:     make(chan *protocol.Envelope, 64),
		closeCh: make(chan struct{}),
	}
}

// Send enqueues env for delivery. Drops + closes the connection on send timeout
// so a stuck client cannot wedge the hub goroutine.
func (c *Connection) Send(env *protocol.Envelope) error {
	if c.closed.Load() {
		return errors.New("connection closed")
	}
	select {
	case c.out <- env:
		return nil
	case <-c.closeCh:
		return errors.New("connection closed")
	case <-time.After(time.Second):
		// Slow consumer — disconnect rather than back-pressure the hub.
		c.Close("send_timeout")
		return errors.New("send timeout")
	}
}

// SendAndClose sends env (best-effort) then closes the underlying WebSocket
// with a normal close code so the client sees a graceful shutdown.
func (c *Connection) SendAndClose(env *protocol.Envelope, reason string) {
	if env != nil {
		select {
		case c.out <- env:
		default:
		}
	}
	c.Close(reason)
}

// Close is idempotent.
func (c *Connection) Close(reason string) {
	c.closeOnce.Do(func() {
		c.closed.Store(true)
		close(c.closeCh)
		_ = c.ws.Close(websocket.StatusNormalClosure, reason)
	})
}

// writeLoop drains c.out and sends ping frames on idle ticks. It exits when
// the connection closes or any write errors out.
func (c *Connection) writeLoop(ctx context.Context) {
	ticker := time.NewTicker(pingInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-c.closeCh:
			return
		case env, ok := <-c.out:
			if !ok {
				return
			}
			if err := c.writeEnvelope(ctx, env); err != nil {
				slog.Debug("write envelope failed", "conn", c.ID, "err", err)
				c.Close("write_error")
				return
			}
		case <-ticker.C:
			wctx, cancel := context.WithTimeout(ctx, writeTimeout)
			err := c.ws.Ping(wctx)
			cancel()
			if err != nil {
				slog.Debug("ping failed", "conn", c.ID, "err", err)
				c.Close("ping_error")
				return
			}
		}
	}
}

func (c *Connection) writeEnvelope(ctx context.Context, env *protocol.Envelope) error {
	wctx, cancel := context.WithTimeout(ctx, writeTimeout)
	defer cancel()
	raw, err := json.Marshal(env)
	if err != nil {
		return fmt.Errorf("marshal: %w", err)
	}
	return c.ws.Write(wctx, websocket.MessageText, raw)
}

// readEnvelope reads one JSON message. Application-level pong messages are
// transparently consumed and not surfaced to the caller; ping frames at the
// websocket layer are auto-handled by nhooyr.
func (c *Connection) readEnvelope(ctx context.Context) (*protocol.Envelope, error) {
	for {
		_, data, err := c.ws.Read(ctx)
		if err != nil {
			return nil, err
		}
		var env protocol.Envelope
		if err := json.Unmarshal(data, &env); err != nil {
			return nil, fmt.Errorf("parse envelope: %w", err)
		}
		// Reply to app-level ping so Mac/Phone implementations that send
		// {"type":"ping"} (in addition to WS pings) get a fast answer.
		switch env.Type {
		case protocol.TypePing:
			pong, _ := protocol.NewEnvelope(protocol.TypePong, nil)
			_ = c.Send(pong)
			continue
		case protocol.TypePong:
			continue
		}
		return &env, nil
	}
}

// sendError wraps code/message in the standard error envelope.
func (c *Connection) sendError(code, message string) {
	env, _ := protocol.NewEnvelope(protocol.TypeError, protocol.ErrorPayload{
		Code: code, Message: message,
	})
	_ = c.Send(env)
}
