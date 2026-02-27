package handlers

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	"family_teacher_remote/internal/config"
	storepkg "family_teacher_remote/internal/db"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gofiber/fiber/v2"
)

func TestEnsureBundleReturns404ForStaleCourseIDWithoutCourseName(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(1601)
	teacherID := int64(2601)
	staleCourseID := int64(9999)

	mock.ExpectQuery(`SELECT id FROM teacher_accounts WHERE user_id = \? AND status = 'active' LIMIT 1`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(teacherID))
	mock.ExpectQuery(`SELECT 1\s+FROM courses\s+WHERE id = \? AND teacher_id = \?\s+LIMIT 1`).
		WithArgs(staleCourseID, teacherID).
		WillReturnRows(sqlmock.NewRows([]string{"found"}))

	app := buildEnsureBundleTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)
	status, body, _ := callAPI(
		t,
		app,
		http.MethodPost,
		"/api/teacher/courses/9999/bundles",
		token,
		"",
	)
	if status != http.StatusNotFound {
		t.Fatalf("status = %d, want %d (body=%q)", status, http.StatusNotFound, body)
	}
	if !strings.Contains(strings.ToLower(body), "course not found") {
		t.Fatalf("body = %q, want contains %q", body, "course not found")
	}
	assertSQLMockExpectations(t, mock)
}

func TestEnsureBundleFallsBackByCourseNameAndReturnsResolvedCourseID(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(1602)
	teacherID := int64(2602)
	staleCourseID := int64(10001)
	resolvedCourseID := int64(321)
	existingBundleID := int64(444)
	mock.ExpectQuery(`SELECT id FROM teacher_accounts WHERE user_id = \? AND status = 'active' LIMIT 1`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(teacherID))
	mock.ExpectQuery(`SELECT 1\s+FROM courses\s+WHERE id = \? AND teacher_id = \?\s+LIMIT 1`).
		WithArgs(staleCourseID, teacherID).
		WillReturnRows(sqlmock.NewRows([]string{"found"}))

	mock.ExpectBegin()
	mock.ExpectQuery(`SELECT id\s+FROM courses\s+WHERE teacher_id = \? AND course_name_key = \?\s+ORDER BY id DESC\s+LIMIT 1`).
		WithArgs(teacherID, "algebra").
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(resolvedCourseID))
	mock.ExpectQuery(`SELECT id\s+FROM course_catalog_entries\s+WHERE course_id = \? AND teacher_id = \?\s+LIMIT 1`).
		WithArgs(resolvedCourseID, teacherID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(int64(1)))
	mock.ExpectCommit()

	mock.ExpectQuery(`SELECT id FROM bundles WHERE course_id = \? AND teacher_id = \? LIMIT 1`).
		WithArgs(resolvedCourseID, teacherID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(existingBundleID))

	app := buildEnsureBundleTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)
	status, body, _ := callAPI(
		t,
		app,
		http.MethodPost,
		"/api/teacher/courses/10001/bundles?course_name=Algebra",
		token,
		"",
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d (body=%q)", status, http.StatusOK, body)
	}

	var decoded map[string]interface{}
	if err := json.Unmarshal([]byte(body), &decoded); err != nil {
		t.Fatalf("json.Unmarshal() error = %v (body=%q)", err, body)
	}
	if got := int64(decoded["bundle_id"].(float64)); got != existingBundleID {
		t.Fatalf("bundle_id = %d, want %d", got, existingBundleID)
	}
	if got := int64(decoded["course_id"].(float64)); got != resolvedCourseID {
		t.Fatalf("course_id = %d, want %d", got, resolvedCourseID)
	}
	if got := decoded["status"].(string); got != "existing" {
		t.Fatalf("status = %q, want %q", got, "existing")
	}
	assertSQLMockExpectations(t, mock)
}

func buildEnsureBundleTestApp(db *sql.DB, jwtSecrets []string) *fiber.App {
	deps := Dependencies{
		Config: config.Config{
			JWTVerifySecrets: jwtSecrets,
		},
		Store: &storepkg.Store{DB: db},
	}
	teacherCourses := NewTeacherCoursesHandler(deps)
	app := fiber.New()
	app.Post("/api/teacher/courses/:id/bundles", teacherCourses.EnsureBundle)
	return app
}
