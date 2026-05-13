// Package config loads YAML server configuration. Environment variable
// substitution (${VAR}) is supported on string fields so secrets can be
// injected from docker-compose env without touching the file.
package config

import (
	"fmt"
	"os"
	"regexp"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Server ServerConfig `yaml:"server"`
	DB     DBConfig     `yaml:"db"`
	Image  ImageConfig  `yaml:"image"`
	Log    LogConfig    `yaml:"log"`
}

type ServerConfig struct {
	Address    string    `yaml:"address"` // host:port for WSS + HTTP
	TLS        TLSConfig `yaml:"tls"`
	PublicHost string    `yaml:"public_host"` // host:port used to compose absolute image URLs
}

type TLSConfig struct {
	CertFile string `yaml:"cert_file"`
	KeyFile  string `yaml:"key_file"`
}

type DBConfig struct {
	Path string `yaml:"path"`
}

type ImageConfig struct {
	InboxDir   string `yaml:"inbox_dir"`
	HMACSecret string `yaml:"hmac_secret"`
}

type LogConfig struct {
	Level string `yaml:"level"`
}

// Load reads + parses the YAML config at path and expands ${VAR} references.
func Load(path string) (*Config, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read config: %w", err)
	}
	expanded := expandEnv(string(raw))
	var cfg Config
	if err := yaml.Unmarshal([]byte(expanded), &cfg); err != nil {
		return nil, fmt.Errorf("parse yaml: %w", err)
	}
	if err := cfg.validate(); err != nil {
		return nil, err
	}
	return &cfg, nil
}

func (c *Config) validate() error {
	if c.Server.Address == "" {
		return fmt.Errorf("server.address required")
	}
	if c.Server.TLS.CertFile == "" || c.Server.TLS.KeyFile == "" {
		return fmt.Errorf("server.tls.cert_file and server.tls.key_file required")
	}
	if c.Server.PublicHost == "" {
		return fmt.Errorf("server.public_host required (used for image URLs)")
	}
	if c.DB.Path == "" {
		return fmt.Errorf("db.path required")
	}
	if c.Image.InboxDir == "" {
		return fmt.Errorf("image.inbox_dir required")
	}
	if c.Image.HMACSecret == "" {
		return fmt.Errorf("image.hmac_secret required (use ${CC_HMAC_SECRET})")
	}
	if c.Log.Level == "" {
		c.Log.Level = "info"
	}
	return nil
}

var envPattern = regexp.MustCompile(`\$\{([A-Z_][A-Z0-9_]*)\}`)

func expandEnv(s string) string {
	return envPattern.ReplaceAllStringFunc(s, func(match string) string {
		key := match[2 : len(match)-1]
		return os.Getenv(key)
	})
}
