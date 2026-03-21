package handlers

import (
	"database/sql"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
)

type AccountDevicesHandler struct {
	cfg Dependencies
}

type accountDeviceSummary struct {
	DeviceKey             string `json:"device_key"`
	DeviceName            string `json:"device_name"`
	Platform              string `json:"platform"`
	TimezoneName          string `json:"timezone_name"`
	TimezoneOffsetMinutes int    `json:"timezone_offset_minutes"`
	AppVersion            string `json:"app_version"`
	LastSeenAt            string `json:"last_seen_at"`
	Online                bool   `json:"online"`
	IsCurrent             bool   `json:"is_current"`
}

func NewAccountDevicesHandler(deps Dependencies) *AccountDevicesHandler {
	return &AccountDevicesHandler{cfg: deps}
}

func (h *AccountDevicesHandler) ListAccountDevices(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	currentDeviceKey, _ := c.Locals(AuthLocalDeviceKeyKey).(string)
	rows, err := h.cfg.Store.DB.Query(
		`SELECT device_key, device_name, platform,
		        timezone_name, timezone_offset_minutes, app_version,
		        last_seen_at, auth_session_nonce
		 FROM app_user_devices
		 WHERE user_id = ?
		 ORDER BY CASE WHEN device_key = ? THEN 0 ELSE 1 END,
		          COALESCE(last_seen_at, created_at) DESC, id DESC`,
		userID,
		strings.TrimSpace(currentDeviceKey),
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "account device list failed")
	}
	defer rows.Close()

	nowUTC := time.Now().UTC()
	results := []accountDeviceSummary{}
	for rows.Next() {
		var (
			deviceKey        string
			deviceName       string
			platform         string
			timezoneName     sql.NullString
			timezoneOffset   int
			appVersion       sql.NullString
			lastSeenAt       sql.NullTime
			authSessionNonce sql.NullString
		)
		if err := rows.Scan(
			&deviceKey,
			&deviceName,
			&platform,
			&timezoneName,
			&timezoneOffset,
			&appVersion,
			&lastSeenAt,
			&authSessionNonce,
		); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "account device list failed")
		}
		lastSeen := ""
		online := false
		if lastSeenAt.Valid {
			lastSeen = lastSeenAt.Time.UTC().Format(time.RFC3339)
			online = strings.TrimSpace(authSessionNonce.String) != "" &&
				nowUTC.Sub(lastSeenAt.Time.UTC()) <= 90*time.Second
		}
		results = append(results, accountDeviceSummary{
			DeviceKey:             deviceKey,
			DeviceName:            deviceName,
			Platform:              platform,
			TimezoneName:          timezoneName.String,
			TimezoneOffsetMinutes: timezoneOffset,
			AppVersion:            appVersion.String,
			LastSeenAt:            lastSeen,
			Online:                online,
			IsCurrent:             strings.TrimSpace(currentDeviceKey) == deviceKey,
		})
	}
	return c.JSON(results)
}

func (h *AccountDevicesHandler) DeleteAccountDevice(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	deviceKey := strings.TrimSpace(c.Params("deviceKey"))
	if deviceKey == "" {
		return fiber.NewError(fiber.StatusBadRequest, "device_key required")
	}

	tx, err := h.cfg.Store.DB.Begin()
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "device delete failed")
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()

	rows, err := tx.Query(
		`SELECT device_key
		 FROM app_user_devices
		 WHERE user_id = ?
		 FOR UPDATE`,
		userID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "device delete failed")
	}
	deviceKeys := []string{}
	targetExists := false
	for rows.Next() {
		var existingKey string
		if err := rows.Scan(&existingKey); err != nil {
			_ = rows.Close()
			return fiber.NewError(fiber.StatusInternalServerError, "device delete failed")
		}
		deviceKeys = append(deviceKeys, existingKey)
		if existingKey == deviceKey {
			targetExists = true
		}
	}
	_ = rows.Close()
	if !targetExists {
		return fiber.NewError(fiber.StatusNotFound, "device not found")
	}
	if len(deviceKeys) <= 1 {
		return fiber.NewError(fiber.StatusConflict, "cannot delete last device")
	}

	result, err := tx.Exec(
		`DELETE FROM app_user_devices
		 WHERE user_id = ? AND device_key = ?`,
		userID,
		deviceKey,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "device delete failed")
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "device delete failed")
	}
	if affected <= 0 {
		return fiber.NewError(fiber.StatusNotFound, "device not found")
	}
	if _, err := tx.Exec(
		`UPDATE refresh_tokens
		 SET revoked_at = NOW()
		 WHERE user_id = ? AND device_key = ? AND revoked_at IS NULL`,
		userID,
		deviceKey,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "device delete failed")
	}
	if err := tx.Commit(); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "device delete failed")
	}
	committed = true

	currentDeviceKey, _ := c.Locals(AuthLocalDeviceKeyKey).(string)
	return c.JSON(fiber.Map{
		"status":                 "deleted",
		"deleted_current_device": strings.TrimSpace(currentDeviceKey) == deviceKey,
	})
}
