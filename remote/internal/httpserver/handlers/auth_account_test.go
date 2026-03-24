package handlers

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"testing"

	"family_teacher_remote/internal/config"
	storepkg "family_teacher_remote/internal/db"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gofiber/fiber/v2"
	"golang.org/x/crypto/bcrypt"
)

func TestGetAccountProfileReturnsEmail(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(701)
	mock.ExpectQuery(`SELECT username, email FROM users WHERE id = \? LIMIT 1`).
		WithArgs(userID).
		WillReturnRows(
			sqlmock.NewRows([]string{"username", "email"}).
				AddRow("student1", "student@example.com"),
		)
	mock.ExpectQuery(`SELECT id FROM admin_accounts WHERE user_id = \? LIMIT 1`).
		WithArgs(userID).
		WillReturnError(sql.ErrNoRows)
	mock.ExpectQuery(`SELECT id, status FROM teacher_accounts WHERE user_id = \? LIMIT 1`).
		WithArgs(userID).
		WillReturnError(sql.ErrNoRows)

	app := buildAuthAccountTestApp(db)
	token := signTestJWTWithDevice(t, "secret", userID, "device-a", "nonce-a")
	status, body, _ := callAPI(
		t,
		app,
		http.MethodGet,
		"/api/account/profile",
		token,
		"",
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d (body=%q)", status, http.StatusOK, body)
	}

	var response map[string]interface{}
	if err := json.Unmarshal([]byte(body), &response); err != nil {
		t.Fatalf("json.Unmarshal() error = %v (body=%q)", err, body)
	}
	if got := response["email"]; got != "student@example.com" {
		t.Fatalf("email = %#v, want %q", got, "student@example.com")
	}
	if got := response["username"]; got != "student1" {
		t.Fatalf("username = %#v, want %q", got, "student1")
	}
	if got := response["role"]; got != "student" {
		t.Fatalf("role = %#v, want %q", got, "student")
	}
	assertSQLMockExpectations(t, mock)
}

func TestUpdateRecoveryEmailChangesEmail(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(702)
	passwordHash, err := bcrypt.GenerateFromPassword([]byte("secret123"), bcrypt.DefaultCost)
	if err != nil {
		t.Fatalf("GenerateFromPassword() error = %v", err)
	}
	mock.ExpectQuery(`SELECT password_hash FROM users WHERE id = \? LIMIT 1`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"password_hash"}).AddRow(string(passwordHash)))
	mock.ExpectExec(`UPDATE users SET email = \? WHERE id = \?`).
		WithArgs("new@example.com", userID).
		WillReturnResult(sqlmock.NewResult(0, 1))

	app := buildAuthAccountTestApp(db)
	token := signTestJWTWithDevice(t, "secret", userID, "device-a", "nonce-a")
	status, body, _ := callAPI(
		t,
		app,
		http.MethodPost,
		"/api/account/recovery-email",
		token,
		`{"current_password":"secret123","email":"New@Example.com"}`,
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d (body=%q)", status, http.StatusOK, body)
	}
	assertSQLMockExpectations(t, mock)
}

func TestUpdateRecoveryEmailRejectsBadPassword(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(703)
	passwordHash, err := bcrypt.GenerateFromPassword([]byte("secret123"), bcrypt.DefaultCost)
	if err != nil {
		t.Fatalf("GenerateFromPassword() error = %v", err)
	}
	mock.ExpectQuery(`SELECT password_hash FROM users WHERE id = \? LIMIT 1`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"password_hash"}).AddRow(string(passwordHash)))

	app := buildAuthAccountTestApp(db)
	token := signTestJWTWithDevice(t, "secret", userID, "device-a", "nonce-a")
	status, body, _ := callAPI(
		t,
		app,
		http.MethodPost,
		"/api/account/recovery-email",
		token,
		`{"current_password":"wrong","email":"new@example.com"}`,
	)
	if status != http.StatusUnauthorized {
		t.Fatalf("status = %d, want %d (body=%q)", status, http.StatusUnauthorized, body)
	}
	assertSQLMockExpectations(t, mock)
}

func buildAuthAccountTestApp(db *sql.DB) *fiber.App {
	deps := Dependencies{
		Config: config.Config{
			JWTVerifySecrets: []string{"secret"},
		},
		Store: &storepkg.Store{DB: db},
	}
	auth := NewAuthHandler(deps)
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
	app.Get("/api/account/profile", auth.GetAccountProfile)
	app.Post("/api/account/recovery-email", auth.UpdateRecoveryEmail)
	return app
}
