package handlers

import (
	"database/sql"
	"net/http"
	"strings"
	"testing"
	"time"

	"family_teacher_remote/internal/config"
	storepkg "family_teacher_remote/internal/db"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gofiber/fiber/v2"
)

func TestLoginRequestParsesFlatDevicePayload(t *testing.T) {
	app := fiber.New()
	app.Post("/parse", func(c *fiber.Ctx) error {
		var req loginRequest
		if err := c.BodyParser(&req); err != nil {
			return fiber.NewError(fiber.StatusBadRequest, "bad body")
		}
		return c.JSON(fiber.Map{
			"device_key":              req.DeviceKey,
			"device_name":             req.DeviceName,
			"platform":                req.Platform,
			"timezone_name":           req.TimezoneName,
			"timezone_offset_minutes": req.TimezoneOffsetMinutes,
			"app_version":             req.AppVersion,
		})
	})

	status, body, _ := callAPI(
		t,
		app,
		http.MethodPost,
		"/parse",
		"",
		`{
		  "username":"student",
		  "password":"pw",
		  "device_key":"device-a",
		  "device_name":"Study Tablet",
		  "platform":"android",
		  "timezone_name":"UTC",
		  "timezone_offset_minutes":30,
		  "app_version":"test-version"
		}`,
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d (body=%q)", status, http.StatusOK, body)
	}
	for _, snippet := range []string{
		`"device_key":"device-a"`,
		`"device_name":"Study Tablet"`,
		`"platform":"android"`,
		`"timezone_name":"UTC"`,
		`"timezone_offset_minutes":30`,
		`"app_version":"test-version"`,
	} {
		if !strings.Contains(body, snippet) {
			t.Fatalf("body = %q, want contains %q", body, snippet)
		}
	}
}

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
