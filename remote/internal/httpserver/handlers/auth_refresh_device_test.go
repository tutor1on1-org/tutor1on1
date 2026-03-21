package handlers

import (
	"database/sql"
	"net/http"
	"testing"
	"time"

	"family_teacher_remote/internal/config"
	storepkg "family_teacher_remote/internal/db"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gofiber/fiber/v2"
)

func TestRefreshRejectsLegacyTokenWithoutDeviceBinding(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	refreshToken := "legacy-refresh-token"
	mock.ExpectQuery(`SELECT id, user_id, expires_at, revoked_at, device_key, device_session_nonce
		 FROM refresh_tokens
		 WHERE token_hash = \? LIMIT 1`).
		WithArgs(hashToken(refreshToken)).
		WillReturnRows(
			sqlmock.NewRows(
				[]string{
					"id",
					"user_id",
					"expires_at",
					"revoked_at",
					"device_key",
					"device_session_nonce",
				},
			).AddRow(
				int64(1),
				int64(7001),
				time.Now().Add(time.Hour),
				nil,
				nil,
				nil,
			),
		)

	app := buildRefreshTestApp(db)
	status, body, _ := callAPI(
		t,
		app,
		http.MethodPost,
		"/api/auth/refresh",
		"",
		`{"refresh_token":"`+refreshToken+`"}`,
	)
	if status != http.StatusUnauthorized {
		t.Fatalf("status = %d, want %d (body=%q)", status, http.StatusUnauthorized, body)
	}
	assertSQLMockExpectations(t, mock)
}

func buildRefreshTestApp(db *sql.DB) *fiber.App {
	deps := Dependencies{
		Config: config.Config{
			JWTSecret:           "current-secret",
			RefreshTokenTTLDays: 30,
		},
		Store: &storepkg.Store{DB: db},
	}
	auth := NewAuthHandler(deps)
	app := fiber.New()
	app.Post("/api/auth/refresh", auth.Refresh)
	return app
}
