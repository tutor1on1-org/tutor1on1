package handlers

import (
	"database/sql"
	"errors"
	"strings"
	"time"
)

var errDeviceLimitReached = errors.New("device limit reached")

const maxAppUserDevicesPerUser = 10

type appUserDeviceSessionInput struct {
	DeviceKey             string
	DeviceName            string
	Platform              string
	TimezoneName          string
	TimezoneOffsetMinutes int
	AppVersion            string
}

func normalizeAppUserDeviceSessionInput(
	input appUserDeviceSessionInput,
) appUserDeviceSessionInput {
	deviceKey := strings.TrimSpace(input.DeviceKey)
	if deviceKey == "" {
		deviceKey = "legacy"
	}
	deviceName := strings.TrimSpace(input.DeviceName)
	if deviceName == "" {
		deviceName = "Device"
	}
	platform := strings.TrimSpace(strings.ToLower(input.Platform))
	if platform == "" {
		platform = "unknown"
	}
	timezoneName := strings.TrimSpace(input.TimezoneName)
	appVersion := strings.TrimSpace(input.AppVersion)
	if len(deviceKey) > 128 {
		deviceKey = deviceKey[:128]
	}
	if len(deviceName) > 255 {
		deviceName = deviceName[:255]
	}
	if len(platform) > 64 {
		platform = platform[:64]
	}
	if len(timezoneName) > 128 {
		timezoneName = timezoneName[:128]
	}
	if len(appVersion) > 64 {
		appVersion = appVersion[:64]
	}
	return appUserDeviceSessionInput{
		DeviceKey:             deviceKey,
		DeviceName:            deviceName,
		Platform:              platform,
		TimezoneName:          timezoneName,
		TimezoneOffsetMinutes: input.TimezoneOffsetMinutes,
		AppVersion:            appVersion,
	}
}

func upsertAppUserDeviceSession(
	db *sql.DB,
	userID int64,
	input appUserDeviceSessionInput,
) (string, appUserDeviceSessionInput, error) {
	if db == nil {
		return "", appUserDeviceSessionInput{}, errors.New("database unavailable")
	}
	normalized := normalizeAppUserDeviceSessionInput(input)
	tx, err := db.Begin()
	if err != nil {
		return "", appUserDeviceSessionInput{}, err
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()

	registeredDevices, existingID, err := lockAppUserDevicesForLogin(
		tx,
		userID,
		normalized.DeviceKey,
	)
	if err != nil {
		return "", appUserDeviceSessionInput{}, err
	}
	if existingID <= 0 && len(registeredDevices) >= maxAppUserDevicesPerUser {
		evictCount := len(registeredDevices) - maxAppUserDevicesPerUser + 1
		for _, device := range registeredDevices[:evictCount] {
			if err = evictAppUserDevice(tx, userID, device.DeviceKey); err != nil {
				return "", appUserDeviceSessionInput{}, err
			}
		}
	}

	sessionNonce, err := randomToken(16)
	if err != nil {
		return "", appUserDeviceSessionInput{}, err
	}

	if _, err = tx.Exec(
		`UPDATE app_user_devices
		 SET auth_session_nonce = NULL
		 WHERE user_id = ? AND device_key <> ?`,
		userID,
		normalized.DeviceKey,
	); err != nil {
		return "", appUserDeviceSessionInput{}, err
	}

	if _, err = tx.Exec(
		`INSERT INTO app_user_devices (
		   user_id,
		   device_key,
		   device_name,
		   platform,
		   timezone_name,
		   timezone_offset_minutes,
		   app_version,
		   auth_session_nonce,
		   last_seen_at
		 )
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
		 ON DUPLICATE KEY UPDATE
		   device_name = VALUES(device_name),
		   platform = VALUES(platform),
		   timezone_name = VALUES(timezone_name),
		   timezone_offset_minutes = VALUES(timezone_offset_minutes),
		   app_version = VALUES(app_version),
		   auth_session_nonce = VALUES(auth_session_nonce),
		   last_seen_at = VALUES(last_seen_at)`,
		userID,
		normalized.DeviceKey,
		normalized.DeviceName,
		normalized.Platform,
		nullableString(normalized.TimezoneName),
		normalized.TimezoneOffsetMinutes,
		nullableString(normalized.AppVersion),
		sessionNonce,
		time.Now().UTC(),
	); err != nil {
		return "", appUserDeviceSessionInput{}, err
	}

	if _, err = tx.Exec(
		`UPDATE refresh_tokens
		 SET revoked_at = NOW()
		 WHERE user_id = ? AND revoked_at IS NULL`,
		userID,
	); err != nil {
		return "", appUserDeviceSessionInput{}, err
	}

	if err = tx.Commit(); err != nil {
		return "", appUserDeviceSessionInput{}, err
	}
	committed = true
	return sessionNonce, normalized, nil
}

type registeredAppUserDevice struct {
	ID        int64
	DeviceKey string
}

func lockAppUserDevicesForLogin(
	tx *sql.Tx,
	userID int64,
	deviceKey string,
) ([]registeredAppUserDevice, int64, error) {
	rows, err := tx.Query(
		`SELECT id, device_key
		 FROM app_user_devices
		 WHERE user_id = ?
		 ORDER BY COALESCE(last_seen_at, created_at) ASC, id ASC
		 FOR UPDATE`,
		userID,
	)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	devices := []registeredAppUserDevice{}
	var existingID int64
	for rows.Next() {
		var device registeredAppUserDevice
		if err := rows.Scan(&device.ID, &device.DeviceKey); err != nil {
			return nil, 0, err
		}
		devices = append(devices, device)
		if device.DeviceKey == deviceKey {
			existingID = device.ID
		}
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}
	return devices, existingID, nil
}

func evictAppUserDevice(tx *sql.Tx, userID int64, deviceKey string) error {
	if _, err := tx.Exec(
		`UPDATE refresh_tokens
		 SET revoked_at = NOW()
		 WHERE user_id = ? AND device_key = ? AND revoked_at IS NULL`,
		userID,
		deviceKey,
	); err != nil {
		return err
	}
	result, err := tx.Exec(
		`DELETE FROM app_user_devices
		 WHERE user_id = ? AND device_key = ?`,
		userID,
		deviceKey,
	)
	if err != nil {
		return err
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if affected <= 0 {
		return sql.ErrNoRows
	}
	return nil
}

func isActiveAppUserDeviceSession(
	db *sql.DB,
	userID int64,
	deviceKey string,
	sessionNonce string,
) (bool, error) {
	if db == nil {
		return false, errors.New("database unavailable")
	}
	normalizedKey := strings.TrimSpace(deviceKey)
	normalizedNonce := strings.TrimSpace(sessionNonce)
	if normalizedKey == "" || normalizedNonce == "" {
		return false, nil
	}
	row := db.QueryRow(
		`SELECT 1
		 FROM app_user_devices
		 WHERE user_id = ?
		   AND device_key = ?
		   AND auth_session_nonce = ?
		 LIMIT 1`,
		userID,
		normalizedKey,
		normalizedNonce,
	)
	var ok int
	if err := row.Scan(&ok); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return false, nil
		}
		return false, err
	}
	return true, nil
}

func ParseDeviceSessionValidation(
	db *sql.DB,
	userID int64,
	deviceKey string,
	sessionNonce string,
) (bool, error) {
	return isActiveAppUserDeviceSession(db, userID, deviceKey, sessionNonce)
}
