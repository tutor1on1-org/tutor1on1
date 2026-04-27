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
				"latest_bundle_hash",
				"latest_bundle_oss_path",
			}).AddRow(int64(501), "Algebra", nil, nil, "private", "pending", nil, nil, nil, nil),
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

func TestCreateCourseInitialApprovalStatusIsDraft(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(1704)
	teacherID := int64(2704)
	courseID := int64(604)
	labelID := int64(1)

	mock.ExpectQuery(`SELECT id FROM teacher_accounts WHERE user_id = \? AND status = 'active' LIMIT 1`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(teacherID))
	mock.ExpectQuery(`(?s)SELECT c.id, c.subject, c.grade, c.description,.*WHERE c.teacher_id = \? AND c.course_name_key = \?.*LIMIT 1`).
		WithArgs(teacherID, "draft math").
		WillReturnError(sql.ErrNoRows)
	mock.ExpectBegin()
	mock.ExpectExec(`INSERT INTO courses`).
		WithArgs(
			teacherID,
			"Draft Math",
			"draft math",
			sql.NullString{String: "Grade 5", Valid: true},
			sql.NullString{String: "Created from test", Valid: true},
		).
		WillReturnResult(sqlmock.NewResult(courseID, 1))
	mock.ExpectExec(`INSERT INTO course_catalog_entries .*'draft'`).
		WithArgs(courseID, teacherID).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectQuery(`SELECT id\s+FROM subject_labels\s+WHERE is_active = TRUE AND id IN \(\?\)`).
		WithArgs(labelID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(labelID))
	mock.ExpectExec(`DELETE FROM course_subject_labels WHERE course_id = \?`).
		WithArgs(courseID).
		WillReturnResult(sqlmock.NewResult(0, 0))
	mock.ExpectExec(`INSERT INTO course_subject_labels`).
		WithArgs(courseID, labelID).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()
	mock.ExpectQuery(`SELECT sl.id, sl.slug, sl.name, sl.is_active\s+FROM course_subject_labels csl`).
		WithArgs(courseID).
		WillReturnRows(
			sqlmock.NewRows([]string{"id", "slug", "name", "is_active"}).
				AddRow(labelID, "math", "Math", true),
		)

	app := buildTeacherContractTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)
	status, body, _ := callAPI(
		t,
		app,
		http.MethodPost,
		"/api/teacher/courses",
		token,
		`{"subject":"Draft Math","grade":"Grade 5","description":"Created from test","subject_label_ids":[1]}`,
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d (body=%q)", status, http.StatusOK, body)
	}

	var decoded map[string]interface{}
	if err := json.Unmarshal([]byte(body), &decoded); err != nil {
		t.Fatalf("json.Unmarshal() error = %v (body=%q)", err, body)
	}
	if got := decoded["approval_status"].(string); got != "draft" {
		t.Fatalf("approval_status = %q, want %q", got, "draft")
	}
	if got := decoded["status"].(string); got != "created" {
		t.Fatalf("status = %q, want %q", got, "created")
	}
	assertSQLMockExpectations(t, mock)
}

func TestUpdateCourseMetadataUpdatesDescription(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(1705)
	teacherID := int64(2705)
	courseID := int64(77)

	mock.ExpectQuery(`SELECT id FROM teacher_accounts WHERE user_id = \? AND status = 'active' LIMIT 1`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(teacherID))
	mock.ExpectExec(`UPDATE courses SET description = \? WHERE id = \? AND teacher_id = \?`).
		WithArgs(
			sql.NullString{String: "New marketplace description", Valid: true},
			courseID,
			teacherID,
		).
		WillReturnResult(sqlmock.NewResult(0, 1))

	app := buildTeacherContractTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)
	status, body, _ := callAPI(
		t,
		app,
		http.MethodPost,
		"/api/teacher/courses/77/metadata",
		token,
		`{"description":"  New marketplace description  "}`,
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d (body=%q)", status, http.StatusOK, body)
	}
	if !strings.Contains(body, `"description":"New marketplace description"`) {
		t.Fatalf("body = %q, want trimmed description", body)
	}
	if !strings.Contains(body, `"status":"updated"`) {
		t.Fatalf("body = %q, want updated status", body)
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
	mock.ExpectBegin()
	mock.ExpectExec(`(?s)DELETE cuv FROM course_upload_votes cuv.*WHERE cur.bundle_version_id = \?`).
		WithArgs(versionID).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec(`DELETE FROM course_upload_requests WHERE bundle_version_id = \?`).
		WithArgs(versionID).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec(`DELETE FROM artifact_state1_items WHERE bundle_version_id = \?`).
		WithArgs(versionID).
		WillReturnResult(sqlmock.NewResult(0, 2))
	mock.ExpectExec(`(?s)DELETE bv FROM bundle_versions bv.*WHERE bv.id = \? AND b.course_id = \? AND b.teacher_id = \?`).
		WithArgs(versionID, courseID, teacherID).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectQuery(`(?s)SELECT 1\s+FROM bundles b\s+JOIN bundle_versions bv ON bv.bundle_id = b.id\s+WHERE b.course_id = \? AND b.teacher_id = \?\s+LIMIT 1`).
		WithArgs(courseID, teacherID).
		WillReturnRows(sqlmock.NewRows([]string{"found"}))
	mock.ExpectExec(`(?s)UPDATE course_catalog_entries\s+SET visibility = 'private', published_at = NULL\s+WHERE course_id = \? AND teacher_id = \?`).
		WithArgs(courseID, teacherID).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

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

func TestDeleteCourseBundleReferencesTxDeletesModerationAndArtifactState(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	courseID := int64(707)

	mock.ExpectBegin()
	mock.ExpectExec(`(?s)DELETE cuv FROM course_upload_votes cuv.*WHERE cur.course_id = \?`).
		WithArgs(courseID).
		WillReturnResult(sqlmock.NewResult(0, 2))
	mock.ExpectExec(`DELETE FROM course_upload_requests WHERE course_id = \?`).
		WithArgs(courseID).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec(`DELETE FROM artifact_state1_items WHERE course_id = \?`).
		WithArgs(courseID).
		WillReturnResult(sqlmock.NewResult(0, 3))
	mock.ExpectCommit()

	tx, err := db.Begin()
	if err != nil {
		t.Fatalf("Begin() error = %v", err)
	}
	if err := deleteCourseBundleReferencesTx(tx, courseID); err != nil {
		t.Fatalf("deleteCourseBundleReferencesTx() error = %v", err)
	}
	if err := tx.Commit(); err != nil {
		t.Fatalf("Commit() error = %v", err)
	}
	assertSQLMockExpectations(t, mock)
}

func TestDeleteBundleVersionReferencesTxDeletesModerationAndArtifactState(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	bundleVersionID := int64(808)

	mock.ExpectBegin()
	mock.ExpectExec(`(?s)DELETE cuv FROM course_upload_votes cuv.*WHERE cur.bundle_version_id = \?`).
		WithArgs(bundleVersionID).
		WillReturnResult(sqlmock.NewResult(0, 2))
	mock.ExpectExec(`DELETE FROM course_upload_requests WHERE bundle_version_id = \?`).
		WithArgs(bundleVersionID).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec(`DELETE FROM artifact_state1_items WHERE bundle_version_id = \?`).
		WithArgs(bundleVersionID).
		WillReturnResult(sqlmock.NewResult(0, 3))
	mock.ExpectCommit()

	tx, err := db.Begin()
	if err != nil {
		t.Fatalf("Begin() error = %v", err)
	}
	if err := deleteBundleVersionReferencesTx(tx, bundleVersionID); err != nil {
		t.Fatalf("deleteBundleVersionReferencesTx() error = %v", err)
	}
	if err := tx.Commit(); err != nil {
		t.Fatalf("Commit() error = %v", err)
	}
	assertSQLMockExpectations(t, mock)
}

func TestDeleteCourseRecordReferencesTxDeletesRemainingCourseFKs(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	courseID := int64(909)

	mock.ExpectBegin()
	mock.ExpectExec(`DELETE FROM course_quit_requests WHERE course_id = \?`).
		WithArgs(courseID).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec(`DELETE FROM course_subject_labels WHERE course_id = \?`).
		WithArgs(courseID).
		WillReturnResult(sqlmock.NewResult(0, 2))
	mock.ExpectCommit()

	tx, err := db.Begin()
	if err != nil {
		t.Fatalf("Begin() error = %v", err)
	}
	if err := deleteCourseRecordReferencesTx(tx, courseID); err != nil {
		t.Fatalf("deleteCourseRecordReferencesTx() error = %v", err)
	}
	if err := tx.Commit(); err != nil {
		t.Fatalf("Commit() error = %v", err)
	}
	assertSQLMockExpectations(t, mock)
}

func TestGetLatestCourseBundleInfoReturnsHashForTeacher(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(1703)
	courseID := int64(88)

	mock.ExpectQuery(`(?s)SELECT bv.id, b.id, bv.version, bv.hash, bv.oss_path, b.teacher_id, ta.user_id.*WHERE c.id = \?.*LIMIT 1`).
		WithArgs(courseID).
		WillReturnRows(
			sqlmock.NewRows([]string{
				"id",
				"bundle_id",
				"version",
				"hash",
				"oss_path",
				"teacher_id",
				"user_id",
			}).AddRow(int64(501), int64(601), 3, "hash-123", "bundles/88/3.zip", int64(2703), userID),
		)

	app := buildTeacherContractTestApp(db, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)
	status, body, _ := callAPI(
		t,
		app,
		http.MethodGet,
		"/api/bundles/latest-info?course_id=88",
		token,
		"",
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d (body=%q)", status, http.StatusOK, body)
	}
	if !strings.Contains(body, `"hash":"hash-123"`) {
		t.Fatalf("body = %q, want hash payload", body)
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
	app.Post("/api/teacher/courses/:id/metadata", teacherCourses.UpdateCourseMetadata)
	app.Get("/api/bundles/latest-info", bundles.GetLatestCourseBundleInfo)
	app.Post(
		"/api/teacher/courses/:id/bundle-versions/:versionId/delete",
		bundles.DeleteTeacherCourseBundleVersion,
	)
	return app
}
