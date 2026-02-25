package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

type Config struct {
	HTTPAddr             string
	DatabaseDSN          string
	JWTSecret            string
	AccessTokenTTLMin    int
	RefreshTokenTTLDays  int
	RecoveryTokenTTLMin  int
	RecoveryTokenEcho    bool
	SMTPEnabled          bool
	SMTPHost             string
	SMTPPort             int
	SMTPUsername         string
	SMTPPassword         string
	SMTPFrom             string
	SMTPFromName         string
	SMTPUseTLS           bool
	SMTPStartTLS         bool
	SMTPSkipVerify       bool
	StorageRoot          string
	BundleMaxBytes       int64
}

func Load() (Config, error) {
	httpAddr := getenv("HTTP_ADDR", ":8080")
	dsn := os.Getenv("DB_DSN")
	if dsn == "" {
		return Config{}, fmt.Errorf("DB_DSN is required")
	}
	jwtSecret := os.Getenv("JWT_SECRET")
	if jwtSecret == "" {
		return Config{}, fmt.Errorf("JWT_SECRET is required")
	}
	accessTTL := getenvInt("ACCESS_TOKEN_TTL_MINUTES", 30)
	refreshTTL := getenvInt("REFRESH_TOKEN_TTL_DAYS", 30)
	recoveryTTL := getenvInt("RECOVERY_TOKEN_TTL_MINUTES", 30)
	recoveryEcho := getenvBool("RECOVERY_TOKEN_ECHO", false)
	smtpEnabled := getenvBool("SMTP_ENABLED", false)
	smtpHost := getenv("SMTP_HOST", "")
	smtpPort := getenvInt("SMTP_PORT", 0)
	smtpUser := getenv("SMTP_USERNAME", "")
	smtpPass := getenv("SMTP_PASSWORD", "")
	smtpFrom := getenv("SMTP_FROM", "")
	smtpFromName := getenv("SMTP_FROM_NAME", "")
	smtpUseTLS := getenvBool("SMTP_USE_TLS", false)
	smtpStartTLS := getenvBool("SMTP_STARTTLS", false)
	smtpSkipVerify := getenvBool("SMTP_SKIP_VERIFY", false)
	storageRoot := getenv("STORAGE_ROOT", "")
	bundleMaxBytes := getenvInt64("BUNDLE_MAX_BYTES", 1073741824)
	if storageRoot == "" {
		return Config{}, fmt.Errorf("STORAGE_ROOT is required")
	}
	if bundleMaxBytes <= 0 {
		return Config{}, fmt.Errorf("BUNDLE_MAX_BYTES must be > 0")
	}
	if recoveryTTL <= 0 {
		return Config{}, fmt.Errorf("RECOVERY_TOKEN_TTL_MINUTES must be > 0")
	}
	if smtpEnabled {
		if smtpHost == "" || smtpPort <= 0 || smtpFrom == "" {
			return Config{}, fmt.Errorf("SMTP_HOST, SMTP_PORT, and SMTP_FROM are required when SMTP is enabled")
		}
		if smtpUser != "" && smtpPass == "" {
			return Config{}, fmt.Errorf("SMTP_PASSWORD is required when SMTP_USERNAME is set")
		}
	}

	return Config{
		HTTPAddr:            httpAddr,
		DatabaseDSN:         dsn,
		JWTSecret:           jwtSecret,
		AccessTokenTTLMin:   accessTTL,
		RefreshTokenTTLDays: refreshTTL,
		RecoveryTokenTTLMin: recoveryTTL,
		RecoveryTokenEcho:   recoveryEcho,
		SMTPEnabled:         smtpEnabled,
		SMTPHost:            smtpHost,
		SMTPPort:            smtpPort,
		SMTPUsername:        smtpUser,
		SMTPPassword:        smtpPass,
		SMTPFrom:            smtpFrom,
		SMTPFromName:        smtpFromName,
		SMTPUseTLS:          smtpUseTLS,
		SMTPStartTLS:        smtpStartTLS,
		SMTPSkipVerify:      smtpSkipVerify,
		StorageRoot:         storageRoot,
		BundleMaxBytes:      bundleMaxBytes,
	}, nil
}

func getenv(key, fallback string) string {
	val := os.Getenv(key)
	if val == "" {
		return fallback
	}
	return val
}

func getenvInt(key string, fallback int) int {
	val := os.Getenv(key)
	if val == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(val)
	if err != nil {
		return fallback
	}
	return parsed
}

func getenvInt64(key string, fallback int64) int64 {
	val := os.Getenv(key)
	if val == "" {
		return fallback
	}
	parsed, err := strconv.ParseInt(val, 10, 64)
	if err != nil {
		return fallback
	}
	return parsed
}

func getenvBool(key string, fallback bool) bool {
	raw := strings.TrimSpace(strings.ToLower(os.Getenv(key)))
	if raw == "" {
		return fallback
	}
	switch raw {
	case "1", "true", "yes", "y", "on":
		return true
	case "0", "false", "no", "n", "off":
		return false
	default:
		return fallback
	}
}
