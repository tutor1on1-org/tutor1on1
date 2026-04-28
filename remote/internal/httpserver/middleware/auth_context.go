package middleware

import (
	"database/sql"
	"errors"
	"strings"

	"family_teacher_remote/internal/httpserver/handlers"

	"github.com/gofiber/fiber/v2"
)

type AuthContextMiddleware struct {
	jwtSecrets []string
	db         *sql.DB
}

func NewAuthContext(jwtSecrets []string, db *sql.DB) *AuthContextMiddleware {
	return &AuthContextMiddleware{
		jwtSecrets: jwtSecrets,
		db:         db,
	}
}

func (m *AuthContextMiddleware) Handler(c *fiber.Ctx) error {
	auth := strings.TrimSpace(c.Get("Authorization"))
	if auth == "" {
		return c.Next()
	}
	ctx, err := handlers.ParseAuthContextFromBearerHeader(auth, m.jwtSecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	if ctx.DeviceKey == "" || ctx.DeviceSessionNonce == "" {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	if m.db != nil &&
		ctx.DeviceKey != "" &&
		ctx.DeviceSessionNonce != "" {
		var userActive int
		if err := m.db.QueryRow(
			"SELECT 1 FROM users WHERE id = ? AND status <> 'deleted' LIMIT 1",
			ctx.UserID,
		).Scan(&userActive); err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
			}
			return fiber.NewError(fiber.StatusInternalServerError, "auth validation failed")
		}
		active, activeErr := handlers.ParseDeviceSessionValidation(
			m.db,
			ctx.UserID,
			ctx.DeviceKey,
			ctx.DeviceSessionNonce,
		)
		if activeErr != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "auth validation failed")
		}
		if !active {
			return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
		}
	}
	c.Locals(handlers.AuthLocalValidatedKey, true)
	c.Locals(handlers.AuthLocalUserIDKey, ctx.UserID)
	c.Locals(handlers.AuthLocalDeviceKeyKey, ctx.DeviceKey)
	c.Locals(handlers.AuthLocalDeviceSessionNonceKey, ctx.DeviceSessionNonce)
	return c.Next()
}
