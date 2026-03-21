package handlers

import (
	"database/sql"
	"net/http"
	"strconv"
	"strings"
	"testing"
	"time"

	"family_teacher_remote/internal/config"
	storepkg "family_teacher_remote/internal/db"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gofiber/fiber/v2"
	"github.com/golang-jwt/jwt/v5"
)

func TestDeleteAccountDeviceRejectsLastDevice(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(501)
	mock.ExpectBegin()
	mock.ExpectQuery(`SELECT device_key
		 FROM app_user_devices
		 WHERE user_id = \?
		 FOR UPDATE`).
		WithArgs(userID).
		WillReturnRows(
			sqlmock.NewRows([]string{"device_key"}).
				AddRow("device-a"),
		)
	mock.ExpectRollback()

	app := buildAccountDevicesTestApp(db)
	token := signTestJWTWithDevice(t, "secret", userID, "device-a", "nonce-a")
	status, body, _ := callAPI(
		t,
		app,
		http.MethodPost,
		"/api/account/devices/device-a/delete",
		token,
		"{}",
	)
	if status != http.StatusConflict {
		t.Fatalf("status = %d, want %d (body=%q)", status, http.StatusConflict, body)
	}
	assertSQLMockExpectations(t, mock)
}

func TestDeleteAccountDeviceDeletesOtherDevice(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(502)
	mock.ExpectBegin()
	mock.ExpectQuery(`SELECT device_key
		 FROM app_user_devices
		 WHERE user_id = \?
		 FOR UPDATE`).
		WithArgs(userID).
		WillReturnRows(
			sqlmock.NewRows([]string{"device_key"}).
				AddRow("device-a").
				AddRow("device-b"),
		)
	mock.ExpectExec(`DELETE FROM app_user_devices
		 WHERE user_id = \? AND device_key = \?`).
		WithArgs(userID, "device-b").
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec(`UPDATE refresh_tokens
		 SET revoked_at = NOW\(\)
		 WHERE user_id = \? AND device_key = \? AND revoked_at IS NULL`).
		WithArgs(userID, "device-b").
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	app := buildAccountDevicesTestApp(db)
	token := signTestJWTWithDevice(t, "secret", userID, "device-a", "nonce-a")
	status, body, _ := callAPI(
		t,
		app,
		http.MethodPost,
		"/api/account/devices/device-b/delete",
		token,
		"{}",
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d (body=%q)", status, http.StatusOK, body)
	}
	assertSQLMockExpectations(t, mock)
}

func buildAccountDevicesTestApp(db *sql.DB) *fiber.App {
	deps := Dependencies{
		Config: config.Config{
			JWTVerifySecrets: []string{"secret"},
		},
		Store: &storepkg.Store{DB: db},
	}
	accountDevices := NewAccountDevicesHandler(deps)
	app := fiber.New()
	app.Use(func(c *fiber.Ctx) error {
		ctx, err := ParseAuthContextFromBearerHeader(
			c.Get("Authorization"),
			[]string{"secret"},
		)
		if err != nil {
			return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
		}
		c.Locals(AuthLocalValidatedKey, true)
		c.Locals(AuthLocalUserIDKey, ctx.UserID)
		c.Locals(AuthLocalDeviceKeyKey, ctx.DeviceKey)
		c.Locals(AuthLocalDeviceSessionNonceKey, ctx.DeviceSessionNonce)
		return c.Next()
	})
	app.Get("/api/account/devices", accountDevices.ListAccountDevices)
	app.Post("/api/account/devices/:deviceKey/delete", accountDevices.DeleteAccountDevice)
	return app
}

func signTestJWTWithDevice(
	t *testing.T,
	secret string,
	userID int64,
	deviceKey string,
	sessionNonce string,
) string {
	t.Helper()
	claims := jwt.MapClaims{
		"sub": strconv.FormatInt(userID, 10),
		"iat": time.Now().Unix(),
		"exp": time.Now().Add(10 * time.Minute).Unix(),
	}
	if strings.TrimSpace(deviceKey) != "" {
		claims["device_key"] = deviceKey
	}
	if strings.TrimSpace(sessionNonce) != "" {
		claims["device_session_nonce"] = sessionNonce
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString([]byte(secret))
	if err != nil {
		t.Fatalf("SignedString() error = %v", err)
	}
	return signed
}
