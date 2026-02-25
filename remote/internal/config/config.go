package config

import (
	"fmt"
	"os"
	"strconv"
)

type Config struct {
	HTTPAddr             string
	DatabaseDSN          string
	JWTSecret            string
	AccessTokenTTLMin    int
	RefreshTokenTTLDays  int
	RecoveryTokenTTLMin  int
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

	return Config{
		HTTPAddr:            httpAddr,
		DatabaseDSN:         dsn,
		JWTSecret:           jwtSecret,
		AccessTokenTTLMin:   accessTTL,
		RefreshTokenTTLDays: refreshTTL,
		RecoveryTokenTTLMin: recoveryTTL,
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
