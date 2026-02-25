package handlers

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"strings"
	"time"

	"family_teacher_remote/internal/config"
	"family_teacher_remote/internal/db"

	"github.com/gofiber/fiber/v2"
	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

type Dependencies struct {
	Config config.Config
	Store  *db.Store
}

type AuthHandler struct {
	cfg   config.Config
	store *db.Store
}

func NewAuthHandler(deps Dependencies) *AuthHandler {
	return &AuthHandler{
		cfg:   deps.Config,
		store: deps.Store,
	}
}

type registerRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type loginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type refreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

type revokeRequest struct {
	RefreshToken string `json:"refresh_token"`
}

func (h *AuthHandler) Register(c *fiber.Ctx) error {
	var req registerRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	email := strings.TrimSpace(strings.ToLower(req.Email))
	if email == "" || req.Password == "" {
		return fiber.NewError(fiber.StatusBadRequest, "email and password required")
	}
	if h.store == nil || h.store.DB == nil {
		return fiber.NewError(fiber.StatusServiceUnavailable, "database unavailable")
	}
	hashed, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "password hash failed")
	}
	_, err = h.store.DB.Exec(
		"INSERT INTO users (email, password_hash, status) VALUES (?, ?, ?)",
		email, string(hashed), "active",
	)
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "email already exists")
	}
	return c.JSON(fiber.Map{"status": "ok"})
}

func (h *AuthHandler) Login(c *fiber.Ctx) error {
	var req loginRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	email := strings.TrimSpace(strings.ToLower(req.Email))
	if email == "" || req.Password == "" {
		return fiber.NewError(fiber.StatusBadRequest, "email and password required")
	}
	userID, passwordHash, err := h.getUserAuthByEmail(email)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "invalid credentials")
	}
	if bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(req.Password)) != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "invalid credentials")
	}
	return h.issueTokens(c, userID)
}

func (h *AuthHandler) Refresh(c *fiber.Ctx) error {
	var req refreshRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	token := strings.TrimSpace(req.RefreshToken)
	if token == "" {
		return fiber.NewError(fiber.StatusBadRequest, "refresh_token required")
	}
	hash := hashToken(token)
	var (
		id        int64
		userID    int64
		expiresAt time.Time
		revokedAt *time.Time
	)
	row := h.store.DB.QueryRow(
		"SELECT id, user_id, expires_at, revoked_at FROM refresh_tokens WHERE token_hash = ? LIMIT 1",
		hash,
	)
	if err := row.Scan(&id, &userID, &expiresAt, &revokedAt); err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "invalid refresh token")
	}
	if revokedAt != nil || time.Now().After(expiresAt) {
		return fiber.NewError(fiber.StatusUnauthorized, "refresh token expired")
	}
	if _, err := h.store.DB.Exec(
		"UPDATE refresh_tokens SET revoked_at = NOW() WHERE id = ?",
		id,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "token revoke failed")
	}
	return h.issueTokens(c, userID)
}

func (h *AuthHandler) Revoke(c *fiber.Ctx) error {
	var req revokeRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	token := strings.TrimSpace(req.RefreshToken)
	if token == "" {
		return fiber.NewError(fiber.StatusBadRequest, "refresh_token required")
	}
	hash := hashToken(token)
	_, err := h.store.DB.Exec(
		"UPDATE refresh_tokens SET revoked_at = NOW() WHERE token_hash = ?",
		hash,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "token revoke failed")
	}
	return c.JSON(fiber.Map{"status": "ok"})
}

func (h *AuthHandler) issueTokens(c *fiber.Ctx, userID int64) error {
	accessToken, err := h.newAccessToken(userID)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "access token failed")
	}
	refreshToken, err := randomToken(32)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "refresh token failed")
	}
	refreshHash := hashToken(refreshToken)
	expiresAt := time.Now().Add(time.Duration(h.cfg.RefreshTokenTTLDays) * 24 * time.Hour)
	_, err = h.store.DB.Exec(
		"INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES (?, ?, ?)",
		userID, refreshHash, expiresAt,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "refresh token save failed")
	}
	return c.JSON(fiber.Map{
		"access_token":  accessToken,
		"refresh_token": refreshToken,
		"token_type":    "bearer",
		"expires_in":    h.cfg.AccessTokenTTLMin * 60,
	})
}

func (h *AuthHandler) newAccessToken(userID int64) (string, error) {
	claims := jwt.MapClaims{
		"sub": userID,
		"exp": time.Now().Add(time.Duration(h.cfg.AccessTokenTTLMin) * time.Minute).Unix(),
		"iat": time.Now().Unix(),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(h.cfg.JWTSecret))
}

func (h *AuthHandler) getUserAuthByEmail(email string) (int64, string, error) {
	row := h.store.DB.QueryRow("SELECT id, password_hash FROM users WHERE email = ? LIMIT 1", email)
	var id int64
	var hash string
	if err := row.Scan(&id, &hash); err != nil {
		return 0, "", errors.New("not found")
	}
	return id, hash, nil
}

func randomToken(byteLen int) (string, error) {
	buf := make([]byte, byteLen)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return hex.EncodeToString(buf), nil
}

func hashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}
