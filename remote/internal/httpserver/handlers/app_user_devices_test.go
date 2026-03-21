package handlers

import (
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestUpsertAppUserDeviceSessionRejectsEleventhDevice(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(88)
	mock.ExpectBegin()
	mock.ExpectQuery(`SELECT id FROM app_user_devices
		 WHERE user_id = \? AND device_key = \?
		 LIMIT 1`).
		WithArgs(userID, "device-11").
		WillReturnRows(sqlmock.NewRows([]string{"id"}))
	mock.ExpectQuery(`SELECT COUNT\(\*\)
			 FROM app_user_devices
			 WHERE user_id = \?`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(10))
	mock.ExpectRollback()

	_, _, err := upsertAppUserDeviceSession(
		db,
		userID,
		appUserDeviceSessionInput{
			DeviceKey:  "device-11",
			DeviceName: "Tablet 11",
			Platform:   "android",
		},
	)
	if err != errDeviceLimitReached {
		t.Fatalf("err = %v, want %v", err, errDeviceLimitReached)
	}
	assertSQLMockExpectations(t, mock)
}
