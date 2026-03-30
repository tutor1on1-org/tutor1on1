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
	)
	mock.ExpectQuery(`SELECT id, session_sync_id, course_id, teacher_user_id, student_user_id, sender_user_id, chapter_key, updated_at, envelope, envelope_hash`).
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
	)
	mock.ExpectQuery(`SELECT id, session_sync_id, course_id, teacher_user_id, student_user_id, sender_user_id, chapter_key, updated_at, envelope, envelope_hash`).
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
	)
	mock.ExpectQuery(`SELECT p.id, p.course_id, c.subject, p.teacher_user_id, p.student_user_id, p.chapter_key, p.item_count, p.updated_at, p.envelope, p.envelope_hash`).
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
	)
	mock.ExpectQuery(`SELECT p.id, p.course_id, c.subject, p.teacher_user_id, p.student_user_id, p.chapter_key, p.item_count, p.updated_at, p.envelope, p.envelope_hash`).
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
	)
	mock.ExpectQuery(`SELECT id, session_sync_id, course_id, teacher_user_id, student_user_id, sender_user_id, chapter_key, updated_at, envelope, envelope_hash`).
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
	)
	mock.ExpectQuery(`SELECT p.id, p.course_id, c.subject, p.teacher_user_id, p.student_user_id, p.chapter_key, p.item_count, p.updated_at, p.envelope, p.envelope_hash`).
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
	assignedAt := time.Date(2026, 3, 10, 12, 0, 0, 0, time.UTC)
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
		"bundle-hash-5",
		nil,
	)
	mock.ExpectQuery(`SELECT e.id, e.course_id, t.user_id, e.status, e.assigned_at`).
		WithArgs(userID).
		WillReturnRows(rows)

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
	if !strings.Contains(body, `"`+"state2"+`":"`+expected+`"`) {
		t.Fatalf("unexpected state2 response body: %s", body)
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
		"bundle-hash-2",
		nil,
	)
	mock.ExpectQuery(`SELECT c.id, c.subject, c.grade, c.description,\s*ce.visibility, ce.approval_status, ce.published_at`).
		WithArgs(teacherID, teacherID).
		WillReturnRows(rows)
	mock.ExpectQuery(`SELECT sl.id, sl.slug, sl.name, sl.is_active\s+FROM course_subject_labels csl`).
		WithArgs(int64(88)).
		WillReturnRows(sqlmock.NewRows([]string{"id", "slug", "name", "is_active"}))

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
	expected := buildState2([]string{
		buildTeacherCourseStateFingerprint(teacherCourseSummary{
			CourseID:              88,
			Subject:               "Chemistry",
			LatestBundleVersionID: 2,
			LatestBundleHash:      "bundle-hash-2",
		}),
	})
	if !strings.Contains(body, `"`+"state2"+`":"`+expected+`"`) {
		t.Fatalf("unexpected state2 response body: %s", body)
	}

	assertSQLMockExpectations(t, mock)
}

func TestDownloadManifestReturnsNotModifiedWhenETagMatches(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(3010)
	updatedAt := time.Date(2026, 3, 8, 8, 0, 0, 0, time.UTC)
	rows := sqlmock.NewRows([]string{
		"session_sync_id",
		"updated_at",
		"envelope_hash",
		"envelope",
	}).AddRow(
		"s1",
		updatedAt,
		"session-hash",
		[]byte("session_payload"),
	)
	mock.ExpectQuery(`SELECT session_sync_id, updated_at, envelope_hash, envelope`).
		WithArgs(userID, userID).
		WillReturnRows(rows)
	rows2 := sqlmock.NewRows([]string{
		"session_sync_id",
		"updated_at",
		"envelope_hash",
		"envelope",
	}).AddRow(
		"s1",
		updatedAt,
		"session-hash",
		[]byte("session_payload"),
	)
	mock.ExpectQuery(`SELECT session_sync_id, updated_at, envelope_hash, envelope`).
		WithArgs(userID, userID).
		WillReturnRows(rows2)

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
	)
	mock.ExpectQuery(`SELECT id, session_sync_id, course_id, teacher_user_id, student_user_id, sender_user_id, chapter_key, updated_at, envelope, envelope_hash`).
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
	app.Get("/api/enrollments/sync-state2", enrollments.GetEnrollmentsSyncState2)
	app.Get("/api/teacher/courses", teacherCourses.ListCourses)
	app.Get("/api/teacher/courses/sync-state2", teacherCourses.GetCoursesSyncState2)
	app.Get("/api/sessions/sync/list", sessionSync.List)
	app.Get("/api/progress/sync/list", progressSync.List)
	app.Get("/api/progress/sync/chunks/list", progressSync.ListChunks)
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
