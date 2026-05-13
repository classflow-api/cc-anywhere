package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strconv"
	"text/tabwriter"
	"time"

	"github.com/spf13/cobra"

	"github.com/yoolines/cc-anywhere/internal/auth"
	"github.com/yoolines/cc-anywhere/internal/config"
	"github.com/yoolines/cc-anywhere/internal/db"
	"github.com/yoolines/cc-anywhere/internal/device"
)

// adminCmd groups the operator commands run inside the container.
func adminCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "admin",
		Short: "Admin commands",
	}
	cmd.AddCommand(resetMasterTokenCmd())
	cmd.AddCommand(listDevicesCmd())
	cmd.AddCommand(revokeDeviceCmd())
	return cmd
}

func resetMasterTokenCmd() *cobra.Command {
	var cfgPath string
	var force bool
	cmd := &cobra.Command{
		Use:   "reset-master-token",
		Short: "Generate a new master token (prints once to stderr)",
		RunE: func(cmd *cobra.Command, args []string) error {
			if !force {
				return errors.New("must pass --force to confirm (kicks current Mac session)")
			}
			cfg, err := config.Load(cfgPath)
			if err != nil {
				return err
			}
			ctx := context.Background()
			conn, err := db.Open(ctx, cfg.DB.Path)
			if err != nil {
				return err
			}
			defer conn.Close()

			token, err := auth.GenerateToken()
			if err != nil {
				return err
			}
			authSvc := auth.New(conn)
			if err := authSvc.SetMasterToken(ctx, token); err != nil {
				return err
			}
			// Per R-S7-02 print to stderr only.
			fmt.Fprintln(os.Stderr, "=== NEW MASTER TOKEN — copy now, it will not be shown again ===")
			fmt.Fprintln(os.Stderr, token)
			fmt.Fprintln(os.Stderr, "=== save it somewhere safe ===")
			return nil
		},
	}
	cmd.Flags().StringVar(&cfgPath, "config", "/etc/cc-anywhere/config.yaml", "config file")
	cmd.Flags().BoolVar(&force, "force", false, "required confirmation")
	return cmd
}

func listDevicesCmd() *cobra.Command {
	var cfgPath string
	cmd := &cobra.Command{
		Use:   "list-devices",
		Short: "List all sub_tokens and their state",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := config.Load(cfgPath)
			if err != nil {
				return err
			}
			ctx := context.Background()
			conn, err := db.Open(ctx, cfg.DB.Path)
			if err != nil {
				return err
			}
			defer conn.Close()
			devSvc := device.New(conn)
			rows, err := devSvc.List(ctx)
			if err != nil {
				return err
			}
			tw := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
			fmt.Fprintln(tw, "ID\tSTATUS\tNAME\tMODEL\tOS\tBOUND_AT\tLAST_SEEN")
			for _, r := range rows {
				fmt.Fprintf(tw, "%d\t%s\t%s\t%s\t%s\t%s\t%s\n",
					r.ID, r.Status,
					r.DeviceName.String, r.DeviceModel.String, r.OSVersion.String,
					fmtTime(r.BoundAt.Time, r.BoundAt.Valid),
					fmtTime(r.LastSeenAt.Time, r.LastSeenAt.Valid),
				)
			}
			return tw.Flush()
		},
	}
	cmd.Flags().StringVar(&cfgPath, "config", "/etc/cc-anywhere/config.yaml", "config file")
	return cmd
}

func revokeDeviceCmd() *cobra.Command {
	var cfgPath string
	var idStr string
	cmd := &cobra.Command{
		Use:   "revoke-device",
		Short: "Revoke a sub_token by id",
		RunE: func(cmd *cobra.Command, args []string) error {
			if idStr == "" {
				return errors.New("--id required")
			}
			id, err := strconv.ParseInt(idStr, 10, 64)
			if err != nil {
				return fmt.Errorf("invalid id: %w", err)
			}
			cfg, err := config.Load(cfgPath)
			if err != nil {
				return err
			}
			ctx := context.Background()
			conn, err := db.Open(ctx, cfg.DB.Path)
			if err != nil {
				return err
			}
			defer conn.Close()
			devSvc := device.New(conn)
			row, err := devSvc.Revoke(ctx, id)
			if err != nil {
				return err
			}
			fmt.Printf("revoked id=%d name=%q\n", row.ID, row.DeviceName.String)
			return nil
		},
	}
	cmd.Flags().StringVar(&cfgPath, "config", "/etc/cc-anywhere/config.yaml", "config file")
	cmd.Flags().StringVar(&idStr, "id", "", "sub_token id to revoke")
	return cmd
}

func fmtTime(t time.Time, valid bool) string {
	if !valid {
		return "-"
	}
	return t.UTC().Format(time.RFC3339)
}
