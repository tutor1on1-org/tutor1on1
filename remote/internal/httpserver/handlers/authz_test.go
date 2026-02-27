package handlers

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/golang-jwt/jwt/v5"
)

func TestRequireUserIDAcceptsPrimaryJWTSecret(t *testing.T) {
	app := buildAuthzTestApp([]string{"primary-secret"})
	token := signTestJWT(t, "primary-secret", 101, true)

	status, body := callProtected(t, app, token)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d (body=%q)", status, http.StatusOK, body)
	}
	if body != "101" {
		t.Fatalf("body = %q, want %q", body, "101")
	}
}

func TestRequireUserIDAcceptsLegacyJWTSecretDuringRotation(t *testing.T) {
	app := buildAuthzTestApp([]string{"primary-secret", "legacy-secret"})
	token := signTestJWT(t, "legacy-secret", 202, true)

	status, body := callProtected(t, app, token)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d (body=%q)", status, http.StatusOK, body)
	}
	if body != "202" {
		t.Fatalf("body = %q, want %q", body, "202")
	}
}

func TestRequireUserIDRejectsTokenWhenSecretDoesNotMatch(t *testing.T) {
	app := buildAuthzTestApp([]string{"primary-secret", "legacy-secret"})
	token := signTestJWT(t, "unknown-secret", 303, true)

	status, _ := callProtected(t, app, token)
	if status != http.StatusUnauthorized {
		t.Fatalf("status = %d, want %d", status, http.StatusUnauthorized)
	}
}

func TestRequireUserIDRejectsTokenMissingExpiration(t *testing.T) {
	app := buildAuthzTestApp([]string{"primary-secret"})
	token := signTestJWT(t, "primary-secret", 404, false)

	status, _ := callProtected(t, app, token)
	if status != http.StatusUnauthorized {
		t.Fatalf("status = %d, want %d", status, http.StatusUnauthorized)
	}
}

func buildAuthzTestApp(jwtSecrets []string) *fiber.App {
	app := fiber.New()
	app.Get("/protected", func(c *fiber.Ctx) error {
		userID, err := requireUserID(c, jwtSecrets)
		if err != nil {
			return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
		}
		return c.SendString(strconv.FormatInt(userID, 10))
	})
	return app
}

func signTestJWT(t *testing.T, secret string, userID int64, withExp bool) string {
	t.Helper()
	claims := jwt.MapClaims{
		"sub": strconv.FormatInt(userID, 10),
		"iat": time.Now().Unix(),
	}
	if withExp {
		claims["exp"] = time.Now().Add(10 * time.Minute).Unix()
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString([]byte(secret))
	if err != nil {
		t.Fatalf("SignedString() error = %v", err)
	}
	return signed
}

func callProtected(t *testing.T, app *fiber.App, token string) (int, string) {
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
