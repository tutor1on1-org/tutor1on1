package config

import (
	"reflect"
	"strings"
	"testing"
)

func TestLoadIncludesPreviousJWTSecretsForVerification(t *testing.T) {
	setRequiredEnv(t)
	t.Setenv("JWT_PREVIOUS_SECRETS", " legacy-a ,legacy-b,legacy-a ")
	t.Setenv("APP_ENV", "development")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	if cfg.JWTSecret != "primary-secret" {
		t.Fatalf("JWTSecret = %q, want primary-secret", cfg.JWTSecret)
	}
	wantVerify := []string{"primary-secret", "legacy-a", "legacy-b"}
	if !reflect.DeepEqual(cfg.JWTVerifySecrets, wantVerify) {
		t.Fatalf("JWTVerifySecrets = %#v, want %#v", cfg.JWTVerifySecrets, wantVerify)
	}
	if cfg.Environment != "development" {
		t.Fatalf("Environment = %q, want development", cfg.Environment)
	}
}

func TestLoadRejectsRecoveryTokenEchoInProduction(t *testing.T) {
	setRequiredEnv(t)
	t.Setenv("APP_ENV", "production")
	t.Setenv("RECOVERY_TOKEN_ECHO", "true")

	_, err := Load()
	if err == nil {
		t.Fatal("Load() expected error, got nil")
	}
	if !strings.Contains(err.Error(), "RECOVERY_TOKEN_ECHO must be false in production") {
		t.Fatalf("Load() error = %q, want production RECOVERY_TOKEN_ECHO error", err.Error())
	}
}

func TestLoadUsesEnvProfileFallback(t *testing.T) {
	setRequiredEnv(t)
	t.Setenv("APP_ENV", "")
	t.Setenv("ENV_PROFILE", "staging")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if cfg.Environment != "staging" {
		t.Fatalf("Environment = %q, want staging", cfg.Environment)
	}
}

func setRequiredEnv(t *testing.T) {
	t.Helper()
	t.Setenv("DB_DSN", "user:pass@tcp(127.0.0.1:3306)/family_teacher?parseTime=true")
	t.Setenv("JWT_SECRET", "primary-secret")
	t.Setenv("JWT_PREVIOUS_SECRETS", "")
	t.Setenv("STORAGE_ROOT", "/tmp/storage")
}
