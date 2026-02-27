package handlers

import (
	"errors"
	"strconv"
	"strings"

	"github.com/gofiber/fiber/v2"
	"github.com/golang-jwt/jwt/v5"
)

func requireUserID(c *fiber.Ctx, jwtSecrets []string) (int64, error) {
	auth := strings.TrimSpace(c.Get("Authorization"))
	if auth == "" {
		return 0, errors.New("missing authorization")
	}
	parts := strings.Fields(auth)
	if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
		return 0, errors.New("invalid authorization header")
	}
	tokenStr := parts[1]
	for _, secret := range jwtSecrets {
		secret = strings.TrimSpace(secret)
		if secret == "" {
			continue
		}
		userID, err := parseUserIDFromToken(tokenStr, secret)
		if err == nil {
			return userID, nil
		}
	}
	return 0, errors.New("invalid token")
}

func parseUserIDFromToken(tokenStr string, jwtSecret string) (int64, error) {
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
		return 0, errors.New("invalid token")
	}
	sub, ok := claims["sub"]
	if !ok {
		return 0, errors.New("missing sub claim")
	}
	switch v := sub.(type) {
	case int64:
		return v, nil
	case int:
		return int64(v), nil
	case float64:
		return int64(v), nil
	case string:
		parsed, err := strconv.ParseInt(v, 10, 64)
		if err != nil {
			return 0, errors.New("invalid sub claim")
		}
		return parsed, nil
	default:
		return 0, errors.New("invalid sub type")
	}
}
