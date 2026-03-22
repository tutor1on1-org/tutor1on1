package handlers

import (
	"database/sql"
	"net/http"
	"regexp"
	"strings"
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

func TestVerifyStudentStudyModeControlPinAcceptsActiveOverride(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	studentUserID := int64(301)
	mock.ExpectQuery(regexp.QuoteMeta(`
SELECT s.id, s.teacher_user_id, u.username,
        ta.control_pin_hash,
        s.mode, s.enabled, s.start_at_utc, s.end_at_utc,
        s.local_weekday, s.local_start_minute_of_day, s.local_end_minute_of_day,
        s.timezone_name_snapshot, s.timezone_offset_snapshot_minutes,
        s.updated_at, s.status
 FROM teacher_study_mode_schedules s
 JOIN users u ON u.id = s.teacher_user_id
 JOIN teacher_accounts ta ON ta.user_id = s.teacher_user_id
 WHERE s.student_user_id = ?
   AND s.status = 'active'
   AND EXISTS (
     SELECT 1
     FROM enrollments e
     WHERE e.student_id = s.student_user_id
       AND e.status = 'active'
       AND e.teacher_id = ta.id
   )
 ORDER BY s.updated_at DESC, s.id DESC`)).
		WithArgs(studentUserID).
		WillReturnRows(sqlmock.NewRows([]string{
			"id",
			"teacher_user_id",
			"username",
			"control_pin_hash",
			"mode",
			"enabled",
			"start_at_utc",
			"end_at_utc",
			"local_weekday",
			"local_start_minute_of_day",
			"local_end_minute_of_day",
			"timezone_name_snapshot",
			"timezone_offset_snapshot_minutes",
			"updated_at",
			"status",
		}))
	mock.ExpectQuery(regexp.QuoteMeta(`
SELECT o.teacher_user_id, u.username, ta.control_pin_hash, o.enabled
 FROM teacher_study_mode_overrides o
 JOIN users u ON u.id = o.teacher_user_id
 JOIN teacher_accounts ta ON ta.user_id = o.teacher_user_id
 WHERE o.student_user_id = ?
   AND EXISTS (
     SELECT 1
     FROM enrollments e
     WHERE e.student_id = o.student_user_id
       AND e.status = 'active'
       AND e.teacher_id = ta.id
   )
 ORDER BY o.updated_at DESC, o.id DESC
 LIMIT 1`)).
		WithArgs(studentUserID).
		WillReturnRows(
			sqlmock.NewRows([]string{
				"teacher_user_id",
				"username",
				"control_pin_hash",
				"enabled",
			}).AddRow(41, "teacher_a", hashControlPin("2468"), true),
		)

	handler := &StudyModeHandler{
		cfg: Dependencies{
			Store: &storepkg.Store{DB: db},
		},
	}
	app := fiber.New()
	app.Use(func(c *fiber.Ctx) error {
		c.Locals(AuthLocalValidatedKey, true)
		c.Locals(AuthLocalUserIDKey, studentUserID)
		return c.Next()
	})
	app.Post(
		"/api/student/study-mode/verify-control-pin",
		handler.VerifyStudentStudyModeControlPin,
	)

	status, body, _ := callAPI(
		t,
		app,
		http.MethodPost,
		"/api/student/study-mode/verify-control-pin",
		"",
		`{"control_pin":"2468","local_weekday":2,"local_minute_of_day":300}`,
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d (body=%q)", status, http.StatusOK, body)
	}
	if !strings.Contains(body, `"verified":true`) {
		t.Fatalf("body = %q, want verified=true", body)
	}
	assertSQLMockExpectations(t, mock)
}
