package handlers

import (
	"bytes"
	"database/sql"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"family_teacher_remote/internal/config"
	storepkg "family_teacher_remote/internal/db"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gofiber/fiber/v2"
)

func TestCreateEnrollmentRequestRejectsTeacherAccount(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(901)
	mock.ExpectQuery(`SELECT id FROM teacher_accounts WHERE user_id = \? AND status = 'active' LIMIT 1`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(int64(7001)))

	app := buildEnrollmentBundleTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)
	status, _, _ := callAPI(
		t,
		app,
		http.MethodPost,
		"/api/enrollment-requests",
		token,
		`{"course_id":123,"message":"please approve"}`,
	)
	if status != http.StatusForbidden {
		t.Fatalf("status = %d, want %d", status, http.StatusForbidden)
	}
	assertSQLMockExpectations(t, mock)
}

func TestCreateEnrollmentRequestRejectsPrivateCourse(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(902)
	courseID := int64(88)
	mock.ExpectQuery(`SELECT id FROM teacher_accounts WHERE user_id = \? AND status = 'active' LIMIT 1`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}))
	mock.ExpectQuery(`SELECT c.teacher_id, ce.visibility`).
		WithArgs(courseID).
		WillReturnRows(
			sqlmock.NewRows([]string{"teacher_id", "visibility"}).
				AddRow(int64(77), "private"),
		)

	app := buildEnrollmentBundleTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)
	status, _, _ := callAPI(
		t,
		app,
		http.MethodPost,
		"/api/enrollment-requests",
		token,
		`{"course_id":88,"message":"join"}`,
	)
	if status != http.StatusForbidden {
		t.Fatalf("status = %d, want %d", status, http.StatusForbidden)
	}
	assertSQLMockExpectations(t, mock)
}

func TestCreateEnrollmentRequestRejectsAlreadyEnrolledStudent(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(903)
	courseID := int64(89)
	teacherID := int64(778)
	mock.ExpectQuery(`SELECT id FROM teacher_accounts WHERE user_id = \? AND status = 'active' LIMIT 1`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}))
	mock.ExpectQuery(`SELECT c.teacher_id, ce.visibility`).
		WithArgs(courseID).
		WillReturnRows(
			sqlmock.NewRows([]string{"teacher_id", "visibility"}).
				AddRow(teacherID, "public"),
		)
	mock.ExpectQuery(`SELECT 1 FROM enrollments`).
		WithArgs(userID, courseID, teacherID).
		WillReturnRows(sqlmock.NewRows([]string{"ok"}).AddRow(1))

	app := buildEnrollmentBundleTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)
	status, _, _ := callAPI(
		t,
		app,
		http.MethodPost,
		"/api/enrollment-requests",
		token,
		`{"course_id":89}`,
	)
	if status != http.StatusConflict {
		t.Fatalf("status = %d, want %d", status, http.StatusConflict)
	}
	assertSQLMockExpectations(t, mock)
}

func TestDownloadBundleRejectsNonEnrolledStudent(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(1201)
	bundleVersionID := int64(44)
	courseID := int64(501)
	teacherID := int64(42)
	teacherUserID := int64(1500)
	mock.ExpectQuery(`SELECT bv.oss_path, bv.version, b.id, b.course_id, b.teacher_id, ta.user_id`).
		WithArgs(bundleVersionID).
		WillReturnRows(
			sqlmock.NewRows([]string{
				"oss_path", "version", "bundle_id", "course_id", "teacher_id", "teacher_user_id",
			}).AddRow("bundles/9/2.zip", 2, int64(9), courseID, teacherID, teacherUserID),
		)
	mock.ExpectQuery(`SELECT 1 FROM enrollments`).
		WithArgs(userID, courseID, teacherID).
		WillReturnRows(sqlmock.NewRows([]string{"ok"}))

	app := buildEnrollmentBundleTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)
	status, _, _ := callAPI(
		t,
		app,
		http.MethodGet,
		"/api/bundles/download?bundle_version_id=44",
		token,
		"",
	)
	if status != http.StatusForbidden {
		t.Fatalf("status = %d, want %d", status, http.StatusForbidden)
	}
	assertSQLMockExpectations(t, mock)
}

func TestDownloadBundleAllowsEnrolledStudent(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(1202)
	bundleVersionID := int64(45)
	courseID := int64(502)
	teacherID := int64(43)
	teacherUserID := int64(1501)
	mock.ExpectQuery(`SELECT bv.oss_path, bv.version, b.id, b.course_id, b.teacher_id, ta.user_id`).
		WithArgs(bundleVersionID).
		WillReturnRows(
			sqlmock.NewRows([]string{
				"oss_path", "version", "bundle_id", "course_id", "teacher_id", "teacher_user_id",
			}).AddRow("bundles/10/3.zip", 3, int64(10), courseID, teacherID, teacherUserID),
		)
	mock.ExpectQuery(`SELECT 1 FROM enrollments`).
		WithArgs(userID, courseID, teacherID).
		WillReturnRows(sqlmock.NewRows([]string{"ok"}).AddRow(1))

	app := buildEnrollmentBundleTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)
	status, _, headers := callAPI(
		t,
		app,
		http.MethodGet,
		"/api/bundles/download?bundle_version_id=45",
		token,
		"",
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d", status, http.StatusOK)
	}
	if headers.Get("X-Accel-Redirect") != "/_files/bundles/10/3.zip" {
		t.Fatalf("X-Accel-Redirect = %q, want %q", headers.Get("X-Accel-Redirect"), "/_files/bundles/10/3.zip")
	}
	if headers.Get("Content-Disposition") != `attachment; filename="bundle_10_v3.zip"` {
		t.Fatalf(
			"Content-Disposition = %q, want %q",
			headers.Get("Content-Disposition"),
			`attachment; filename="bundle_10_v3.zip"`,
		)
	}
	assertSQLMockExpectations(t, mock)
}

func TestDownloadBundleAllowsTeacherOwnerWithoutEnrollmentLookup(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	teacherUserID := int64(1502)
	bundleVersionID := int64(46)
	mock.ExpectQuery(`SELECT bv.oss_path, bv.version, b.id, b.course_id, b.teacher_id, ta.user_id`).
		WithArgs(bundleVersionID).
		WillReturnRows(
			sqlmock.NewRows([]string{
				"oss_path", "version", "bundle_id", "course_id", "teacher_id", "teacher_user_id",
			}).AddRow("bundles/11/1.zip", 1, int64(11), int64(503), int64(44), teacherUserID),
		)

	app := buildEnrollmentBundleTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", teacherUserID, true)
	status, _, headers := callAPI(
		t,
		app,
		http.MethodGet,
		"/api/bundles/download?bundle_version_id=46",
		token,
		"",
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d", status, http.StatusOK)
	}
	if headers.Get("X-Accel-Redirect") != "/_files/bundles/11/1.zip" {
		t.Fatalf("X-Accel-Redirect = %q, want %q", headers.Get("X-Accel-Redirect"), "/_files/bundles/11/1.zip")
	}
	assertSQLMockExpectations(t, mock)
}

func newHandlerSQLMock(t *testing.T) (*sql.DB, sqlmock.Sqlmock) {
	t.Helper()
	db, mock, err := sqlmock.New(sqlmock.QueryMatcherOption(sqlmock.QueryMatcherRegexp))
	if err != nil {
		t.Fatalf("sqlmock.New() error = %v", err)
	}
	return db, mock
}

func buildEnrollmentBundleTestApp(db *sql.DB, jwtSecrets []string) *fiber.App {
	deps := Dependencies{
		Config: config.Config{
			JWTVerifySecrets: jwtSecrets,
		},
		Store: &storepkg.Store{DB: db},
	}
	enrollments := NewEnrollmentHandler(deps)
	bundles := NewBundlesHandler(deps)

	app := fiber.New()
	app.Post("/api/enrollment-requests", enrollments.CreateRequest)
	app.Get("/api/bundles/download", bundles.Download)
	return app
}

func callAPI(
	t *testing.T,
	app *fiber.App,
	method string,
	url string,
	token string,
	body string,
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

func assertSQLMockExpectations(t *testing.T, mock sqlmock.Sqlmock) {
	t.Helper()
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("sql expectations not met: %v", err)
	}
}
