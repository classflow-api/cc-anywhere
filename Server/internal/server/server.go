// Package server wires the WebSocket + HTTP listeners and runs the per-conn
// dispatch loop. Auth/device/router/presence/image are injected so they can
// be exercised in isolation.
package server

import (
	"context"
	"crypto/tls"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"nhooyr.io/websocket"

	"github.com/yoolines/cc-anywhere/internal/auth"
	"github.com/yoolines/cc-anywhere/internal/config"
	"github.com/yoolines/cc-anywhere/internal/device"
	"github.com/yoolines/cc-anywhere/internal/image"
	"github.com/yoolines/cc-anywhere/internal/presence"
	"github.com/yoolines/cc-anywhere/internal/protocol"
	"github.com/yoolines/cc-anywhere/internal/router"
)

// Server is the top-level runtime. Build with New, then Run.
type Server struct {
	cfg      *config.Config
	db       *sql.DB
	hub      *Hub
	auth     *auth.Service
	device   *device.Service
	router   *router.Router
	presence *presence.Service
	image    *image.Service

	httpSrv *http.Server
}

// New constructs the wiring. Caller still owns db.
func New(cfg *config.Config, db *sql.DB) (*Server, error) {
	hub := NewHub()
	authSvc := auth.New(db)
	deviceSvc := device.New(db)
	presenceSvc := presence.New(hub)

	imageSvc, err := image.New(cfg.Image.InboxDir, cfg.Server.PublicHost, []byte(cfg.Image.HMACSecret), hub, hub)
	if err != nil {
		return nil, fmt.Errorf("image svc: %w", err)
	}

	macSink := router.NewMacSink(hub.MacConnSend, func() bool { return hub.MacConn() != nil })
	r := router.New(macSink, hub, imageSvc)

	s := &Server{
		cfg:      cfg,
		db:       db,
		hub:      hub,
		auth:     authSvc,
		device:   deviceSvc,
		router:   r,
		presence: presenceSvc,
		image:    imageSvc,
	}
	return s, nil
}

// Run launches the TLS HTTPS server (WebSocket on /ws, image HTTP on
// /upload/{id} and /download/{id}, /healthz). It blocks until ctx is cancelled
// or the listener errors out.
func (s *Server) Run(ctx context.Context) error {
	s.device.StartPendingGC(ctx, time.Minute)
	s.image.StartGC(ctx)

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	mux.HandleFunc("/ws", s.handleWS(ctx))
	mux.HandleFunc("/upload/", s.image.HandleUploadHTTP)
	mux.HandleFunc("/download/", s.image.HandleDownloadHTTP)

	tlsCfg := &tls.Config{
		MinVersion: tls.VersionTLS12,
		CipherSuites: []uint16{
			tls.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
			tls.TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
			tls.TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305,
			tls.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
			tls.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
			tls.TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305,
		},
	}
	s.httpSrv = &http.Server{
		Addr:              s.cfg.Server.Address,
		Handler:           mux,
		TLSConfig:         tlsCfg,
		ReadHeaderTimeout: 15 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		slog.Info("server listening", "addr", s.cfg.Server.Address)
		errCh <- s.httpSrv.ListenAndServeTLS(s.cfg.Server.TLS.CertFile, s.cfg.Server.TLS.KeyFile)
	}()

	select {
	case <-ctx.Done():
		shutCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = s.httpSrv.Shutdown(shutCtx)
		return nil
	case err := <-errCh:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return err
	}
}

// handleWS upgrades, runs bind, then enters the per-connection loop.
func (s *Server) handleWS(ctx context.Context) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ws, err := websocket.Accept(w, r, &websocket.AcceptOptions{
			// We don't issue CORS-protected pages, but allow any origin so
			// development tools connecting from arbitrary hosts work.
			InsecureSkipVerify: true,
		})
		if err != nil {
			slog.Warn("ws accept", "err", err)
			return
		}
		connID := uuid.NewString()[:8]
		conn := newConnection(ws, connID)

		// Bind must arrive within 60s (R-S1-03).
		bindCtx, cancel := context.WithTimeout(ctx, bindTimeout)
		bindErr := s.bind(bindCtx, conn, r)
		cancel()
		if bindErr != nil {
			slog.Info("bind failed", "conn", connID, "err", bindErr)
			conn.Close("bind_failed")
			return
		}

		// Spawn writer; reader runs on this goroutine.
		connCtx, connCancel := context.WithCancel(ctx)
		defer connCancel()
		go conn.writeLoop(connCtx)

		s.serveConn(connCtx, conn)
	}
}

// bind reads the first envelope, validates it, and registers the connection.
// On failure it sends bind.error and returns the error (caller closes ws).
func (s *Server) bind(ctx context.Context, conn *Connection, r *http.Request) error {
	// Run a temporary write loop just to deliver bind.ack/bind.error before
	// the main writeLoop starts. We do this inline: build the envelope and
	// write it directly on the websocket since the out channel isn't drained yet.
	env, err := conn.readEnvelope(ctx)
	if err != nil {
		return fmt.Errorf("read bind: %w", err)
	}
	if env.Type != protocol.TypeBind {
		s.writeImmediate(ctx, conn, protocol.MustEnvelope(protocol.TypeBindError, protocol.BindError{
			Code: protocol.CodeInvalidToken, Message: "first message must be bind",
		}))
		return errors.New("first message not bind")
	}
	var req protocol.BindRequest
	if err := env.DecodeData(&req); err != nil {
		s.writeImmediate(ctx, conn, protocol.MustEnvelope(protocol.TypeBindError, protocol.BindError{
			Code: protocol.CodeInvalidToken, Message: "malformed bind",
		}))
		return fmt.Errorf("decode bind: %w", err)
	}

	switch req.Type {
	case "mac":
		if err := s.auth.VerifyMaster(ctx, req.Token); err != nil {
			s.writeImmediate(ctx, conn, protocol.MustEnvelope(protocol.TypeBindError, protocol.BindError{
				Code: protocol.CodeInvalidToken, Message: "invalid master token",
			}))
			return err
		}
		conn.Kind = ConnKindMac
		s.hub.AcceptMac(conn)
		s.writeImmediate(ctx, conn, protocol.MustEnvelope(protocol.TypeBindAck, protocol.BindAck{
			AgentID:      "default",
			SessionToken: uuid.NewString(),
		}))
		// Presence side effects fired after the ack is on the wire.
		s.presence.MacOnline()
		s.presence.PhoneCountChanged()
		return nil

	case "phone":
		row, firstBind, err := s.device.BindPhone(ctx, req.Token, req.DeviceName, req.DeviceModel, req.OSVersion)
		if err != nil {
			code := protocol.CodeInvalidToken
			switch {
			case errors.Is(err, protocol.ErrTokenExpired):
				code = protocol.CodeTokenExpired
			case errors.Is(err, protocol.ErrRevoked):
				code = protocol.CodeRevoked
			}
			s.writeImmediate(ctx, conn, protocol.MustEnvelope(protocol.TypeBindError, protocol.BindError{
				Code: code, Message: err.Error(),
			}))
			return err
		}
		conn.Kind = ConnKindPhone
		conn.TokenHash = row.TokenHash
		conn.DeviceName = req.DeviceName
		s.hub.AcceptPhone(conn)
		s.writeImmediate(ctx, conn, protocol.MustEnvelope(protocol.TypeBindAck, protocol.BindAck{
			SessionToken: uuid.NewString(),
		}))
		if firstBind {
			boundAt := ""
			if row.BoundAt.Valid {
				boundAt = row.BoundAt.Time.UTC().Format(time.RFC3339)
			}
			notify := protocol.MustEnvelope(protocol.TypeDeviceBound, protocol.DeviceBound{
				SubTokenID:  protocol.FormatSubTokenID(row.ID),
				DeviceName:  req.DeviceName,
				DeviceModel: req.DeviceModel,
				OSVersion:   req.OSVersion,
				BoundAt:     boundAt,
			})
			s.hub.MacConnSend(notify)
		}
		s.presence.PhoneCountChanged()
		// Inform the phone whether Mac is currently online so it can update UI.
		if s.hub.MacConn() != nil {
			online, _ := protocol.NewEnvelope(protocol.TypePresenceMacOnline, nil)
			_ = conn.Send(online)
			// 新 phone 上线后,主动让 Mac 重新广播 tab.list。
			// Mac 收到 tab.list.request 会回 tab.list.response,
			// 由 RouteFromMac 广播给所有 phone(含本次新上线的)。
			// 避免依赖 phone 端自行 fetch 时序(client-driven pull 在 ws 还没 connected 时会丢请求)。
			req, _ := protocol.NewEnvelope(protocol.TypeTabListRequest, nil)
			s.hub.MacConnSend(req)
		} else {
			off, _ := protocol.NewEnvelope(protocol.TypePresenceMacOffline, nil)
			_ = conn.Send(off)
		}
		return nil

	default:
		s.writeImmediate(ctx, conn, protocol.MustEnvelope(protocol.TypeBindError, protocol.BindError{
			Code: protocol.CodeInvalidToken, Message: "unknown bind.type",
		}))
		return fmt.Errorf("unknown bind type: %s", req.Type)
	}
}

// writeImmediate bypasses the out-channel writeLoop. Used during bind before
// the writeLoop starts.
func (s *Server) writeImmediate(ctx context.Context, conn *Connection, env *protocol.Envelope) {
	wctx, cancel := context.WithTimeout(ctx, writeTimeout)
	defer cancel()
	raw, _ := json.Marshal(env)
	_ = conn.ws.Write(wctx, websocket.MessageText, raw)
}

// serveConn loops reading envelopes from conn and dispatches by direction.
func (s *Server) serveConn(ctx context.Context, conn *Connection) {
	defer func() {
		wasMac := s.hub.RemoveConnection(conn)
		conn.Close("loop_exit")
		if conn.Kind == ConnKindMac && wasMac {
			s.presence.MacOffline()
		}
		if conn.Kind == ConnKindPhone {
			s.presence.PhoneCountChanged()
		}
		slog.Info("connection closed", "conn", conn.ID, "kind", kindString(conn.Kind))
	}()

	for {
		env, err := conn.readEnvelope(ctx)
		if err != nil {
			if !isNormalClose(err) {
				slog.Debug("read loop end", "conn", conn.ID, "err", err)
			}
			return
		}

		switch conn.Kind {
		case ConnKindMac:
			s.dispatchFromMac(ctx, conn, env)
		case ConnKindPhone:
			s.dispatchFromPhone(ctx, conn, env)
		}
	}
}

// dispatchFromMac handles Mac-originated envelopes — device mgmt + routing.
func (s *Server) dispatchFromMac(ctx context.Context, conn *Connection, env *protocol.Envelope) {
	switch env.Type {
	case protocol.TypeDeviceCreateSubtoken:
		plain, row, err := s.device.CreateSubToken(ctx)
		if err != nil {
			conn.sendError(protocol.CodeInternal, err.Error())
			return
		}
		resp, _ := protocol.NewEnvelope(protocol.TypeDeviceSubtokenCreated, protocol.DeviceSubtokenCreated{
			SubToken:  plain,
			ID:        protocol.FormatSubTokenID(row.ID),
			ExpiresAt: row.ExpiresAt.Time.UTC().Format(time.RFC3339),
		})
		_ = conn.Send(resp)

	case protocol.TypeDeviceList:
		rows, err := s.device.List(ctx)
		if err != nil {
			conn.sendError(protocol.CodeInternal, err.Error())
			return
		}
		out := make([]protocol.DeviceInfo, 0, len(rows))
		for _, row := range rows {
			online := s.hub.PhoneByHash(row.TokenHash) != nil
			out = append(out, device.ToProtocolInfo(row, online))
		}
		resp, _ := protocol.NewEnvelope(protocol.TypeDeviceListResponse, protocol.DeviceListResponse{Devices: out})
		_ = conn.Send(resp)

	case protocol.TypeDeviceRevoke:
		var req protocol.DeviceRevoke
		if err := env.DecodeData(&req); err != nil {
			conn.sendError(protocol.CodeInternal, "malformed device.revoke")
			return
		}
		idInt, err := protocol.ParseSubTokenID(req.SubTokenID)
		if err != nil {
			conn.sendError(protocol.CodeInvalidToken, "invalid sub_token_id")
			return
		}
		row, err := s.device.Revoke(ctx, idInt)
		if err != nil {
			conn.sendError(protocol.CodeInvalidToken, err.Error())
			return
		}
		// Kick the phone if it's online.
		if phone := s.hub.PhoneByHash(row.TokenHash); phone != nil {
			env, _ := protocol.NewEnvelope(protocol.TypeForceDisconnect, protocol.ForceDisconnect{Reason: "revoked"})
			phone.SendAndClose(env, "revoked")
		}
		resp, _ := protocol.NewEnvelope(protocol.TypeDeviceRevoked, protocol.DeviceRevoked{SubTokenID: protocol.FormatSubTokenID(row.ID)})
		_ = conn.Send(resp)

	case protocol.TypeImageFetched:
		s.router.RouteImageFetched(ctx, env)

	default:
		// Plain forward (msg.stream, tab.*, etc.)
		if errEnv := s.router.RouteFromMac(env); errEnv != nil {
			_ = conn.Send(errEnv)
		}
	}
}

// dispatchFromPhone handles phone-originated envelopes.
func (s *Server) dispatchFromPhone(ctx context.Context, conn *Connection, env *protocol.Envelope) {
	switch env.Type {
	case protocol.TypeImageUploadBegin:
		var req protocol.ImageUploadBegin
		if err := env.DecodeData(&req); err != nil {
			conn.sendError(protocol.CodeInternal, "malformed image.upload.begin")
			return
		}
		resp, err := s.image.BeginUpload(&req)
		if err != nil {
			code := protocol.CodeInternal
			if errors.Is(err, protocol.ErrImageTooLarge) {
				code = protocol.CodeImageTooLarge
			}
			conn.sendError(code, err.Error())
			return
		}
		urlEnv, _ := protocol.NewEnvelope(protocol.TypeImageUploadURL, resp)
		_ = conn.Send(urlEnv)

	case protocol.TypeImageDownloadRequest:
		var req protocol.ImageDownloadRequest
		if err := env.DecodeData(&req); err != nil {
			conn.sendError(protocol.CodeInternal, "malformed image.download.url")
			return
		}
		url, fname, ok := s.image.RequestDownloadURL(req.UploadID)
		resp := protocol.ImageDownloadResponse{
			UploadID: req.UploadID,
			ImageURL: url, // 空字符串表示已过期/不存在
			Filename: fname,
		}
		_ = ok // 即使 ok=false 也返回带空 URL 的 response,让 phone 端知道
		respEnv, _ := protocol.NewEnvelope(protocol.TypeImageDownloadResp, resp)
		_ = conn.Send(respEnv)

	case protocol.TypeDeviceSelfUnbind:
		row, err := s.device.RevokeByHash(ctx, conn.TokenHash)
		if err == nil && row != nil {
			// Tell Mac so its UI updates.
			notify, _ := protocol.NewEnvelope(protocol.TypeDeviceRevoked, protocol.DeviceRevoked{SubTokenID: protocol.FormatSubTokenID(row.ID)})
			s.hub.MacConnSend(notify)
		}
		env, _ := protocol.NewEnvelope(protocol.TypeForceDisconnect, protocol.ForceDisconnect{Reason: "self_unbind"})
		conn.SendAndClose(env, "self_unbind")

	default:
		if errEnv := s.router.RouteFromPhone(ctx, env); errEnv != nil {
			_ = conn.Send(errEnv)
		}
	}
}

func isNormalClose(err error) bool {
	if err == nil {
		return true
	}
	var ce websocket.CloseError
	if errors.As(err, &ce) {
		switch ce.Code {
		case websocket.StatusNormalClosure, websocket.StatusGoingAway:
			return true
		}
	}
	msg := err.Error()
	return strings.Contains(msg, "EOF") || strings.Contains(msg, "use of closed")
}

func kindString(k ConnKind) string {
	switch k {
	case ConnKindMac:
		return "mac"
	case ConnKindPhone:
		return "phone"
	default:
		return "unbound"
	}
}
