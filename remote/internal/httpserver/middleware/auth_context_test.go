package middleware

import (
	"database/sql"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"

	"family_teacher_remote/internal/httpserver/handlers"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gofiber/fiber/v2"
	"github.com/golang-jwt/jwt/v5"
)

func TestAuthContextRejectsTokenWithoutDeviceBinding(t *testing.T) {
	db, mock := newAuthContextSQLMock(t)
	defer db.Close()

	app := buildAuthContextTestApp(db)
	token := signAuthContextJWT(t, "secret", 401, "", "")
	status, body := callAuthContextRoute(t, app, token)
	if status != http.StatusUnauthorized {
		t.Fatalf("status = %d, want %d (body=%q)", status, http.StatusUnauthorized, body)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("sql expectations not met: %v", err)
	}
}

func TestAuthContextAcceptsActiveDeviceSession(t *testing.T) {
	db, mock := newAuthContextSQLMock(t)
	defer db.Close()

	userID := int64(402)
	deviceKey := "device-a"
	sessionNonce := "nonce-a"
	mock.ExpectQuery(`SELECT 1
		 FROM app_user_devices
		 WHERE user_id = \?
		   AND device_key = \?
		   AND auth_session_nonce = \?
		 LIMIT 1`).
		WithArgs(userID, deviceKey, sessionNonce).
		WillReturnRows(sqlmock.NewRows([]string{"1"}).AddRow(1))

	app := buildAuthContextTestApp(db)
	token := signAuthContextJWT(t, "secret", userID, deviceKey, sessionNonce)
	status, body := callAuthContextRoute(t, app, token)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d (body=%q)", status, http.StatusOK, body)
	}
	if body != "402|device-a" {
		t.Fatalf("body = %q, want %q", body, "402|device-a")
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("sql expectations not met: %v", err)
	}
}

func TestAuthContextRejectsInactiveDeviceSession(t *testing.T) {
	db, mock := newAuthContextSQLMock(t)
	defer db.Close()

	userID := int64(403)
	deviceKey := "device-b"
	sessionNonce := "nonce-b"
	mock.ExpectQuery(`SELECT 1
		 FROM app_user_devices
		 WHERE user_id = \?
		   AND device_key = \?
		   AND auth_session_nonce = \?
		 LIMIT 1`).
		WithArgs(userID, deviceKey, sessionNonce).
		WillReturnRows(sqlmock.NewRows([]string{"1"}))

	app := buildAuthContextTestApp(db)
	token := signAuthContextJWT(t, "secret", userID, deviceKey, sessionNonce)
	status, body := callAuthContextRoute(t, app, token)
	if status != http.StatusUnauthorized {
		t.Fatalf("status = %d, want %d (body=%q)", status, http.StatusUnauthorized, body)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("sql expectations not met: %v", err)
	}
}

func newAuthContextSQLMock(t *testing.T) (*sql.DB, sqlmock.Sqlmock) {
	t.Helper()
	db, mock, err := sqlmock.New(sqlmock.QueryMatcherOption(sqlmock.QueryMatcherRegexp))
	if err != nil {
		t.Fatalf("sqlmock.New() error = %v", err)
	}
	return db, mock
}

func buildAuthContextTestApp(db *sql.DB) *fiber.App {
	app := fiber.New()
	app.Use(NewAuthContext([]string{"secret"}, db).Handler)
	app.Get("/protected", func(c *fiber.Ctx) error {
		userID, _ := c.Locals(handlers.AuthLocalUserIDKey).(int64)
		deviceKey, _ := c.Locals(handlers.AuthLocalDeviceKeyKey).(string)
		return c.SendString(fmt.Sprintf("%d|%s", userID, deviceKey))
	})
	return app
}

func signAuthContextJWT(
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

func callAuthContextRoute(t *testing.T, app *fiber.App, token string) (int, string) {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, "/protected", nil)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := app.Test(req)
	if err != nil {
		t.Fatalf("app.Test() error = %v", err)
	}
	defer resp.Body.Close()
	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("ReadAll() error = %v", err)
	}
	return resp.StatusCode, strings.TrimSpace(string(bodyBytes))
}
