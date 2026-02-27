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
		"session_sync_id",
		"course_id",
		"teacher_user_id",
		"student_user_id",
		"sender_user_id",
		"updated_at",
		"envelope",
		"envelope_hash",
	}).AddRow(
		"s1",
		int64(44),
		int64(901),
		userID,
		userID,
		updatedAt,
		[]byte("session_payload"),
		"session_hash",
	)
	mock.ExpectQuery(`SELECT session_sync_id, course_id, teacher_user_id, student_user_id, sender_user_id, updated_at, envelope, envelope_hash`).
		WithArgs(userID, userID, sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnRows(rows)
	rows2 := sqlmock.NewRows([]string{
		"session_sync_id",
		"course_id",
		"teacher_user_id",
		"student_user_id",
		"sender_user_id",
		"updated_at",
		"envelope",
		"envelope_hash",
	}).AddRow(
		"s1",
		int64(44),
		int64(901),
		userID,
		userID,
		updatedAt,
		[]byte("session_payload"),
		"session_hash",
	)
	mock.ExpectQuery(`SELECT session_sync_id, course_id, teacher_user_id, student_user_id, sender_user_id, updated_at, envelope, envelope_hash`).
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
	mock.ExpectQuery(`SELECT p.course_id, c.subject, p.teacher_user_id, p.student_user_id, p.kp_key, p.lit, p.lit_percent`).
		WithArgs(userID, sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnRows(rows)
	rows2 := sqlmock.NewRows([]string{
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
	mock.ExpectQuery(`SELECT p.course_id, c.subject, p.teacher_user_id, p.student_user_id, p.kp_key, p.lit, p.lit_percent`).
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
	}).AddRow(
		int64(1),
		int64(66),
		int64(77),
		"active",
		assignedAt,
		"Physics",
		"Teacher A",
		int64(5),
	)
	mock.ExpectQuery(`SELECT e.id, e.course_id, e.teacher_id, e.status, e.assigned_at`).
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
	}).AddRow(
		int64(1),
		int64(66),
		int64(77),
		"active",
		assignedAt,
		"Physics",
		"Teacher A",
		int64(5),
	)
	mock.ExpectQuery(`SELECT e.id, e.course_id, e.teacher_id, e.status, e.assigned_at`).
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
		"published_at",
		"latest_bundle_version_id",
	}).AddRow(
		int64(88),
		"Chemistry",
		"Grade 5",
		"Desc",
		"private",
		nil,
		int64(2),
	)
	mock.ExpectQuery(`SELECT c.id, c.subject, c.grade, c.description`).
		WithArgs(teacherID, teacherID).
		WillReturnRows(rows)
	mock.ExpectQuery(`SELECT id FROM teacher_accounts WHERE user_id = \? AND status = 'active' LIMIT 1`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(teacherID))
	rows2 := sqlmock.NewRows([]string{
		"id",
		"subject",
		"grade",
		"description",
		"visibility",
		"published_at",
		"latest_bundle_version_id",
	}).AddRow(
		int64(88),
		"Chemistry",
		"Grade 5",
		"Desc",
		"private",
		nil,
		int64(2),
	)
	mock.ExpectQuery(`SELECT c.id, c.subject, c.grade, c.description`).
		WithArgs(teacherID, teacherID).
		WillReturnRows(rows2)

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

	app := fiber.New()
	app.Get("/api/enrollments", enrollments.ListEnrollments)
	app.Get("/api/teacher/courses", teacherCourses.ListCourses)
	app.Get("/api/sessions/sync/list", sessionSync.List)
	app.Get("/api/progress/sync/list", progressSync.List)
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
