package handlers

import (
	"bytes"
	"database/sql"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"family_teacher_remote/internal/config"
	storepkg "family_teacher_remote/internal/db"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gofiber/fiber/v2"
)

func TestSessionSyncListReturnsNotModifiedWhenETagMatches(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(3001)
	updatedAt := time.Date(2026, 2, 27, 9, 0, 0, 0, time.UTC)
	rows := sqlmock.NewRows([]string{
		"id",
		"session_sync_id",
		"course_id",
		"teacher_user_id",
		"student_user_id",
		"sender_user_id",
		"chapter_key",
		"updated_at",
		"envelope",
		"envelope_hash",
		"content_hash",
	}).AddRow(
		int64(1),
		"s1",
		int64(44),
		int64(901),
		userID,
		userID,
		"1.1",
		updatedAt,
		[]byte("session_payload"),
		"session_hash",
		"session_content_hash",
	)
	mock.ExpectQuery(`SELECT id, session_sync_id, course_id, teacher_user_id, student_user_id, sender_user_id, chapter_key, updated_at, envelope, envelope_hash, content_hash`).
		WithArgs(userID, userID, sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnRows(rows)
	rows2 := sqlmock.NewRows([]string{
		"id",
		"session_sync_id",
		"course_id",
		"teacher_user_id",
		"student_user_id",
		"sender_user_id",
		"chapter_key",
		"updated_at",
		"envelope",
		"envelope_hash",
		"content_hash",
	}).AddRow(
		int64(1),
		"s1",
		int64(44),
		int64(901),
		userID,
		userID,
		"1.1",
		updatedAt,
		[]byte("session_payload"),
		"session_hash",
		"session_content_hash",
	)
	mock.ExpectQuery(`SELECT id, session_sync_id, course_id, teacher_user_id, student_user_id, sender_user_id, chapter_key, updated_at, envelope, envelope_hash, content_hash`).
		WithArgs(userID, userID, sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnRows(rows2)

	app := buildSyncETagTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)

	status, _, headers := callAPI(
		t,
		app,
		http.MethodGet,
		"/api/sessions/sync/list",
		token,
		"",
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d", status, http.StatusOK)
	}
	etag := headers.Get("Etag")
	if strings.TrimSpace(etag) == "" {
		t.Fatal("missing ETag on session sync list response")
	}

	status, _, _ = callAPIWithExtraHeaders(
		t,
		app,
		http.MethodGet,
		"/api/sessions/sync/list",
		token,
		"",
		map[string]string{
			"If-None-Match": etag,
		},
	)
	if status != http.StatusNotModified {
		t.Fatalf("status = %d, want %d", status, http.StatusNotModified)
	}

	assertSQLMockExpectations(t, mock)
}

func TestProgressSyncListReturnsNotModifiedWhenETagMatches(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(3002)
	updatedAt := time.Date(2026, 2, 27, 9, 10, 0, 0, time.UTC)
	rows := sqlmock.NewRows([]string{
		"id",
		"course_id",
		"subject",
		"teacher_user_id",
		"student_user_id",
		"kp_key",
		"lit",
		"lit_percent",
		"question_level",
		"summary_text",
		"summary_raw_response",
		"summary_valid",
		"updated_at",
		"envelope",
		"envelope_hash",
		"content_hash",
	}).AddRow(
		int64(1),
		int64(55),
		"Biology",
		int64(901),
		userID,
		"1.1",
		true,
		80,
		"easy",
		"summary",
		"raw",
		true,
		updatedAt,
		[]byte("progress_payload"),
		"progress_hash",
		"progress_content_hash",
	)
	mock.ExpectQuery(`SELECT p.id, p.course_id, c.subject, p.teacher_user_id, p.student_user_id, p.kp_key, p.lit, p.lit_percent`).
		WithArgs(userID, sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnRows(rows)
	rows2 := sqlmock.NewRows([]string{
		"id",
		"course_id",
		"subject",
		"teacher_user_id",
		"student_user_id",
		"kp_key",
		"lit",
		"lit_percent",
		"question_level",
		"summary_text",
		"summary_raw_response",
		"summary_valid",
		"updated_at",
		"envelope",
		"envelope_hash",
		"content_hash",
	}).AddRow(
		int64(1),
		int64(55),
		"Biology",
		int64(901),
		userID,
		"1.1",
		true,
		80,
		"easy",
		"summary",
		"raw",
		true,
		updatedAt,
		[]byte("progress_payload"),
		"progress_hash",
		"progress_content_hash",
	)
	mock.ExpectQuery(`SELECT p.id, p.course_id, c.subject, p.teacher_user_id, p.student_user_id, p.kp_key, p.lit, p.lit_percent`).
		WithArgs(userID, sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnRows(rows2)

	app := buildSyncETagTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)

	status, _, headers := callAPI(
		t,
		app,
		http.MethodGet,
		"/api/progress/sync/list",
		token,
		"",
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d", status, http.StatusOK)
	}
	etag := headers.Get("Etag")
	if strings.TrimSpace(etag) == "" {
		t.Fatal("missing ETag on progress sync list response")
	}

	status, _, _ = callAPIWithExtraHeaders(
		t,
		app,
		http.MethodGet,
		"/api/progress/sync/list",
		token,
		"",
		map[string]string{
			"If-None-Match": etag,
		},
	)
	if status != http.StatusNotModified {
		t.Fatalf("status = %d, want %d", status, http.StatusNotModified)
	}

	assertSQLMockExpectations(t, mock)
}

func TestProgressSyncChunksListReturnsNotModifiedWhenETagMatches(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(3006)
	updatedAt := time.Date(2026, 2, 27, 9, 12, 0, 0, time.UTC)
	rows := sqlmock.NewRows([]string{
		"id",
		"course_id",
		"subject",
		"teacher_user_id",
		"student_user_id",
		"chapter_key",
		"item_count",
		"updated_at",
		"envelope",
		"envelope_hash",
		"content_hash",
	}).AddRow(
		int64(1),
		int64(77),
		"Biology",
		int64(901),
		userID,
		"1.1",
		24,
		updatedAt,
		[]byte("chunk_payload"),
		"chunk_hash",
		"chunk_content_hash",
	)
	mock.ExpectQuery(`SELECT p.id, p.course_id, c.subject, p.teacher_user_id, p.student_user_id, p.chapter_key, p.item_count, p.updated_at, p.envelope, p.envelope_hash, p.content_hash`).
		WithArgs(userID, sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnRows(rows)
	rows2 := sqlmock.NewRows([]string{
		"id",
		"course_id",
		"subject",
		"teacher_user_id",
		"student_user_id",
		"chapter_key",
		"item_count",
		"updated_at",
		"envelope",
		"envelope_hash",
		"content_hash",
	}).AddRow(
		int64(1),
		int64(77),
		"Biology",
		int64(901),
		userID,
		"1.1",
		24,
		updatedAt,
		[]byte("chunk_payload"),
		"chunk_hash",
		"chunk_content_hash",
	)
	mock.ExpectQuery(`SELECT p.id, p.course_id, c.subject, p.teacher_user_id, p.student_user_id, p.chapter_key, p.item_count, p.updated_at, p.envelope, p.envelope_hash, p.content_hash`).
		WithArgs(userID, sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnRows(rows2)

	app := buildSyncETagTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)

	status, _, headers := callAPI(
		t,
		app,
		http.MethodGet,
		"/api/progress/sync/chunks/list",
		token,
		"",
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d", status, http.StatusOK)
	}
	etag := headers.Get("Etag")
	if strings.TrimSpace(etag) == "" {
		t.Fatal("missing ETag on progress chunk sync list response")
	}

	status, _, _ = callAPIWithExtraHeaders(
		t,
		app,
		http.MethodGet,
		"/api/progress/sync/chunks/list",
		token,
		"",
		map[string]string{
			"If-None-Match": etag,
		},
	)
	if status != http.StatusNotModified {
		t.Fatalf("status = %d, want %d", status, http.StatusNotModified)
	}

	assertSQLMockExpectations(t, mock)
}

func TestSessionSyncListSinceIDIncludesEqualTimestampRows(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(3101)
	since := time.Date(2026, 2, 27, 9, 0, 0, 0, time.UTC)
	rows := sqlmock.NewRows([]string{
		"id",
		"session_sync_id",
		"course_id",
		"teacher_user_id",
		"student_user_id",
		"sender_user_id",
		"chapter_key",
		"updated_at",
		"envelope",
		"envelope_hash",
		"content_hash",
	}).AddRow(
		int64(11),
		"s-next",
		int64(44),
		int64(901),
		userID,
		userID,
		"1.1",
		since,
		[]byte("payload"),
		"hash",
		"content-hash",
	)
	mock.ExpectQuery(`SELECT id, session_sync_id, course_id, teacher_user_id, student_user_id, sender_user_id, chapter_key, updated_at, envelope, envelope_hash, content_hash`).
		WithArgs(userID, userID, since, since, int64(10), 5).
		WillReturnRows(rows)

	app := buildSyncETagTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)

	status, body, _ := callAPI(
		t,
		app,
		http.MethodGet,
		"/api/sessions/sync/list?since=2026-02-27T09:00:00Z&since_id=10&limit=5",
		token,
		"",
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d", status, http.StatusOK)
	}
	if !strings.Contains(body, `"cursor_id":11`) {
		t.Fatalf("response missing cursor row: %s", body)
	}
	if !strings.Contains(body, `"session_sync_id":"s-next"`) {
		t.Fatalf("response missing expected item: %s", body)
	}

	assertSQLMockExpectations(t, mock)
}

func TestProgressSyncListSinceIDIncludesEqualTimestampRows(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(3102)
	since := time.Date(2026, 2, 27, 9, 10, 0, 0, time.UTC)
	rows := sqlmock.NewRows([]string{
		"id",
		"course_id",
		"subject",
		"teacher_user_id",
		"student_user_id",
		"kp_key",
		"lit",
		"lit_percent",
		"question_level",
		"summary_text",
		"summary_raw_response",
		"summary_valid",
		"updated_at",
		"envelope",
		"envelope_hash",
		"content_hash",
	}).AddRow(
		int64(22),
		int64(55),
		"Biology",
		int64(901),
		userID,
		"1.1",
		true,
		80,
		"easy",
		"summary",
		"raw",
		true,
		since,
		[]byte("progress_payload"),
		"progress_hash",
		"progress_content_hash",
	)
	mock.ExpectQuery(`SELECT p.id, p.course_id, c.subject, p.teacher_user_id, p.student_user_id, p.kp_key, p.lit, p.lit_percent`).
		WithArgs(userID, since, since, int64(21), 5).
		WillReturnRows(rows)

	app := buildSyncETagTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)

	status, body, _ := callAPI(
		t,
		app,
		http.MethodGet,
		"/api/progress/sync/list?since=2026-02-27T09:10:00Z&since_id=21&limit=5",
		token,
		"",
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d", status, http.StatusOK)
	}
	if !strings.Contains(body, `"cursor_id":22`) {
		t.Fatalf("response missing cursor row: %s", body)
	}
	if !strings.Contains(body, `"kp_key":"1.1"`) {
		t.Fatalf("response missing expected item: %s", body)
	}

	assertSQLMockExpectations(t, mock)
}

func TestProgressSyncChunksListSinceIDIncludesEqualTimestampRows(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(3106)
	since := time.Date(2026, 2, 27, 9, 12, 0, 0, time.UTC)
	rows := sqlmock.NewRows([]string{
		"id",
		"course_id",
		"subject",
		"teacher_user_id",
		"student_user_id",
		"chapter_key",
		"item_count",
		"updated_at",
		"envelope",
		"envelope_hash",
		"content_hash",
	}).AddRow(
		int64(24),
		int64(77),
		"Biology",
		int64(901),
		userID,
		"1.1",
		24,
		since,
		[]byte("chunk_payload"),
		"chunk_hash",
		"chunk_content_hash",
	)
	mock.ExpectQuery(`SELECT p.id, p.course_id, c.subject, p.teacher_user_id, p.student_user_id, p.chapter_key, p.item_count, p.updated_at, p.envelope, p.envelope_hash, p.content_hash`).
		WithArgs(userID, since, since, int64(23), 5).
		WillReturnRows(rows)

	app := buildSyncETagTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)

	status, body, _ := callAPI(
		t,
		app,
		http.MethodGet,
		"/api/progress/sync/chunks/list?since=2026-02-27T09:12:00Z&since_id=23&limit=5",
		token,
		"",
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d", status, http.StatusOK)
	}
	if !strings.Contains(body, `"cursor_id":24`) {
		t.Fatalf("response missing cursor row: %s", body)
	}
	if !strings.Contains(body, `"chapter_key":"1.1"`) {
		t.Fatalf("response missing expected chunk: %s", body)
	}

	assertSQLMockExpectations(t, mock)
}

func TestEnrollmentListReturnsNotModifiedWhenETagMatches(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(3003)
	assignedAt := time.Date(2026, 2, 27, 9, 20, 0, 0, time.UTC)
	rows := sqlmock.NewRows([]string{
		"id",
		"course_id",
		"teacher_id",
		"status",
		"assigned_at",
		"subject",
		"display_name",
		"latest_bundle_version_id",
		"latest_bundle_hash",
		"latest_bundle_oss_path",
	}).AddRow(
		int64(1),
		int64(66),
		int64(77),
		"active",
		assignedAt,
		"Physics",
		"Teacher A",
		int64(5),
		nil,
		nil,
	)
	mock.ExpectQuery(`SELECT e.id, e.course_id, t.user_id, e.status, e.assigned_at`).
		WithArgs(userID).
		WillReturnRows(rows)
	rows2 := sqlmock.NewRows([]string{
		"id",
		"course_id",
		"teacher_id",
		"status",
		"assigned_at",
		"subject",
		"display_name",
		"latest_bundle_version_id",
		"latest_bundle_hash",
		"latest_bundle_oss_path",
	}).AddRow(
		int64(1),
		int64(66),
		int64(77),
		"active",
		assignedAt,
		"Physics",
		"Teacher A",
		int64(5),
		nil,
		nil,
	)
	mock.ExpectQuery(`SELECT e.id, e.course_id, t.user_id, e.status, e.assigned_at`).
		WithArgs(userID).
		WillReturnRows(rows2)

	app := buildSyncETagTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)

	status, _, headers := callAPI(
		t,
		app,
		http.MethodGet,
		"/api/enrollments",
		token,
		"",
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d", status, http.StatusOK)
	}
	etag := headers.Get("Etag")
	if strings.TrimSpace(etag) == "" {
		t.Fatal("missing ETag on enrollments list response")
	}

	status, _, _ = callAPIWithExtraHeaders(
		t,
		app,
		http.MethodGet,
		"/api/enrollments",
		token,
		"",
		map[string]string{
			"If-None-Match": etag,
		},
	)
	if status != http.StatusNotModified {
		t.Fatalf("status = %d, want %d", status, http.StatusNotModified)
	}

	assertSQLMockExpectations(t, mock)
}

func TestEnrollmentsSyncState2ReturnsCanonicalHash(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(3012)
	expected := buildState2([]string{
		buildStudentEnrollmentStateFingerprint(enrollmentSummary{
			CourseID:              66,
			TeacherID:             77,
			TeacherName:           "Teacher A",
			CourseName:            "Physics",
			LatestBundleVersionID: 5,
			LatestBundleHash:      "bundle-hash-5",
		}),
	})
	mock.ExpectQuery(`SELECT state2 FROM student_enrollment_sync_state2 WHERE user_id = \?`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"state2"}).AddRow(expected))

	app := buildSyncETagTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)

	status, body, _ := callAPI(
		t,
		app,
		http.MethodGet,
		"/api/enrollments/sync-state2",
		token,
		"",
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d body=%s", status, http.StatusOK, body)
	}
	if !strings.Contains(body, `"`+"state2"+`":"`+expected+`"`) {
		t.Fatalf("unexpected state2 response body: %s", body)
	}

	assertSQLMockExpectations(t, mock)
}

func TestEnrollmentsSyncState2ReturnsStoredHashWithoutRebuild(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(3412)
	mock.ExpectQuery(`SELECT state2 FROM student_enrollment_sync_state2 WHERE user_id = \?`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"state2"}).AddRow("stored-enrollment-state2"))

	app := buildSyncETagTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)

	status, body, _ := callAPI(
		t,
		app,
		http.MethodGet,
		"/api/enrollments/sync-state2",
		token,
		"",
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d body=%s", status, http.StatusOK, body)
	}
	if !strings.Contains(body, `"state2":"stored-enrollment-state2"`) {
		t.Fatalf("unexpected state2 response body: %s", body)
	}

	assertSQLMockExpectations(t, mock)
}

func TestEnrollmentsSyncState1ReturnsCanonicalItemsAndState2(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(3512)
	expected := buildState2([]string{
		buildStudentEnrollmentStateFingerprint(enrollmentSummary{
			CourseID:              66,
			TeacherID:             77,
			TeacherName:           "Teacher A",
			CourseName:            "Physics",
			LatestBundleVersionID: 5,
			LatestBundleHash:      "bundle-hash-5",
		}),
	})
	rows := sqlmock.NewRows([]string{
		"course_id",
		"teacher_user_id",
		"teacher_name",
		"course_subject",
		"latest_bundle_version_id",
		"latest_bundle_hash",
	}).AddRow(
		int64(66),
		int64(77),
		"Teacher A",
		"Physics",
		int64(5),
		"bundle-hash-5",
	)
	mock.ExpectQuery(`SELECT course_id, teacher_user_id, teacher_name, course_subject`).
		WithArgs(userID).
		WillReturnRows(rows)

	app := buildSyncETagTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)

	status, body, _ := callAPI(
		t,
		app,
		http.MethodGet,
		"/api/enrollments/sync-state1",
		token,
		"",
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d body=%s", status, http.StatusOK, body)
	}
	if !strings.Contains(body, `"`+"state2"+`":"`+expected+`"`) {
		t.Fatalf("unexpected sync-state1 response body: %s", body)
	}
	if !strings.Contains(body, `"course_id":66`) {
		t.Fatalf("missing enrollment item in response body: %s", body)
	}

	assertSQLMockExpectations(t, mock)
}

func TestTeacherCoursesListReturnsNotModifiedWhenETagMatches(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(3004)
	teacherID := int64(7004)
	mock.ExpectQuery(`SELECT id FROM teacher_accounts WHERE user_id = \? AND status = 'active' LIMIT 1`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(teacherID))
	rows := sqlmock.NewRows([]string{
		"id",
		"subject",
		"grade",
		"description",
		"visibility",
		"approval_status",
		"published_at",
		"latest_bundle_version_id",
		"latest_bundle_hash",
		"latest_bundle_oss_path",
	}).AddRow(
		int64(88),
		"Chemistry",
		"Grade 5",
		"Desc",
		"private",
		"pending",
		nil,
		int64(2),
		nil,
		nil,
	)
	mock.ExpectQuery(`SELECT c.id, c.subject, c.grade, c.description,\s*ce.visibility, ce.approval_status, ce.published_at`).
		WithArgs(teacherID, teacherID).
		WillReturnRows(rows)
	mock.ExpectQuery(`SELECT sl.id, sl.slug, sl.name, sl.is_active\s+FROM course_subject_labels csl`).
		WithArgs(int64(88)).
		WillReturnRows(sqlmock.NewRows([]string{"id", "slug", "name", "is_active"}))
	mock.ExpectQuery(`SELECT id FROM teacher_accounts WHERE user_id = \? AND status = 'active' LIMIT 1`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(teacherID))
	rows2 := sqlmock.NewRows([]string{
		"id",
		"subject",
		"grade",
		"description",
		"visibility",
		"approval_status",
		"published_at",
		"latest_bundle_version_id",
		"latest_bundle_hash",
		"latest_bundle_oss_path",
	}).AddRow(
		int64(88),
		"Chemistry",
		"Grade 5",
		"Desc",
		"private",
		"pending",
		nil,
		int64(2),
		nil,
		nil,
	)
	mock.ExpectQuery(`SELECT c.id, c.subject, c.grade, c.description,\s*ce.visibility, ce.approval_status, ce.published_at`).
		WithArgs(teacherID, teacherID).
		WillReturnRows(rows2)
	mock.ExpectQuery(`SELECT sl.id, sl.slug, sl.name, sl.is_active\s+FROM course_subject_labels csl`).
		WithArgs(int64(88)).
		WillReturnRows(sqlmock.NewRows([]string{"id", "slug", "name", "is_active"}))

	app := buildSyncETagTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)

	status, _, headers := callAPI(
		t,
		app,
		http.MethodGet,
		"/api/teacher/courses",
		token,
		"",
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d", status, http.StatusOK)
	}
	etag := headers.Get("Etag")
	if strings.TrimSpace(etag) == "" {
		t.Fatal("missing ETag on teacher courses list response")
	}

	status, _, _ = callAPIWithExtraHeaders(
		t,
		app,
		http.MethodGet,
		"/api/teacher/courses",
		token,
		"",
		map[string]string{
			"If-None-Match": etag,
		},
	)
	if status != http.StatusNotModified {
		t.Fatalf("status = %d, want %d", status, http.StatusNotModified)
	}

	assertSQLMockExpectations(t, mock)
}

func TestTeacherCoursesSyncState2ReturnsCanonicalHash(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(3013)
	teacherID := int64(7013)
	expected := buildState2([]string{
		buildTeacherCourseStateFingerprint(teacherCourseSummary{
			CourseID:              88,
			Subject:               "Chemistry",
			LatestBundleVersionID: 2,
			LatestBundleHash:      "bundle-hash-2",
		}),
	})
	mock.ExpectQuery(`SELECT id FROM teacher_accounts WHERE user_id = \? AND status = 'active' LIMIT 1`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(teacherID))
	mock.ExpectQuery(`SELECT state2 FROM teacher_course_sync_state2 WHERE user_id = \?`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"state2"}).AddRow(expected))

	app := buildSyncETagTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)

	status, body, _ := callAPI(
		t,
		app,
		http.MethodGet,
		"/api/teacher/courses/sync-state2",
		token,
		"",
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d body=%s", status, http.StatusOK, body)
	}
	if !strings.Contains(body, `"`+"state2"+`":"`+expected+`"`) {
		t.Fatalf("unexpected state2 response body: %s", body)
	}

	assertSQLMockExpectations(t, mock)
}

func TestTeacherCoursesSyncState2ReturnsStoredHashWithoutRebuild(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(3413)
	mock.ExpectQuery(`SELECT id FROM teacher_accounts WHERE user_id = \? AND status = 'active' LIMIT 1`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(int64(7413)))
	mock.ExpectQuery(`SELECT state2 FROM teacher_course_sync_state2 WHERE user_id = \?`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"state2"}).AddRow("stored-teacher-state2"))

	app := buildSyncETagTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)

	status, body, _ := callAPI(
		t,
		app,
		http.MethodGet,
		"/api/teacher/courses/sync-state2",
		token,
		"",
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d body=%s", status, http.StatusOK, body)
	}
	if !strings.Contains(body, `"state2":"stored-teacher-state2"`) {
		t.Fatalf("unexpected state2 response body: %s", body)
	}

	assertSQLMockExpectations(t, mock)
}

func TestTeacherCoursesSyncState1ReturnsCanonicalItemsAndState2(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(3513)
	teacherID := int64(7513)
	expected := buildState2([]string{
		buildTeacherCourseStateFingerprint(teacherCourseSummary{
			CourseID:              88,
			Subject:               "Chemistry",
			LatestBundleVersionID: 2,
			LatestBundleHash:      "bundle-hash-2",
		}),
	})
	mock.ExpectQuery(`SELECT id FROM teacher_accounts WHERE user_id = \? AND status = 'active' LIMIT 1`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(teacherID))
	rows := sqlmock.NewRows([]string{
		"course_id",
		"subject",
		"latest_bundle_version_id",
		"latest_bundle_hash",
	}).AddRow(
		int64(88),
		"Chemistry",
		int64(2),
		"bundle-hash-2",
	)
	mock.ExpectQuery(`SELECT course_id, subject, latest_bundle_version_id, latest_bundle_hash`).
		WithArgs(userID).
		WillReturnRows(rows)

	app := buildSyncETagTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)

	status, body, _ := callAPI(
		t,
		app,
		http.MethodGet,
		"/api/teacher/courses/sync-state1",
		token,
		"",
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d body=%s", status, http.StatusOK, body)
	}
	if !strings.Contains(body, `"`+"state2"+`":"`+expected+`"`) {
		t.Fatalf("unexpected sync-state1 response body: %s", body)
	}
	if !strings.Contains(body, `"course_id":88`) {
		t.Fatalf("missing teacher course item in response body: %s", body)
	}

	assertSQLMockExpectations(t, mock)
}

func TestDownloadManifestReturnsNotModifiedWhenETagMatches(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(3010)
	updatedAt := time.Date(2026, 3, 8, 8, 0, 0, 0, time.UTC)
	emptyState2 := encodeSyncDownloadState2(syncDownloadState2Aggregate{})
	mock.ExpectExec(`DELETE FROM sync_download_state_items`).
		WithArgs(userID, syncDownloadItemKindProgressChunk).
		WillReturnResult(sqlmock.NewResult(0, 0))
	mock.ExpectQuery(`SELECT state2 FROM sync_download_state2 WHERE user_id = \?`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"state2"}).AddRow(emptyState2))
	mock.ExpectExec(`DELETE FROM sync_download_state_items`).
		WithArgs(userID, syncDownloadItemKindProgressChunk).
		WillReturnResult(sqlmock.NewResult(0, 0))
	mock.ExpectQuery(`SELECT user_id, item_kind, scope_key, course_id, student_user_id, updated_at, content_hash FROM sync_download_state_items`).
		WithArgs(userID, syncDownloadItemKindProgressChunk).
		WillReturnRows(
			sqlmock.NewRows([]string{
				"user_id", "item_kind", "scope_key", "course_id", "student_user_id", "updated_at", "content_hash",
			}).AddRow(
				userID,
				syncDownloadItemKindSession,
				"s1",
				int64(88),
				userID,
				updatedAt,
				"session-hash",
			),
		)
	mock.ExpectExec(`DELETE FROM sync_download_state_items`).
		WithArgs(userID, syncDownloadItemKindProgressChunk).
		WillReturnResult(sqlmock.NewResult(0, 0))
	mock.ExpectQuery(`SELECT state2 FROM sync_download_state2 WHERE user_id = \?`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"state2"}).AddRow(emptyState2))
	mock.ExpectExec(`DELETE FROM sync_download_state_items`).
		WithArgs(userID, syncDownloadItemKindProgressChunk).
		WillReturnResult(sqlmock.NewResult(0, 0))
	mock.ExpectQuery(`SELECT user_id, item_kind, scope_key, course_id, student_user_id, updated_at, content_hash FROM sync_download_state_items`).
		WithArgs(userID, syncDownloadItemKindProgressChunk).
		WillReturnRows(
			sqlmock.NewRows([]string{
				"user_id", "item_kind", "scope_key", "course_id", "student_user_id", "updated_at", "content_hash",
			}).AddRow(
				userID,
				syncDownloadItemKindSession,
				"s1",
				int64(88),
				userID,
				updatedAt,
				"session-hash",
			),
		)

	app := buildSyncETagTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)

	status, _, headers := callAPI(
		t,
		app,
		http.MethodGet,
		"/api/sync/download-manifest?include_progress=false",
		token,
		"",
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d", status, http.StatusOK)
	}
	etag := headers.Get("Etag")
	if strings.TrimSpace(etag) == "" {
		t.Fatal("missing ETag on sync download manifest response")
	}

	status, _, _ = callAPIWithExtraHeaders(
		t,
		app,
		http.MethodGet,
		"/api/sync/download-manifest?include_progress=false",
		token,
		"",
		map[string]string{
			"If-None-Match": etag,
		},
	)
	if status != http.StatusNotModified {
		t.Fatalf("status = %d, want %d", status, http.StatusNotModified)
	}

	assertSQLMockExpectations(t, mock)
}

func TestDownloadState2ReturnsStoredAggregate(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(3010)
	mock.ExpectExec(`DELETE FROM sync_download_state_items`).
		WithArgs(userID, syncDownloadItemKindProgressChunk).
		WillReturnResult(sqlmock.NewResult(0, 0))
	mock.ExpectQuery(`SELECT state2 FROM sync_download_state2 WHERE user_id = \?`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"state2"}).AddRow("state2-abc"))

	app := buildSyncETagTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)

	status, body, _ := callAPI(
		t,
		app,
		http.MethodGet,
		"/api/sync/download-state2",
		token,
		"",
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d", status, http.StatusOK)
	}
	if !strings.Contains(body, `"state2":"state2-abc"`) {
		t.Fatalf("unexpected body: %s", body)
	}

	assertSQLMockExpectations(t, mock)
}

func TestDownloadState1ReturnsStoredMetadataItems(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(3012)
	updatedAt := time.Date(2026, 3, 8, 8, 2, 0, 0, time.UTC)
	mock.ExpectExec(`DELETE FROM sync_download_state_items`).
		WithArgs(userID, syncDownloadItemKindProgressChunk).
		WillReturnResult(sqlmock.NewResult(0, 0))
	mock.ExpectQuery(`SELECT state2 FROM sync_download_state2 WHERE user_id = \?`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"state2"}).AddRow("state2-xyz"))
	mock.ExpectExec(`DELETE FROM sync_download_state_items`).
		WithArgs(userID, syncDownloadItemKindProgressChunk).
		WillReturnResult(sqlmock.NewResult(0, 0))
	mock.ExpectQuery(`SELECT user_id, item_kind, scope_key, course_id, student_user_id, updated_at, content_hash FROM sync_download_state_items`).
		WithArgs(userID, syncDownloadItemKindProgressChunk).
		WillReturnRows(
			sqlmock.NewRows([]string{
				"user_id", "item_kind", "scope_key", "course_id", "student_user_id", "updated_at", "content_hash",
			}).
				AddRow(userID, syncDownloadItemKindSession, "s1", int64(55), int64(3012), updatedAt, "session-hash").
				AddRow(userID, syncDownloadItemKindProgressRow, "3012:55:1.1.1", int64(55), int64(3012), updatedAt, "progress-hash"),
		)

	app := buildSyncETagTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)

	status, body, _ := callAPI(
		t,
		app,
		http.MethodGet,
		"/api/sync/download-state1",
		token,
		"",
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d", status, http.StatusOK)
	}
	if !strings.Contains(body, `"state2":"state2-xyz"`) {
		t.Fatalf("missing state2 in body: %s", body)
	}
	if !strings.Contains(body, `"session_sync_id":"s1"`) {
		t.Fatalf("missing session item in body: %s", body)
	}
	if !strings.Contains(body, `"kp_key":"1.1.1"`) {
		t.Fatalf("missing progress row item in body: %s", body)
	}

	assertSQLMockExpectations(t, mock)
}

func TestDownloadFetchReturnsRequestedPayload(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(3011)
	updatedAt := time.Date(2026, 3, 8, 8, 2, 0, 0, time.UTC)

	sessionRows := sqlmock.NewRows([]string{
		"id",
		"session_sync_id",
		"course_id",
		"teacher_user_id",
		"student_user_id",
		"sender_user_id",
		"chapter_key",
		"updated_at",
		"envelope",
		"envelope_hash",
		"content_hash",
	}).AddRow(
		int64(11),
		"s1",
		int64(44),
		int64(901),
		userID,
		userID,
		"1.1",
		updatedAt,
		[]byte("session_payload"),
		"session-hash",
		"session-content-hash",
	)
	mock.ExpectQuery(`SELECT id, session_sync_id, course_id, teacher_user_id, student_user_id, sender_user_id, chapter_key, updated_at, envelope, envelope_hash, content_hash`).
		WithArgs(userID, userID, "s1").
		WillReturnRows(sessionRows)

	progressRows := sqlmock.NewRows([]string{
		"id",
		"course_id",
		"subject",
		"teacher_user_id",
		"student_user_id",
		"kp_key",
		"lit",
		"lit_percent",
		"question_level",
		"summary_text",
		"summary_raw_response",
		"summary_valid",
		"updated_at",
		"envelope",
		"envelope_hash",
		"content_hash",
	}).AddRow(
		int64(33),
		int64(55),
		"Biology",
		int64(901),
		userID,
		"1.1.1",
		true,
		88,
		"medium",
		"summary",
		"raw",
		true,
		updatedAt,
		[]byte("progress_payload"),
		"progress-hash",
		"progress-content-hash",
	)
	mock.ExpectQuery(`SELECT p.id, p.course_id, c.subject, p.teacher_user_id, p.student_user_id, p.kp_key, p.lit, p.lit_percent`).
		WithArgs(userID, userID, userID, int64(55), "1.1.1").
		WillReturnRows(progressRows)

	app := buildSyncETagTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)

	status, body, _ := callAPI(
		t,
		app,
		http.MethodPost,
		"/api/sync/download-fetch",
		token,
		`{"session_sync_ids":["s1"],"progress_chunks":[],"progress_rows":[{"student_user_id":3011,"course_id":55,"kp_key":"1.1.1"}]}`,
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d body=%s", status, http.StatusOK, body)
	}
	if !strings.Contains(body, `"session_sync_id":"s1"`) {
		t.Fatalf("missing session payload in response body: %s", body)
	}
	if !strings.Contains(body, `"kp_key":"1.1.1"`) {
		t.Fatalf("missing progress row payload in response body: %s", body)
	}

	assertSQLMockExpectations(t, mock)
}

func buildSyncETagTestApp(db *sql.DB, jwtSecrets []string) *fiber.App {
	deps := Dependencies{
		Config: config.Config{
			JWTVerifySecrets: jwtSecrets,
		},
		Store: &storepkg.Store{DB: db},
	}
	enrollments := NewEnrollmentHandler(deps)
	teacherCourses := NewTeacherCoursesHandler(deps)
	sessionSync := NewSessionSyncHandler(deps)
	progressSync := NewProgressSyncHandler(deps)
	syncDownload := NewSyncDownloadHandler(deps)

	app := fiber.New()
	app.Get("/api/enrollments", enrollments.ListEnrollments)
	app.Get("/api/enrollments/sync-state1", enrollments.GetEnrollmentsSyncState1)
	app.Get("/api/enrollments/sync-state2", enrollments.GetEnrollmentsSyncState2)
	app.Get("/api/teacher/courses", teacherCourses.ListCourses)
	app.Get("/api/teacher/courses/sync-state1", teacherCourses.GetCoursesSyncState1)
	app.Get("/api/teacher/courses/sync-state2", teacherCourses.GetCoursesSyncState2)
	app.Get("/api/sessions/sync/list", sessionSync.List)
	app.Get("/api/progress/sync/list", progressSync.List)
	app.Get("/api/progress/sync/chunks/list", progressSync.ListChunks)
	app.Get("/api/sync/download-state2", syncDownload.State2)
	app.Get("/api/sync/download-state1", syncDownload.State1)
	app.Get("/api/sync/download-manifest", syncDownload.Manifest)
	app.Post("/api/sync/download-fetch", syncDownload.Fetch)
	return app
}

func callAPIWithExtraHeaders(
	t *testing.T,
	app *fiber.App,
	method string,
	url string,
	token string,
	body string,
	extraHeaders map[string]string,
) (int, string, http.Header) {
	t.Helper()
	var bodyReader io.Reader
	if strings.TrimSpace(body) != "" {
		bodyReader = bytes.NewBufferString(body)
	}
	req := httptest.NewRequest(method, url, bodyReader)
	if strings.TrimSpace(token) != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	if strings.TrimSpace(body) != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	for key, value := range extraHeaders {
		req.Header.Set(key, value)
	}
	resp, err := app.Test(req)
	if err != nil {
		t.Fatalf("app.Test() error = %v", err)
	}
	defer resp.Body.Close()
	responseBody, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("ReadAll() error = %v", err)
	}
	return resp.StatusCode, strings.TrimSpace(string(responseBody)), resp.Header.Clone()
}
