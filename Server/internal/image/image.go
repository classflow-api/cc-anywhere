// Package image owns the temporary image inbox: upload begin (returns signed
// URL), HTTP upload (writes to disk, verifies sha256), HTTP download for
// Mac, image.fetched cleanup, and a 5-minute GC for unfetched uploads.
//
// HMAC URL tokens carry (uploadID, op, expiresAt) so the same upload_id can
// only be downloaded once Mac is invited and only within the expiry window.
package image

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"

	"github.com/yoolines/cc-anywhere/internal/protocol"
)

const (
	maxImageBytes = 20 * 1024 * 1024
	uploadTTL     = 5 * time.Minute
)

// PhoneSink lets the image service push image.upload.expired to the phone
// that uploaded the file (we don't know which phone it was, so this is the
// broadcast variant — the phone matches by upload_id).
type PhoneSink interface {
	BroadcastToPhones(env *protocol.Envelope)
}

// MacSink lets the image service push input.image to Mac after a successful
// upload. Implemented by the hub.
type MacSink interface {
	MacConnSend(env *protocol.Envelope)
	HasMac() bool
}

// Service holds an in-memory map of pending uploads keyed by upload_id.
// Persistence is intentional: Server restart drops pending uploads (they have
// a 5-minute lifetime anyway).
type Service struct {
	inboxDir   string
	publicHost string
	secret     []byte

	mac   MacSink
	phone PhoneSink

	mu      sync.Mutex
	pending map[string]*pendingUpload
}

type pendingUpload struct {
	ID        string
	TabID     string
	Filename  string
	Sha256    string
	Size      int64
	CreatedAt time.Time
	ExpiresAt time.Time
	Received  bool // set after successful upload write+verify
}

// New constructs the service and ensures the inbox dir exists with 0700.
func New(inboxDir, publicHost string, secret []byte, mac MacSink, phone PhoneSink) (*Service, error) {
	if err := os.MkdirAll(inboxDir, 0o700); err != nil {
		return nil, fmt.Errorf("mkdir inbox: %w", err)
	}
	return &Service{
		inboxDir:   inboxDir,
		publicHost: publicHost,
		secret:     secret,
		mac:        mac,
		phone:      phone,
		pending:    make(map[string]*pendingUpload),
	}, nil
}

// BeginUpload validates size, records a pending upload, and returns the
// upload URL the phone should POST to.
func (s *Service) BeginUpload(req *protocol.ImageUploadBegin) (*protocol.ImageUploadURL, error) {
	if req.Size <= 0 || req.Size > maxImageBytes {
		return nil, protocol.ErrImageTooLarge
	}
	if req.Sha256 == "" || req.TabID == "" {
		return nil, errors.New("missing tab_id or sha256")
	}
	id := uuid.NewString()
	now := time.Now()
	exp := now.Add(uploadTTL)
	pu := &pendingUpload{
		ID: id, TabID: req.TabID, Filename: req.Filename,
		Sha256: strings.ToLower(req.Sha256), Size: req.Size,
		CreatedAt: now, ExpiresAt: exp,
	}
	s.mu.Lock()
	s.pending[id] = pu
	s.mu.Unlock()

	token := s.signToken(id, "upload", exp)
	return &protocol.ImageUploadURL{
		UploadID:  id,
		UploadURL: fmt.Sprintf("https://%s/upload/%s?token=%s&exp=%d", s.publicHost, id, token, exp.Unix()),
	}, nil
}

// HandleUploadHTTP is the POST /upload/{id} handler.
func (s *Service) HandleUploadHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	id := pathTail(r.URL.Path, "/upload/")
	if id == "" {
		http.Error(w, "missing upload id", http.StatusBadRequest)
		return
	}
	token := r.URL.Query().Get("token")
	exp := parseUnix(r.URL.Query().Get("exp"))
	if !s.verifyToken(id, "upload", token, exp) {
		http.Error(w, "invalid token", http.StatusUnauthorized)
		return
	}

	s.mu.Lock()
	pu, ok := s.pending[id]
	s.mu.Unlock()
	if !ok {
		http.Error(w, "upload not found", http.StatusNotFound)
		return
	}
	if pu.Received {
		http.Error(w, "already uploaded", http.StatusConflict)
		return
	}
	if time.Now().After(pu.ExpiresAt) {
		http.Error(w, "expired", http.StatusGone)
		return
	}
	if r.ContentLength > 0 && r.ContentLength > maxImageBytes {
		http.Error(w, "too large", http.StatusRequestEntityTooLarge)
		return
	}

	dst := filepath.Join(s.inboxDir, id)
	f, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o600)
	if err != nil {
		slog.Error("create upload file", "err", err, "id", id)
		http.Error(w, "io error", http.StatusInternalServerError)
		return
	}

	h := sha256.New()
	// LimitReader enforces the 20 MiB cap even when ContentLength is missing.
	limited := io.LimitReader(r.Body, maxImageBytes+1)
	n, copyErr := io.Copy(io.MultiWriter(f, h), limited)
	_ = f.Close()
	if copyErr != nil {
		_ = os.Remove(dst)
		slog.Warn("upload copy failed", "err", copyErr, "id", id)
		http.Error(w, "io error", http.StatusInternalServerError)
		return
	}
	if n > maxImageBytes {
		_ = os.Remove(dst)
		http.Error(w, "too large", http.StatusRequestEntityTooLarge)
		return
	}

	gotSha := hex.EncodeToString(h.Sum(nil))
	if gotSha != pu.Sha256 {
		_ = os.Remove(dst)
		http.Error(w, "sha256 mismatch", http.StatusBadRequest)
		return
	}

	s.mu.Lock()
	pu.Received = true
	s.mu.Unlock()

	// Notify Mac to fetch. If Mac is offline, leave the file in place; the
	// GC will sweep it after the TTL. The phone will see no input on Mac
	// and may retry separately.
	downloadToken := s.signToken(id, "download", pu.ExpiresAt)
	env, _ := protocol.NewEnvelope(protocol.TypeInputImage, protocol.InputImage{
		TabID:    pu.TabID,
		ImageURL: fmt.Sprintf("https://%s/download/%s?token=%s&exp=%d", s.publicHost, id, downloadToken, pu.ExpiresAt.Unix()),
		Filename: pu.Filename,
		Sha256:   pu.Sha256,
		UploadID: id,
	})
	if s.mac.HasMac() {
		s.mac.MacConnSend(env)
	}
	w.WriteHeader(http.StatusNoContent)
}

// HandleDownloadHTTP is the GET /download/{id} handler — Mac uses it.
func (s *Service) HandleDownloadHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	id := pathTail(r.URL.Path, "/download/")
	if id == "" {
		http.Error(w, "missing id", http.StatusBadRequest)
		return
	}
	token := r.URL.Query().Get("token")
	exp := parseUnix(r.URL.Query().Get("exp"))
	if !s.verifyToken(id, "download", token, exp) {
		http.Error(w, "invalid token", http.StatusUnauthorized)
		return
	}

	s.mu.Lock()
	pu, ok := s.pending[id]
	s.mu.Unlock()
	if !ok || !pu.Received {
		http.Error(w, "not ready", http.StatusNotFound)
		return
	}

	path := filepath.Join(s.inboxDir, id)
	f, err := os.Open(path)
	if err != nil {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	defer f.Close()
	stat, _ := f.Stat()
	w.Header().Set("Content-Type", "application/octet-stream")
	if pu.Filename != "" {
		w.Header().Set("Content-Disposition", fmt.Sprintf(`attachment; filename="%s"`, pu.Filename))
	}
	if stat != nil {
		w.Header().Set("Content-Length", strconv.FormatInt(stat.Size(), 10))
	}
	_, _ = io.Copy(w, f)
}

// HandleFetched is called when Mac confirms the download — wipe immediately.
func (s *Service) HandleFetched(ctx context.Context, uploadID string) {
	s.mu.Lock()
	_, ok := s.pending[uploadID]
	if ok {
		delete(s.pending, uploadID)
	}
	s.mu.Unlock()
	if !ok {
		return
	}
	if err := os.Remove(filepath.Join(s.inboxDir, uploadID)); err != nil && !os.IsNotExist(err) {
		slog.Warn("remove fetched image", "id", uploadID, "err", err)
	}
}

// StartGC sweeps expired pending uploads. Run as a background goroutine.
func (s *Service) StartGC(ctx context.Context) {
	go func() {
		t := time.NewTicker(30 * time.Second)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case now := <-t.C:
				s.sweepExpired(now)
			}
		}
	}()
}

func (s *Service) sweepExpired(now time.Time) {
	var expired []*pendingUpload
	s.mu.Lock()
	for id, pu := range s.pending {
		if now.After(pu.ExpiresAt) {
			expired = append(expired, pu)
			delete(s.pending, id)
		}
	}
	s.mu.Unlock()

	for _, pu := range expired {
		_ = os.Remove(filepath.Join(s.inboxDir, pu.ID))
		// Notify the original uploader the image went away. We don't know
		// which phone uploaded it, so broadcast; clients filter by upload_id.
		env, _ := protocol.NewEnvelope(protocol.TypeImageUploadExpired, protocol.ImageUploadExpired{UploadID: pu.ID})
		s.phone.BroadcastToPhones(env)
		slog.Info("upload expired", "id", pu.ID, "received", pu.Received)
	}
}

// signToken returns hex(HMAC-SHA256(secret, "<op>|<id>|<exp>")).
func (s *Service) signToken(id, op string, exp time.Time) string {
	mac := hmac.New(sha256.New, s.secret)
	fmt.Fprintf(mac, "%s|%s|%d", op, id, exp.Unix())
	return hex.EncodeToString(mac.Sum(nil))
}

func (s *Service) verifyToken(id, op, token string, exp time.Time) bool {
	if token == "" || time.Now().After(exp) {
		return false
	}
	expected := s.signToken(id, op, exp)
	return hmac.Equal([]byte(expected), []byte(token))
}

func pathTail(path, prefix string) string {
	if !strings.HasPrefix(path, prefix) {
		return ""
	}
	rest := path[len(prefix):]
	if i := strings.Index(rest, "/"); i >= 0 {
		rest = rest[:i]
	}
	return rest
}

func parseUnix(s string) time.Time {
	if s == "" {
		return time.Time{}
	}
	n, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		return time.Time{}
	}
	return time.Unix(n, 0)
}
