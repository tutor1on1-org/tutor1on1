package handlers

import (
	"errors"
	"strconv"
	"strings"

	"github.com/gofiber/fiber/v2"
	"github.com/golang-jwt/jwt/v5"
)

const (
	AuthLocalValidatedKey          = "auth_validated"
	AuthLocalUserIDKey             = "auth_user_id"
	AuthLocalDeviceKeyKey          = "auth_device_key"
	AuthLocalDeviceSessionNonceKey = "auth_device_session_nonce"
)

type AuthContext struct {
	UserID             int64
	DeviceKey          string
	DeviceSessionNonce string
}

func requireUserID(c *fiber.Ctx, jwtSecrets []string) (int64, error) {
	if validated, ok := c.Locals(AuthLocalValidatedKey).(bool); ok {
		if !validated {
			return 0, errors.New("invalid token")
		}
		userID, ok := c.Locals(AuthLocalUserIDKey).(int64)
		if ok && userID > 0 {
			return userID, nil
		}
		return 0, errors.New("missing user context")
	}
	ctx, err := ParseAuthContextFromBearerHeader(c.Get("Authorization"), jwtSecrets)
	if err != nil {
		return 0, err
	}
	return ctx.UserID, nil
}

func ParseAuthContextFromBearerHeader(
	authHeader string,
	jwtSecrets []string,
) (AuthContext, error) {
	auth := strings.TrimSpace(authHeader)
	if auth == "" {
		return AuthContext{}, errors.New("missing authorization")
	}
	parts := strings.Fields(auth)
	if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
		return AuthContext{}, errors.New("invalid authorization header")
	}
	tokenStr := parts[1]
	for _, secret := range jwtSecrets {
		secret = strings.TrimSpace(secret)
		if secret == "" {
			continue
		}
		ctx, err := parseAuthContextFromToken(tokenStr, secret)
		if err == nil {
			return ctx, nil
		}
	}
	return AuthContext{}, errors.New("invalid token")
}

func parseUserIDFromToken(tokenStr string, jwtSecret string) (int64, error) {
	ctx, err := parseAuthContextFromToken(tokenStr, jwtSecret)
	if err != nil {
		return 0, err
	}
	return ctx.UserID, nil
}

func parseAuthContextFromToken(
	tokenStr string,
	jwtSecret string,
) (AuthContext, error) {
	claims := jwt.MapClaims{}
	token, err := jwt.ParseWithClaims(
		tokenStr,
		claims,
		func(_ *jwt.Token) (interface{}, error) {
			return []byte(jwtSecret), nil
		},
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithExpirationRequired(),
	)
	if err != nil || !token.Valid {
		return AuthContext{}, errors.New("invalid token")
	}
	sub, ok := claims["sub"]
	if !ok {
		return AuthContext{}, errors.New("missing sub claim")
	}
	var userID int64
	switch v := sub.(type) {
	case int64:
		userID = v
	case int:
		userID = int64(v)
	case float64:
		userID = int64(v)
	case string:
		parsed, err := strconv.ParseInt(v, 10, 64)
		if err != nil {
			return AuthContext{}, errors.New("invalid sub claim")
		}
		userID = parsed
	default:
		return AuthContext{}, errors.New("invalid sub type")
	}
	deviceKey, _ := claims["device_key"].(string)
	deviceSessionNonce, _ := claims["device_session_nonce"].(string)
	return AuthContext{
		UserID:             userID,
		DeviceKey:          strings.TrimSpace(deviceKey),
		DeviceSessionNonce: strings.TrimSpace(deviceSessionNonce),
	}, nil
}
