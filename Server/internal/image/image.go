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
	uploadTTL     = 5 * time.Minute     // 未被 Mac fetched 前的 TTL
	fetchedTTL    = 7 * 24 * time.Hour  // Mac fetched 后,保留 7 天供 phone 端预览历史
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
	Received  bool      // set after successful upload write+verify
	Fetched   bool      // set when Mac confirms download via image.fetched
	FetchedAt time.Time // when Fetched was set; entry kept for fetchedTTL after this
}

// New constructs the service and ensures the inbox dir exists with 0700.
// 启动时扫描 inboxDir 已有文件,**重建** pending 内存表为已 fetched 状态。
// 否则 server 重启后,phone 端历史 chat 中的 attachment 卡片(filename = upload_id+ext)
// 找不到对应 pending entry → image.download.url 返回空 → 全部显示 broken_image。
func New(inboxDir, publicHost string, secret []byte, mac MacSink, phone PhoneSink) (*Service, error) {
	if err := os.MkdirAll(inboxDir, 0o700); err != nil {
		return nil, fmt.Errorf("mkdir inbox: %w", err)
	}
	s := &Service{
		inboxDir:   inboxDir,
		publicHost: publicHost,
		secret:     secret,
		mac:        mac,
		phone:      phone,
		pending:    make(map[string]*pendingUpload),
	}
	s.rebuildPendingFromInbox()
	return s, nil
}

// rebuildPendingFromInbox 扫描 inboxDir,把现有文件重建为已 fetched 的 pendingUpload entry,
// 用 mtime 当作 FetchedAt 估算,允许后续 sweepExpired 在超过 fetchedTTL 时清掉。
// 注:无法恢复 Filename(原文件名)和 Sha256,这些只用于校验,缺失时跳过校验即可。
func (s *Service) rebuildPendingFromInbox() {
	entries, err := os.ReadDir(s.inboxDir)
	if err != nil {
		slog.Warn("rebuild pending: read inbox", "err", err)
		return
	}
	now := time.Now()
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		// inbox 文件名是 upload_id 或 upload_id.ext;两种都按基名(去 ext)当作 upload_id 的等价主键。
		// 实际 Mac 端 InputInjector 落盘是 "<upload_id>.<ext>" 形式,Server 这边 download/{id}
		// 的 id 是纯 upload_id — 这是 Mac 端落盘名跟 server 端 id 的差异。
		// 但 server 重建 entry 只需要 inbox 里有这个文件、能被 phone 通过 upload_id 重新取到。
		// 因为 phone 通过 ImageRefStore 拿到的 upload_id 跟 server 文件名是同源关系,
		// 直接用 e.Name() 当 ID(对 server 内部协议是 self-consistent 的)。
		name := e.Name()
		info, ierr := e.Info()
		if ierr != nil {
			continue
		}
		mtime := info.ModTime()
		s.pending[name] = &pendingUpload{
			ID:        name,
			CreatedAt: mtime,
			ExpiresAt: mtime.Add(uploadTTL),
			Received:  true,
			Fetched:   true,
			FetchedAt: mtime,
		}
		_ = now
	}
	slog.Info("rebuilt pending uploads from inbox", "count", len(s.pending))
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

// RequestDownloadURL is called when phone wants to (re-)preview an image.
// 返回的 URL 不依赖于原始 ExpiresAt(那个 5min 早过期了),用 fetchedTTL 重新签 token,
// 让 phone 在 fetched + 7 天窗口内都能下载预览。
// 如果 server 上图片已不存在(过期/未上传),返回 ok=false。
func (s *Service) RequestDownloadURL(uploadID string) (string, string, bool) {
	s.mu.Lock()
	pu, ok := s.pending[uploadID]
	s.mu.Unlock()
	if !ok || !pu.Received {
		return "", "", false
	}
	// 用 fetchedTTL 起算的新过期 — 允许 phone 在保留期内随时拉
	exp := time.Now().Add(fetchedTTL)
	token := s.signToken(uploadID, "download", exp)
	url := fmt.Sprintf("https://%s/download/%s?token=%s&exp=%d", s.publicHost, uploadID, token, exp.Unix())
	return url, pu.Filename, true
}

// HandleFetched is called when Mac confirms the download.
// 标记 Fetched 但不立即删 — 保留 fetchedTTL,供 phone 端通过 image.download.url
// 重新获取下载链接预览历史图片(尤其重装/重连后)。
func (s *Service) HandleFetched(ctx context.Context, uploadID string) {
	s.mu.Lock()
	pu, ok := s.pending[uploadID]
	if ok {
		pu.Fetched = true
		pu.FetchedAt = time.Now()
	}
	s.mu.Unlock()
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
	var unfetchedExpired []*pendingUpload
	var fetchedExpired []*pendingUpload
	s.mu.Lock()
	for id, pu := range s.pending {
		if pu.Fetched {
			// 已被 Mac 取走的图片:从 FetchedAt 算起,fetchedTTL 后再清。
			// 中间这段时间 phone 可以通过 image.download.url 拿新 token 预览。
			if now.Sub(pu.FetchedAt) > fetchedTTL {
				fetchedExpired = append(fetchedExpired, pu)
				delete(s.pending, id)
			}
			continue
		}
		// 未被 Mac 取走的:超过 uploadTTL 即丢(短 TTL,这种情况通知 phone)。
		if now.After(pu.ExpiresAt) {
			unfetchedExpired = append(unfetchedExpired, pu)
			delete(s.pending, id)
		}
	}
	s.mu.Unlock()

	// 已 fetched 过期 — 删文件但不广播 expired(图片已经在 Mac 上用过)
	for _, pu := range fetchedExpired {
		_ = os.Remove(filepath.Join(s.inboxDir, pu.ID))
	}

	// 未 fetched 过期 — 走原 expired 通知路径
	expired := unfetchedExpired
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
