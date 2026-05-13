// Package auth verifies master/sub tokens against their sha256 hashes stored
// in SQLite. All comparisons use constant-time equality on hex strings.
package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"

	"github.com/yoolines/cc-anywhere/internal/protocol"
)

// Service exposes token verification and master-token rotation. It is the
// only component allowed to read/write the master_token table.
type Service struct {
	db *sql.DB
}

func New(db *sql.DB) *Service { return &Service{db: db} }

// HashToken returns the lowercase hex sha256 of token.
func HashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

// GenerateToken returns a 32-byte cryptographic random token as hex.
func GenerateToken() (string, error) {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return "", fmt.Errorf("rand.Read: %w", err)
	}
	return hex.EncodeToString(buf), nil
}

// VerifyMaster returns nil iff token matches the stored master token hash.
// Returns protocol.ErrInvalidToken if no master token is set or mismatch.
func (s *Service) VerifyMaster(ctx context.Context, token string) error {
	var stored string
	err := s.db.QueryRowContext(ctx, `SELECT token_hash FROM master_token WHERE id = 1`).Scan(&stored)
	if errors.Is(err, sql.ErrNoRows) {
		return protocol.ErrInvalidToken
	}
	if err != nil {
		return fmt.Errorf("query master: %w", err)
	}
	if subtle.ConstantTimeCompare([]byte(stored), []byte(HashToken(token))) != 1 {
		return protocol.ErrInvalidToken
	}
	return nil
}

// SetMasterToken upserts the single master_token row with hash(plain).
func (s *Service) SetMasterToken(ctx context.Context, plain string) error {
	h := HashToken(plain)
	_, err := s.db.ExecContext(ctx, `
		INSERT INTO master_token (id, token_hash, created_at, rotated_at)
		VALUES (1, ?, CURRENT_TIMESTAMP, NULL)
		ON CONFLICT(id) DO UPDATE SET token_hash = excluded.token_hash, rotated_at = CURRENT_TIMESTAMP
	`, h)
	if err != nil {
		return fmt.Errorf("upsert master_token: %w", err)
	}
	return nil
}

// HasMaster reports whether a master token has ever been set.
func (s *Service) HasMaster(ctx context.Context) (bool, error) {
	var n int
	err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM master_token WHERE id = 1`).Scan(&n)
	if err != nil {
		return false, err
	}
	return n > 0, nil
}
