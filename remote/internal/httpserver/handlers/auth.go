package handlers

import (
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"math/big"
	"strings"
	"time"

	"family_teacher_remote/internal/config"
	"family_teacher_remote/internal/db"
	"family_teacher_remote/internal/mailer"
	"family_teacher_remote/internal/storage"

	"github.com/gofiber/fiber/v2"
	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

type Dependencies struct {
	Config  config.Config
	Store   *db.Store
	Storage *storage.Service
	Mailer  *mailer.Service
}

type AuthHandler struct {
	cfg    config.Config
	store  *db.Store
	mailer *mailer.Service
}

func NewAuthHandler(deps Dependencies) *AuthHandler {
	return &AuthHandler{
		cfg:    deps.Config,
		store:  deps.Store,
		mailer: deps.Mailer,
	}
}

type registerRequest struct {
	Username string `json:"username"`
	Email    string `json:"email"`
	Password string `json:"password"`
	authDevicePayload
}

type registerTeacherRequest struct {
	Username         string  `json:"username"`
	Email            string  `json:"email"`
	Password         string  `json:"password"`
	DisplayName      string  `json:"display_name"`
	Bio              string  `json:"bio"`
	AvatarURL        string  `json:"avatar_url"`
	Contact          string  `json:"contact"`
	ContactPublished bool    `json:"contact_published"`
	SubjectLabelIDs  []int64 `json:"subject_label_ids"`
	authDevicePayload
}

type loginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
	authDevicePayload
}

type changePasswordRequest struct {
	CurrentPassword string `json:"current_password"`
	NewPassword     string `json:"new_password"`
}

type recoveryRequest struct {
	Email string `json:"email"`
}

type resetPasswordRequest struct {
	Email         string `json:"email"`
	RecoveryToken string `json:"recovery_token"`
	NewPassword   string `json:"new_password"`
}

type updateRecoveryEmailRequest struct {
	CurrentPassword string `json:"current_password"`
	Email           string `json:"email"`
}

type refreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

type revokeRequest struct {
	RefreshToken string `json:"refresh_token"`
}

type authDevicePayload struct {
	DeviceKey             string `json:"device_key"`
	DeviceName            string `json:"device_name"`
	Platform              string `json:"platform"`
	TimezoneName          string `json:"timezone_name"`
	TimezoneOffsetMinutes int    `json:"timezone_offset_minutes"`
	AppVersion            string `json:"app_version"`
}

type authDeviceSession struct {
	DeviceKey          string
	DeviceSessionNonce string
}

func (h *AuthHandler) Register(c *fiber.Ctx) error {
	return h.RegisterStudent(c)
}

func (h *AuthHandler) RegisterStudent(c *fiber.Ctx) error {
	var req registerRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	username := normalizeUsername(req.Username)
	email := normalizeEmail(req.Email)
	if username == "" || email == "" || strings.TrimSpace(req.Password) == "" {
		return fiber.NewError(fiber.StatusBadRequest, "username, email, and password required")
	}
	if h.store == nil || h.store.DB == nil {
		return fiber.NewError(fiber.StatusServiceUnavailable, "database unavailable")
	}
	hashed, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "password hash failed")
	}
	res, err := h.store.DB.Exec(
		"INSERT INTO users (username, email, password_hash, status) VALUES (?, ?, ?, ?)",
		username, email, string(hashed), "active",
	)
	if err != nil {
		return userInsertError(err)
	}
	userID, err := res.LastInsertId()
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "user insert failed")
	}
	deviceSession, deviceErr := h.createAuthDeviceSession(userID, req.authDevicePayload)
	if deviceErr != nil {
		if errors.Is(deviceErr, errDeviceLimitReached) {
			return fiber.NewError(fiber.StatusConflict, "device limit reached")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "device session failed")
	}
	return h.issueTokensWithRole(c, userID, "student", nil, deviceSession)
}

func (h *AuthHandler) RegisterTeacher(c *fiber.Ctx) error {
	var req registerTeacherRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	username := normalizeUsername(req.Username)
	email := normalizeEmail(req.Email)
	displayName := strings.TrimSpace(req.DisplayName)
	if username == "" || email == "" || strings.TrimSpace(req.Password) == "" || displayName == "" {
		return fiber.NewError(fiber.StatusBadRequest, "username, email, password, and display_name required")
	}
	if h.store == nil || h.store.DB == nil {
		return fiber.NewError(fiber.StatusServiceUnavailable, "database unavailable")
	}
	hashed, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "password hash failed")
	}
	tx, err := h.store.DB.Begin()
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "transaction failed")
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()
	res, err := tx.Exec(
		"INSERT INTO users (username, email, password_hash, status) VALUES (?, ?, ?, ?)",
		username, email, string(hashed), "active",
	)
	if err != nil {
		return userInsertError(err)
	}
	userID, err := res.LastInsertId()
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "user insert failed")
	}
	res, err = tx.Exec(
		`INSERT INTO teacher_accounts
		 (user_id, display_name, bio, avatar_url, contact, contact_published, status)
		 VALUES (?, ?, ?, ?, ?, ?, 'pending')`,
		userID,
		displayName,
		nullableString(req.Bio),
		nullableString(req.AvatarURL),
		nullableString(req.Contact),
		req.ContactPublished,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "teacher insert failed")
	}
	teacherID, err := res.LastInsertId()
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "teacher insert failed")
	}
	labelIDs, err := resolveSubjectLabelIDsTx(tx, req.SubjectLabelIDs)
	if err != nil {
		return err
	}
	if err := replaceTeacherSubjectLabelsTx(tx, teacherID, labelIDs); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "teacher labels save failed")
	}
	if _, err := tx.Exec(
		`INSERT INTO teacher_registration_requests (user_id, teacher_id, status)
		 VALUES (?, ?, 'pending')`,
		userID,
		teacherID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "teacher request insert failed")
	}
	if err := tx.Commit(); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "commit failed")
	}
	deviceSession, deviceErr := h.createAuthDeviceSession(userID, req.authDevicePayload)
	if deviceErr != nil {
		if errors.Is(deviceErr, errDeviceLimitReached) {
			return fiber.NewError(fiber.StatusConflict, "device limit reached")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "device session failed")
	}
	return h.issueTokensWithRole(
		c,
		userID,
		"teacher_pending",
		&teacherID,
		deviceSession,
	)
}

func (h *AuthHandler) Login(c *fiber.Ctx) error {
	var req loginRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	username := normalizeUsername(req.Username)
	if username == "" || req.Password == "" {
		return fiber.NewError(fiber.StatusBadRequest, "username and password required")
	}
	userID, passwordHash, err := h.getUserAuthByUsername(username)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "invalid credentials")
	}
	if bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(req.Password)) != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "invalid credentials")
	}
	role, teacherID, err := h.getUserRole(userID)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "role lookup failed")
	}
	deviceSession, deviceErr := h.createAuthDeviceSession(userID, req.authDevicePayload)
	if deviceErr != nil {
		if errors.Is(deviceErr, errDeviceLimitReached) {
			return fiber.NewError(fiber.StatusConflict, "device limit reached")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "device session failed")
	}
	return h.issueTokensWithRole(c, userID, role, teacherID, deviceSession)
}

func (h *AuthHandler) ChangePassword(c *fiber.Ctx) error {
	if h.store == nil || h.store.DB == nil {
		return fiber.NewError(fiber.StatusServiceUnavailable, "database unavailable")
	}
	userID, err := requireUserID(c, h.cfg.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	var req changePasswordRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	if strings.TrimSpace(req.CurrentPassword) == "" || strings.TrimSpace(req.NewPassword) == "" {
		return fiber.NewError(fiber.StatusBadRequest, "current_password and new_password required")
	}
	currentHash, err := h.getUserAuthByID(userID)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "invalid credentials")
	}
	if bcrypt.CompareHashAndPassword([]byte(currentHash), []byte(req.CurrentPassword)) != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "invalid credentials")
	}
	newHash, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "password hash failed")
	}
	if _, err := h.store.DB.Exec(
		"UPDATE users SET password_hash = ? WHERE id = ?",
		string(newHash), userID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "password update failed")
	}
	if _, err := h.store.DB.Exec(
		"UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = ? AND revoked_at IS NULL",
		userID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "token revoke failed")
	}
	return c.JSON(fiber.Map{"status": "ok"})
}

func (h *AuthHandler) GetAccountProfile(c *fiber.Ctx) error {
	if h.store == nil || h.store.DB == nil {
		return fiber.NewError(fiber.StatusServiceUnavailable, "database unavailable")
	}
	userID, err := requireUserID(c, h.cfg.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	row := h.store.DB.QueryRow(
		"SELECT username, email FROM users WHERE id = ? LIMIT 1",
		userID,
	)
	var username string
	var email string
	if err := row.Scan(&username, &email); err != nil {
		return fiber.NewError(fiber.StatusNotFound, "account not found")
	}
	role, _, err := h.getUserRole(userID)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "role lookup failed")
	}
	return c.JSON(fiber.Map{
		"user_id":   userID,
		"username":  username,
		"email":     email,
		"role":      role,
		"has_email": strings.TrimSpace(email) != "",
	})
}

func (h *AuthHandler) UpdateRecoveryEmail(c *fiber.Ctx) error {
	if h.store == nil || h.store.DB == nil {
		return fiber.NewError(fiber.StatusServiceUnavailable, "database unavailable")
	}
	userID, err := requireUserID(c, h.cfg.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	var req updateRecoveryEmailRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	email := normalizeEmail(req.Email)
	currentPassword := strings.TrimSpace(req.CurrentPassword)
	if email == "" || currentPassword == "" {
		return fiber.NewError(fiber.StatusBadRequest, "email and current_password required")
	}
	currentHash, err := h.getUserAuthByID(userID)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "invalid credentials")
	}
	if bcrypt.CompareHashAndPassword([]byte(currentHash), []byte(req.CurrentPassword)) != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "invalid credentials")
	}
	if _, err := h.store.DB.Exec(
		"UPDATE users SET email = ? WHERE id = ?",
		email, userID,
	); err != nil {
		return userEmailUpdateError(err)
	}
	return c.JSON(fiber.Map{"status": "ok"})
}

func (h *AuthHandler) RequestRecovery(c *fiber.Ctx) error {
	if h.store == nil || h.store.DB == nil {
		return fiber.NewError(fiber.StatusServiceUnavailable, "database unavailable")
	}
	if (h.mailer == nil || !h.mailer.Enabled()) && !h.cfg.RecoveryTokenEcho {
		return fiber.NewError(fiber.StatusServiceUnavailable, "smtp not configured")
	}
	var req recoveryRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	email := normalizeEmail(req.Email)
	if email == "" {
		return fiber.NewError(fiber.StatusBadRequest, "email required")
	}
	userID, err := h.getUserIDByEmail(email)
	userExists := err == nil
	token, err := randomDigitsToken(6)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "token generation failed")
	}
	hash := hashToken(token)
	expiresAt := time.Now().Add(time.Duration(h.cfg.RecoveryTokenTTLMin) * time.Minute)
	if userExists {
		if _, err := h.store.DB.Exec(
			"DELETE FROM password_resets WHERE user_id = ? AND used_at IS NULL",
			userID,
		); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "recovery cleanup failed")
		}
		if _, err := h.store.DB.Exec(
			"INSERT INTO password_resets (user_id, token_hash, expires_at) VALUES (?, ?, ?)",
			userID, hash, expiresAt,
		); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "recovery insert failed")
		}
	}
	if userExists && h.mailer != nil && h.mailer.Enabled() {
		if err := h.mailer.SendRecoveryEmail(email, token, h.cfg.RecoveryTokenTTLMin); err != nil {
			return fiber.NewError(fiber.StatusServiceUnavailable, "recovery email failed")
		}
	}
	response := fiber.Map{
		"status":     "ok",
		"expires_in": h.cfg.RecoveryTokenTTLMin * 60,
	}
	if h.cfg.RecoveryTokenEcho {
		response["recovery_token"] = token
	}
	return c.JSON(response)
}

func (h *AuthHandler) ResetPassword(c *fiber.Ctx) error {
	if h.store == nil || h.store.DB == nil {
		return fiber.NewError(fiber.StatusServiceUnavailable, "database unavailable")
	}
	var req resetPasswordRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	email := normalizeEmail(req.Email)
	if email == "" || strings.TrimSpace(req.RecoveryToken) == "" || strings.TrimSpace(req.NewPassword) == "" {
		return fiber.NewError(fiber.StatusBadRequest, "email, recovery_token, and new_password required")
	}
	userID, err := h.getUserIDByEmail(email)
	if err != nil {
		return fiber.NewError(fiber.StatusNotFound, "email not found")
	}
	tokenHash := hashToken(strings.TrimSpace(req.RecoveryToken))
	var (
		resetID   int64
		expiresAt time.Time
		usedAt    *time.Time
	)
	row := h.store.DB.QueryRow(
		"SELECT id, expires_at, used_at FROM password_resets WHERE token_hash = ? AND user_id = ? LIMIT 1",
		tokenHash, userID,
	)
	if err := row.Scan(&resetID, &expiresAt, &usedAt); err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "invalid recovery token")
	}
	if usedAt != nil || time.Now().After(expiresAt) {
		return fiber.NewError(fiber.StatusUnauthorized, "recovery token expired")
	}
	newHash, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "password hash failed")
	}
	tx, err := h.store.DB.Begin()
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "transaction failed")
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()
	if _, err = tx.Exec(
		"UPDATE users SET password_hash = ? WHERE id = ?",
		string(newHash), userID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "password update failed")
	}
	if _, err = tx.Exec(
		"UPDATE password_resets SET used_at = NOW() WHERE id = ?",
		resetID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "recovery update failed")
	}
	if _, err = tx.Exec(
		"UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = ? AND revoked_at IS NULL",
		userID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "token revoke failed")
	}
	if err := tx.Commit(); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "commit failed")
	}
	return c.JSON(fiber.Map{"status": "ok"})
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
		id                 int64
		userID             int64
		expiresAt          time.Time
		revokedAt          *time.Time
		deviceKey          sql.NullString
		deviceSessionNonce sql.NullString
	)
	row := h.store.DB.QueryRow(
		`SELECT id, user_id, expires_at, revoked_at, device_key, device_session_nonce
		 FROM refresh_tokens
		 WHERE token_hash = ? LIMIT 1`,
		hash,
	)
	if err := row.Scan(
		&id,
		&userID,
		&expiresAt,
		&revokedAt,
		&deviceKey,
		&deviceSessionNonce,
	); err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "invalid refresh token")
	}
	if revokedAt != nil || time.Now().After(expiresAt) {
		return fiber.NewError(fiber.StatusUnauthorized, "refresh token expired")
	}
	normalizedDeviceKey := strings.TrimSpace(deviceKey.String)
	normalizedSessionNonce := strings.TrimSpace(deviceSessionNonce.String)
	if !deviceKey.Valid || !deviceSessionNonce.Valid ||
		normalizedDeviceKey == "" || normalizedSessionNonce == "" {
		return fiber.NewError(fiber.StatusUnauthorized, "invalid refresh token")
	}
	active, activeErr := isActiveAppUserDeviceSession(
		h.store.DB,
		userID,
		normalizedDeviceKey,
		normalizedSessionNonce,
	)
	if activeErr != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "device session validation failed")
	}
	if !active {
		return fiber.NewError(fiber.StatusUnauthorized, "invalid refresh token")
	}
	if _, err := h.store.DB.Exec(
		"UPDATE refresh_tokens SET revoked_at = NOW() WHERE id = ?",
		id,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "token revoke failed")
	}
	role, teacherID, err := h.getUserRole(userID)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "role lookup failed")
	}
	return h.issueTokensWithRole(
		c,
		userID,
		role,
		teacherID,
		authDeviceSession{
			DeviceKey:          normalizedDeviceKey,
			DeviceSessionNonce: normalizedSessionNonce,
		},
	)
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

func (h *AuthHandler) issueTokensWithRole(
	c *fiber.Ctx,
	userID int64,
	role string,
	teacherID *int64,
	deviceSession authDeviceSession,
) error {
	accessToken, err := h.newAccessToken(userID, deviceSession)
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
		`INSERT INTO refresh_tokens (
		   user_id,
		   device_key,
		   device_session_nonce,
		   token_hash,
		   expires_at
		 ) VALUES (?, ?, ?, ?, ?)`,
		userID,
		nullableString(deviceSession.DeviceKey),
		nullableString(deviceSession.DeviceSessionNonce),
		refreshHash,
		expiresAt,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "refresh token save failed")
	}
	return c.JSON(fiber.Map{
		"access_token":  accessToken,
		"refresh_token": refreshToken,
		"token_type":    "bearer",
		"expires_in":    h.cfg.AccessTokenTTLMin * 60,
		"user_id":       userID,
		"role":          role,
		"teacher_id":    teacherID,
	})
}

func (h *AuthHandler) newAccessToken(
	userID int64,
	deviceSession authDeviceSession,
) (string, error) {
	claims := jwt.MapClaims{
		"sub": userID,
		"exp": time.Now().Add(time.Duration(h.cfg.AccessTokenTTLMin) * time.Minute).Unix(),
		"iat": time.Now().Unix(),
	}
	if strings.TrimSpace(deviceSession.DeviceKey) != "" {
		claims["device_key"] = strings.TrimSpace(deviceSession.DeviceKey)
	}
	if strings.TrimSpace(deviceSession.DeviceSessionNonce) != "" {
		claims["device_session_nonce"] = strings.TrimSpace(deviceSession.DeviceSessionNonce)
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(h.cfg.JWTSecret))
}

func (h *AuthHandler) createAuthDeviceSession(
	userID int64,
	payload authDevicePayload,
) (authDeviceSession, error) {
	sessionNonce, normalized, err := upsertAppUserDeviceSession(
		h.store.DB,
		userID,
		appUserDeviceSessionInput{
			DeviceKey:             payload.DeviceKey,
			DeviceName:            payload.DeviceName,
			Platform:              payload.Platform,
			TimezoneName:          payload.TimezoneName,
			TimezoneOffsetMinutes: payload.TimezoneOffsetMinutes,
			AppVersion:            payload.AppVersion,
		},
	)
	if err != nil {
		return authDeviceSession{}, err
	}
	return authDeviceSession{
		DeviceKey:          normalized.DeviceKey,
		DeviceSessionNonce: sessionNonce,
	}, nil
}

func (h *AuthHandler) getUserAuthByUsername(username string) (int64, string, error) {
	row := h.store.DB.QueryRow("SELECT id, password_hash FROM users WHERE username = ? LIMIT 1", username)
	var id int64
	var hash string
	if err := row.Scan(&id, &hash); err != nil {
		return 0, "", errors.New("not found")
	}
	return id, hash, nil
}

func (h *AuthHandler) getUserAuthByID(userID int64) (string, error) {
	row := h.store.DB.QueryRow("SELECT password_hash FROM users WHERE id = ? LIMIT 1", userID)
	var hash string
	if err := row.Scan(&hash); err != nil {
		return "", errors.New("not found")
	}
	return hash, nil
}

func (h *AuthHandler) getUserIDByEmail(email string) (int64, error) {
	row := h.store.DB.QueryRow("SELECT id FROM users WHERE email = ? LIMIT 1", email)
	var id int64
	if err := row.Scan(&id); err != nil {
		return 0, errors.New("not found")
	}
	return id, nil
}

func (h *AuthHandler) getUserRole(userID int64) (string, *int64, error) {
	admin, err := isAdminUser(h.store.DB, userID)
	if err != nil {
		return "", nil, err
	}
	if admin {
		return "admin", nil, nil
	}
	var teacherID int64
	var status string
	row := h.store.DB.QueryRow(
		"SELECT id, status FROM teacher_accounts WHERE user_id = ? LIMIT 1",
		userID,
	)
	if err := row.Scan(&teacherID, &status); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "student", nil, nil
		}
		return "", nil, err
	}
	switch strings.TrimSpace(strings.ToLower(status)) {
	case "active":
		return "teacher", &teacherID, nil
	case "rejected":
		return "teacher_rejected", &teacherID, nil
	default:
		return "teacher_pending", &teacherID, nil
	}
}

func normalizeEmail(value string) string {
	return strings.TrimSpace(strings.ToLower(value))
}

func normalizeUsername(value string) string {
	return strings.TrimSpace(strings.ToLower(value))
}

func nullableString(value string) sql.NullString {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return sql.NullString{Valid: false}
	}
	return sql.NullString{String: trimmed, Valid: true}
}

func userInsertError(err error) error {
	message := strings.ToLower(err.Error())
	if strings.Contains(message, "duplicate entry") {
		if strings.Contains(message, "uq_users_username") || strings.Contains(message, "users.username") {
			return fiber.NewError(fiber.StatusBadRequest, "username already exists")
		}
		if strings.Contains(message, "users.email") {
			return fiber.NewError(fiber.StatusBadRequest, "email already exists")
		}
		return fiber.NewError(fiber.StatusBadRequest, "duplicate user")
	}
	return fiber.NewError(fiber.StatusInternalServerError, "user insert failed")
}

func userEmailUpdateError(err error) error {
	message := strings.ToLower(err.Error())
	if strings.Contains(message, "duplicate entry") && strings.Contains(message, "users.email") {
		return fiber.NewError(fiber.StatusBadRequest, "email already exists")
	}
	return fiber.NewError(fiber.StatusInternalServerError, "email update failed")
}

func randomToken(byteLen int) (string, error) {
	buf := make([]byte, byteLen)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return hex.EncodeToString(buf), nil
}

func randomDigitsToken(length int) (string, error) {
	if length <= 0 {
		return "", errors.New("invalid token length")
	}
	var builder strings.Builder
	builder.Grow(length)
	for i := 0; i < length; i++ {
		n, err := rand.Int(rand.Reader, big.NewInt(10))
		if err != nil {
			return "", err
		}
		builder.WriteByte(byte('0') + byte(n.Int64()))
	}
	return builder.String(), nil
}

func hashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}
