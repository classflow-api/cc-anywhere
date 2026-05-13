// Package device owns the sub_tokens table — generation, pending→active
// transition during phone bind, revocation, listing, and pending GC.
package device

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/yoolines/cc-anywhere/internal/auth"
	"github.com/yoolines/cc-anywhere/internal/protocol"
)

const (
	StatusPending = "pending"
	StatusActive  = "active"
	StatusRevoked = "revoked"

	pendingTTL = 5 * time.Minute
)

type Service struct {
	db *sql.DB
}

func New(db *sql.DB) *Service { return &Service{db: db} }

// SubToken is the in-memory shape of a row in sub_tokens.
type SubToken struct {
	ID          int64
	TokenHash   string
	Status      string
	DeviceName  sql.NullString
	DeviceModel sql.NullString
	OSVersion   sql.NullString
	CreatedAt   time.Time
	BoundAt     sql.NullTime
	LastSeenAt  sql.NullTime
	ExpiresAt   sql.NullTime
}

// CreateSubToken generates a new 32-byte token, persists its hash with
// status=pending and expires_at=now+5min, and returns the plaintext token
// (which will never be readable again).
func (s *Service) CreateSubToken(ctx context.Context) (plain string, row *SubToken, err error) {
	plain, err = auth.GenerateToken()
	if err != nil {
		return "", nil, err
	}
	hash := auth.HashToken(plain)
	expiresAt := time.Now().Add(pendingTTL).UTC()
	res, err := s.db.ExecContext(ctx, `
		INSERT INTO sub_tokens (token_hash, status, expires_at)
		VALUES (?, ?, ?)
	`, hash, StatusPending, expiresAt)
	if err != nil {
		return "", nil, fmt.Errorf("insert sub_token: %w", err)
	}
	id, _ := res.LastInsertId()
	return plain, &SubToken{
		ID:        id,
		TokenHash: hash,
		Status:    StatusPending,
		ExpiresAt: sql.NullTime{Time: expiresAt, Valid: true},
	}, nil
}

// BindPhone resolves a phone's bind token. On success it transitions a pending
// row to active (recording device metadata) or refreshes last_seen_at for an
// already-active row. Returns:
//   - row (with up-to-date metadata) and a bool indicating if this was the
//     first-time activation (caller should notify mac via device.bound)
//   - protocol.ErrInvalidToken if no matching token
//   - protocol.ErrTokenExpired if pending row's expires_at has passed
//   - protocol.ErrRevoked if status is revoked
func (s *Service) BindPhone(ctx context.Context, token, deviceName, deviceModel, osVersion string) (row *SubToken, firstBind bool, err error) {
	hash := auth.HashToken(token)
	row, err = s.findByHash(ctx, hash)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, false, protocol.ErrInvalidToken
	}
	if err != nil {
		return nil, false, err
	}

	switch row.Status {
	case StatusRevoked:
		return nil, false, protocol.ErrRevoked

	case StatusPending:
		if row.ExpiresAt.Valid && time.Now().After(row.ExpiresAt.Time) {
			// Mark expired-pending rows as revoked so a future scan deletes them.
			_, _ = s.db.ExecContext(ctx, `UPDATE sub_tokens SET status = ? WHERE id = ?`, StatusRevoked, row.ID)
			return nil, false, protocol.ErrTokenExpired
		}
		now := time.Now().UTC()
		_, err = s.db.ExecContext(ctx, `
			UPDATE sub_tokens
			SET status = ?, device_name = ?, device_model = ?, os_version = ?,
			    bound_at = ?, last_seen_at = ?, expires_at = NULL
			WHERE id = ?
		`, StatusActive, deviceName, deviceModel, osVersion, now, now, row.ID)
		if err != nil {
			return nil, false, fmt.Errorf("activate sub_token: %w", err)
		}
		row.Status = StatusActive
		row.DeviceName = sql.NullString{String: deviceName, Valid: deviceName != ""}
		row.DeviceModel = sql.NullString{String: deviceModel, Valid: deviceModel != ""}
		row.OSVersion = sql.NullString{String: osVersion, Valid: osVersion != ""}
		row.BoundAt = sql.NullTime{Time: now, Valid: true}
		row.LastSeenAt = sql.NullTime{Time: now, Valid: true}
		row.ExpiresAt = sql.NullTime{}
		return row, true, nil

	case StatusActive:
		now := time.Now().UTC()
		_, err = s.db.ExecContext(ctx, `UPDATE sub_tokens SET last_seen_at = ? WHERE id = ?`, now, row.ID)
		if err != nil {
			return nil, false, fmt.Errorf("touch sub_token: %w", err)
		}
		row.LastSeenAt = sql.NullTime{Time: now, Valid: true}
		return row, false, nil

	default:
		return nil, false, protocol.ErrInternal
	}
}

func (s *Service) findByHash(ctx context.Context, hash string) (*SubToken, error) {
	row := s.db.QueryRowContext(ctx, `
		SELECT id, token_hash, status, device_name, device_model, os_version,
		       created_at, bound_at, last_seen_at, expires_at
		FROM sub_tokens WHERE token_hash = ?
	`, hash)
	var t SubToken
	if err := row.Scan(&t.ID, &t.TokenHash, &t.Status, &t.DeviceName, &t.DeviceModel,
		&t.OSVersion, &t.CreatedAt, &t.BoundAt, &t.LastSeenAt, &t.ExpiresAt); err != nil {
		return nil, err
	}
	return &t, nil
}

// FindByID is used by the admin CLI and revoke flow.
func (s *Service) FindByID(ctx context.Context, id int64) (*SubToken, error) {
	row := s.db.QueryRowContext(ctx, `
		SELECT id, token_hash, status, device_name, device_model, os_version,
		       created_at, bound_at, last_seen_at, expires_at
		FROM sub_tokens WHERE id = ?
	`, id)
	var t SubToken
	if err := row.Scan(&t.ID, &t.TokenHash, &t.Status, &t.DeviceName, &t.DeviceModel,
		&t.OSVersion, &t.CreatedAt, &t.BoundAt, &t.LastSeenAt, &t.ExpiresAt); err != nil {
		return nil, err
	}
	return &t, nil
}

// Revoke marks a sub_token as revoked. Idempotent; revoking a non-existent
// id returns nil to keep clients simple.
func (s *Service) Revoke(ctx context.Context, id int64) (*SubToken, error) {
	row, err := s.FindByID(ctx, id)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, protocol.ErrInvalidToken
	}
	if err != nil {
		return nil, err
	}
	if row.Status == StatusRevoked {
		return row, nil
	}
	if _, err := s.db.ExecContext(ctx, `UPDATE sub_tokens SET status = ? WHERE id = ?`, StatusRevoked, id); err != nil {
		return nil, fmt.Errorf("revoke: %w", err)
	}
	row.Status = StatusRevoked
	return row, nil
}

// RevokeByHash is used when a phone unbinds itself — we have the token hash
// of the calling connection but not its DB id at that point.
func (s *Service) RevokeByHash(ctx context.Context, hash string) (*SubToken, error) {
	row, err := s.findByHash(ctx, hash)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return s.Revoke(ctx, row.ID)
}

// List returns every non-deleted sub_token row. The hub layer joins with
// live connection state to compute the `online` field.
func (s *Service) List(ctx context.Context) ([]*SubToken, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, token_hash, status, device_name, device_model, os_version,
		       created_at, bound_at, last_seen_at, expires_at
		FROM sub_tokens
		ORDER BY id ASC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []*SubToken
	for rows.Next() {
		var t SubToken
		if err := rows.Scan(&t.ID, &t.TokenHash, &t.Status, &t.DeviceName, &t.DeviceModel,
			&t.OSVersion, &t.CreatedAt, &t.BoundAt, &t.LastSeenAt, &t.ExpiresAt); err != nil {
			return nil, err
		}
		out = append(out, &t)
	}
	return out, rows.Err()
}

// StartPendingGC launches a background loop that hard-deletes pending rows
// past their expires_at. It returns when ctx is cancelled.
//
// We delete (rather than mark revoked) because pending rows that timed out
// hold no useful audit information — a fresh QR generates a new row anyway.
func (s *Service) StartPendingGC(ctx context.Context, interval time.Duration) {
	if interval <= 0 {
		interval = time.Minute
	}
	go func() {
		t := time.NewTicker(interval)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				res, err := s.db.ExecContext(ctx, `
					DELETE FROM sub_tokens
					WHERE status = ? AND expires_at IS NOT NULL AND expires_at < CURRENT_TIMESTAMP
				`, StatusPending)
				if err != nil {
					slog.Warn("pending gc failed", "err", err)
					continue
				}
				if n, _ := res.RowsAffected(); n > 0 {
					slog.Info("pending gc removed", "count", n)
				}
			}
		}
	}()
}

// ToProtocolInfo formats a SubToken for the device.list.response payload.
func ToProtocolInfo(t *SubToken, online bool) protocol.DeviceInfo {
	info := protocol.DeviceInfo{
		ID:          t.ID,
		DeviceName:  t.DeviceName.String,
		DeviceModel: t.DeviceModel.String,
		OSVersion:   t.OSVersion.String,
		Status:      t.Status,
		Online:      online,
	}
	if t.BoundAt.Valid {
		info.BoundAt = t.BoundAt.Time.UTC().Format(time.RFC3339)
	}
	if t.LastSeenAt.Valid {
		info.LastSeenAt = t.LastSeenAt.Time.UTC().Format(time.RFC3339)
	}
	return info
}
