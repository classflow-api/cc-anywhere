package main

import (
	"context"
	"log/slog"
	"os"
	"os/signal"
	"strings"
	"syscall"

	"github.com/spf13/cobra"

	"github.com/yoolines/cc-anywhere/internal/config"
	"github.com/yoolines/cc-anywhere/internal/db"
	"github.com/yoolines/cc-anywhere/internal/server"
)

func main() {
	root := &cobra.Command{
		Use:           "cc-anywhere",
		Short:         "cc-anywhere relay server",
		SilenceUsage:  true,
		SilenceErrors: true,
	}
	root.AddCommand(serveCmd())
	root.AddCommand(adminCmd())

	if err := root.Execute(); err != nil {
		slog.Error("command failed", "err", err)
		os.Exit(1)
	}
}

func serveCmd() *cobra.Command {
	var cfgPath string
	cmd := &cobra.Command{
		Use:   "serve",
		Short: "Run the relay server",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := config.Load(cfgPath)
			if err != nil {
				return err
			}
			setupLogger(cfg.Log.Level)

			ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
			defer cancel()

			conn, err := db.Open(ctx, cfg.DB.Path)
			if err != nil {
				return err
			}
			defer conn.Close()

			srv, err := server.New(cfg, conn)
			if err != nil {
				return err
			}
			return srv.Run(ctx)
		},
	}
	cmd.Flags().StringVar(&cfgPath, "config", "/etc/cc-anywhere/config.yaml", "config file")
	return cmd
}

func setupLogger(level string) {
	var lvl slog.Level
	switch strings.ToLower(level) {
	case "debug":
		lvl = slog.LevelDebug
	case "warn":
		lvl = slog.LevelWarn
	case "error":
		lvl = slog.LevelError
	default:
		lvl = slog.LevelInfo
	}
	h := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: lvl})
	slog.SetDefault(slog.New(h))
}
