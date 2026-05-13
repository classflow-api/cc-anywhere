// Package db owns the SQLite connection and forward-only migration runner.
//
// The runner ignores any down.sql files so a misplaced rollback artifact in
// the migrations dir does not corrupt the schema_version table.
package db

import (
	"context"
	"database/sql"
	"embed"
	"fmt"
	"io/fs"
	"log/slog"
	"net/url"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	_ "modernc.org/sqlite"
)

//go:embed migrations/*.sql
var migrationFS embed.FS

// Open opens a SQLite file at path with sensible pragmas (WAL + busy timeout)
// and runs forward migrations. The returned DB is ready for concurrent use.
func Open(ctx context.Context, path string) (*sql.DB, error) {
	// SQLite under modernc uses URI form for pragmas. Foreign keys on, WAL,
	// 5s busy timeout — sufficient for our single-writer pattern.
	dsn := fmt.Sprintf(
		"file:%s?_pragma=journal_mode(WAL)&_pragma=foreign_keys(1)&_pragma=busy_timeout(5000)",
		url.PathEscape(path),
	)
	conn, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("sql.Open: %w", err)
	}
	if err := conn.PingContext(ctx); err != nil {
		_ = conn.Close()
		return nil, fmt.Errorf("ping db: %w", err)
	}
	if err := runMigrations(ctx, conn); err != nil {
		_ = conn.Close()
		return nil, fmt.Errorf("migrations: %w", err)
	}
	return conn, nil
}

var migrationName = regexp.MustCompile(`^(\d+)_.*\.up\.sql$`)

func runMigrations(ctx context.Context, conn *sql.DB) error {
	// Bootstrap schema_version. We cannot SELECT it before it exists; the
	// initial migration creates it, so we tolerate the "no such table" path.
	entries, err := fs.ReadDir(migrationFS, "migrations")
	if err != nil {
		return fmt.Errorf("read embed: %w", err)
	}

	type mig struct {
		version int
		name    string
	}
	var migs []mig
	for _, e := range entries {
		m := migrationName.FindStringSubmatch(e.Name())
		if m == nil {
			continue
		}
		v, _ := strconv.Atoi(m[1])
		migs = append(migs, mig{version: v, name: e.Name()})
	}
	sort.Slice(migs, func(i, j int) bool { return migs[i].version < migs[j].version })

	applied := map[int]bool{}
	rows, err := conn.QueryContext(ctx, `SELECT version FROM schema_version`)
	switch {
	case err == nil:
		for rows.Next() {
			var v int
			if scanErr := rows.Scan(&v); scanErr != nil {
				_ = rows.Close()
				return scanErr
			}
			applied[v] = true
		}
		_ = rows.Close()
	case strings.Contains(err.Error(), "no such table"):
		// First-ever boot, the migration itself creates schema_version.
	default:
		return fmt.Errorf("query schema_version: %w", err)
	}

	for _, m := range migs {
		if applied[m.version] {
			continue
		}
		sqlBytes, err := migrationFS.ReadFile(filepath.Join("migrations", m.name))
		if err != nil {
			return fmt.Errorf("read %s: %w", m.name, err)
		}
		slog.Info("applying migration", "version", m.version, "name", m.name)
		if _, err := conn.ExecContext(ctx, string(sqlBytes)); err != nil {
			return fmt.Errorf("exec %s: %w", m.name, err)
		}
	}
	return nil
}
