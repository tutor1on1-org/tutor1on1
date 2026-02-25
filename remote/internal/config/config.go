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

	return Config{
		HTTPAddr:            httpAddr,
		DatabaseDSN:         dsn,
		JWTSecret:           jwtSecret,
		AccessTokenTTLMin:   accessTTL,
		RefreshTokenTTLDays: refreshTTL,
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
