package handlers

import (
	"database/sql"
	"testing"
	"time"

	storepkg "family_teacher_remote/internal/db"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gofiber/fiber/v2"
)

func TestScheduleCandidateMatchesOneTimeReconnectWindow(t *testing.T) {
	now := time.Date(2026, time.March, 19, 9, 30, 0, 0, time.UTC)
	candidate := scheduleCandidate{
		Mode: "one_time",
		StartAtUTC: sql.NullTime{
			Time:  now.Add(-15 * time.Minute),
			Valid: true,
		},
		EndAtUTC: sql.NullTime{
			Time:  now.Add(30 * time.Minute),
			Valid: true,
		},
	}

	if !scheduleCandidateMatches(candidate, 4, 570, now) {
		t.Fatal("expected one-time schedule to remain active after reconnect inside window")
	}
}

func TestScheduleCandidateMatchesWeeklyOvernightWindow(t *testing.T) {
	candidate := scheduleCandidate{
		Mode: "weekly",
		LocalWeekday: sql.NullInt64{
			Int64: 5,
			Valid: true,
		},
		LocalStartMinuteOfDay: sql.NullInt64{
			Int64: 22 * 60,
			Valid: true,
		},
		LocalEndMinuteOfDay: sql.NullInt64{
			Int64: 90,
			Valid: true,
		},
	}

	if !scheduleCandidateMatches(candidate, 6, 45, time.Now().UTC()) {
		t.Fatal("expected overnight weekly schedule to match next-day local time")
	}
	if scheduleCandidateMatches(candidate, 6, 180, time.Now().UTC()) {
		t.Fatal("expected overnight weekly schedule to end after local cutoff")
	}
}

func TestRequireTeacherControlPinRejectsInvalidPin(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	teacherUserID := int64(91)
	mock.ExpectQuery(`SELECT control_pin_hash
		 FROM teacher_accounts
		 WHERE user_id = \? LIMIT 1`).
		WithArgs(teacherUserID).
		WillReturnRows(
			sqlmock.NewRows([]string{"control_pin_hash"}).
				AddRow(hashControlPin("1234")),
		)

	handler := &StudyModeHandler{
		cfg: Dependencies{
			Store: &storepkg.Store{DB: db},
		},
	}
	err := handler.requireTeacherControlPin(teacherUserID, "9999")
	fiberErr, ok := err.(*fiber.Error)
	if !ok {
		t.Fatalf("err type = %T, want *fiber.Error", err)
	}
	if fiberErr.Code != fiber.StatusForbidden {
		t.Fatalf("status = %d, want %d", fiberErr.Code, fiber.StatusForbidden)
	}
	assertSQLMockExpectations(t, mock)
}
