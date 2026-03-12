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

func TestCreateCourseReturnsExistingForNormalizedTeacherCourseKey(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(1701)
	teacherID := int64(2701)

	mock.ExpectQuery(`SELECT id FROM teacher_accounts WHERE user_id = \? AND status = 'active' LIMIT 1`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(teacherID))
	mock.ExpectQuery(`(?s)SELECT c.id, c.subject, c.grade, c.description,.*WHERE c.teacher_id = \? AND c.course_name_key = \?.*LIMIT 1`).
		WithArgs(teacherID, "algebra").
		WillReturnRows(
			sqlmock.NewRows([]string{
				"id",
				"subject",
				"grade",
				"description",
				"visibility",
				"approval_status",
				"published_at",
				"latest_bundle_version_id",
			}).AddRow(int64(501), "Algebra", nil, nil, "private", "pending", nil, nil),
		)
	mock.ExpectQuery(`SELECT sl.id, sl.slug, sl.name, sl.is_active\s+FROM course_subject_labels csl`).
		WithArgs(int64(501)).
		WillReturnRows(sqlmock.NewRows([]string{"id", "slug", "name", "is_active"}))

	app := buildTeacherContractTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)
	status, body, _ := callAPI(
		t,
		app,
		http.MethodPost,
		"/api/teacher/courses",
		token,
		`{"subject":"  Algebra  ","grade":"","description":""}`,
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d (body=%q)", status, http.StatusOK, body)
	}

	var decoded map[string]interface{}
	if err := json.Unmarshal([]byte(body), &decoded); err != nil {
		t.Fatalf("json.Unmarshal() error = %v (body=%q)", err, body)
	}
	if got := int64(decoded["course_id"].(float64)); got != 501 {
		t.Fatalf("course_id = %d, want %d", got, 501)
	}
	if got := decoded["status"].(string); got != "existing" {
		t.Fatalf("status = %q, want %q", got, "existing")
	}
	assertSQLMockExpectations(t, mock)
}

func TestDeleteLastBundleVersionAutoUnpublishesCourse(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(1702)
	teacherID := int64(2702)
	courseID := int64(77)
	versionID := int64(55)

	mock.ExpectQuery(`SELECT id FROM teacher_accounts WHERE user_id = \? AND status = 'active' LIMIT 1`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(teacherID))
	mock.ExpectQuery(`(?s)SELECT bv.oss_path.*WHERE bv.id = \? AND b.course_id = \? AND b.teacher_id = \?`).
		WithArgs(versionID, courseID, teacherID).
		WillReturnRows(sqlmock.NewRows([]string{"oss_path"}).AddRow("bundles/77/1.zip"))
	mock.ExpectExec(`(?s)DELETE bv FROM bundle_versions bv.*WHERE bv.id = \? AND b.course_id = \? AND b.teacher_id = \?`).
		WithArgs(versionID, courseID, teacherID).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectQuery(`(?s)SELECT 1\s+FROM bundles b\s+JOIN bundle_versions bv ON bv.bundle_id = b.id\s+WHERE b.course_id = \? AND b.teacher_id = \?\s+LIMIT 1`).
		WithArgs(courseID, teacherID).
		WillReturnRows(sqlmock.NewRows([]string{"found"}))
	mock.ExpectExec(`(?s)UPDATE course_catalog_entries\s+SET visibility = 'private', published_at = NULL\s+WHERE course_id = \? AND teacher_id = \?`).
		WithArgs(courseID, teacherID).
		WillReturnResult(sqlmock.NewResult(0, 1))

	app := buildTeacherContractTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)
	status, body, _ := callAPI(
		t,
		app,
		http.MethodPost,
		"/api/teacher/courses/77/bundle-versions/55/delete",
		token,
		"",
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d (body=%q)", status, http.StatusOK, body)
	}
	if !strings.Contains(body, `"status":"deleted"`) {
		t.Fatalf("body = %q, want contains %q", body, `"status":"deleted"`)
	}
	assertSQLMockExpectations(t, mock)
}

func buildTeacherContractTestApp(db *sql.DB, jwtSecrets []string) *fiber.App {
	deps := Dependencies{
		Config: config.Config{
			JWTVerifySecrets: jwtSecrets,
		},
		Store: &storepkg.Store{DB: db},
	}
	teacherCourses := NewTeacherCoursesHandler(deps)
	bundles := NewBundlesHandler(deps)

	app := fiber.New()
	app.Post("/api/teacher/courses", teacherCourses.CreateCourse)
	app.Post(
		"/api/teacher/courses/:id/bundle-versions/:versionId/delete",
		bundles.DeleteTeacherCourseBundleVersion,
	)
	return app
}
