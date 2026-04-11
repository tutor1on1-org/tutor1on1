package handlers

import (
	"fmt"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestUpsertAppUserDeviceSessionEvictsOldestDeviceAtLimit(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(88)
	mock.ExpectBegin()
	rows := sqlmock.NewRows([]string{"id", "device_key"})
	for i := 1; i <= maxAppUserDevicesPerUser; i++ {
		rows.AddRow(int64(i), fmt.Sprintf("device-%d", i))
	}
	mock.ExpectQuery(`SELECT id, device_key
		 FROM app_user_devices`).
		WithArgs(userID).
		WillReturnRows(rows)
	mock.ExpectExec(`UPDATE refresh_tokens
		 SET revoked_at = NOW\(\)
		 WHERE user_id = \? AND device_key = \? AND revoked_at IS NULL`).
		WithArgs(userID, "device-1").
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec(`DELETE FROM app_user_devices
		 WHERE user_id = \? AND device_key = \?`).
		WithArgs(userID, "device-1").
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec(`UPDATE app_user_devices
		 SET auth_session_nonce = NULL
		 WHERE user_id = \? AND device_key <> \?`).
		WithArgs(userID, "device-11").
		WillReturnResult(sqlmock.NewResult(0, 9))
	mock.ExpectExec(`INSERT INTO app_user_devices`).
		WithArgs(
			userID,
			"device-11",
			"Tablet 11",
			"android",
			sqlmock.AnyArg(),
			0,
			sqlmock.AnyArg(),
			sqlmock.AnyArg(),
			sqlmock.AnyArg(),
		).
		WillReturnResult(sqlmock.NewResult(11, 1))
	mock.ExpectExec(`UPDATE refresh_tokens
		 SET revoked_at = NOW\(\)
		 WHERE user_id = \? AND revoked_at IS NULL`).
		WithArgs(userID).
		WillReturnResult(sqlmock.NewResult(0, 9))
	mock.ExpectCommit()

	sessionNonce, normalized, err := upsertAppUserDeviceSession(
		db,
		userID,
		appUserDeviceSessionInput{
			DeviceKey:  "device-11",
			DeviceName: "Tablet 11",
			Platform:   "android",
		},
	)
	if err != nil {
		t.Fatalf("upsertAppUserDeviceSession() error = %v", err)
	}
	if sessionNonce == "" {
		t.Fatal("sessionNonce is empty")
	}
	if normalized.DeviceKey != "device-11" {
		t.Fatalf("normalized.DeviceKey = %q, want device-11", normalized.DeviceKey)
	}
	assertSQLMockExpectations(t, mock)
}

func TestUpsertAppUserDeviceSessionDoesNotEvictExistingDeviceAtLimit(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(89)
	rows := sqlmock.NewRows([]string{"id", "device_key"})
	for i := 1; i <= maxAppUserDevicesPerUser; i++ {
		rows.AddRow(int64(i), fmt.Sprintf("device-%d", i))
	}
	mock.ExpectBegin()
	mock.ExpectQuery(`SELECT id, device_key
		 FROM app_user_devices`).
		WithArgs(userID).
		WillReturnRows(rows)
	mock.ExpectExec(`UPDATE app_user_devices
		 SET auth_session_nonce = NULL
		 WHERE user_id = \? AND device_key <> \?`).
		WithArgs(userID, "device-2").
		WillReturnResult(sqlmock.NewResult(0, 9))
	mock.ExpectExec(`INSERT INTO app_user_devices`).
		WithArgs(
			userID,
			"device-2",
			"Tablet 2",
			"android",
			sqlmock.AnyArg(),
			0,
			sqlmock.AnyArg(),
			sqlmock.AnyArg(),
			sqlmock.AnyArg(),
		).
		WillReturnResult(sqlmock.NewResult(2, 2))
	mock.ExpectExec(`UPDATE refresh_tokens
		 SET revoked_at = NOW\(\)
		 WHERE user_id = \? AND revoked_at IS NULL`).
		WithArgs(userID).
		WillReturnResult(sqlmock.NewResult(0, 9))
	mock.ExpectCommit()

	_, _, err := upsertAppUserDeviceSession(
		db,
		userID,
		appUserDeviceSessionInput{
			DeviceKey:  "device-2",
			DeviceName: "Tablet 2",
			Platform:   "android",
		},
	)
	if err != nil {
		t.Fatalf("upsertAppUserDeviceSession() error = %v", err)
	}
	assertSQLMockExpectations(t, mock)
}
