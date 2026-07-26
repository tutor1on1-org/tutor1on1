package handlers

import (
	"bytes"
	"database/sql"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"family_teacher_remote/internal/artifactsync"
	"family_teacher_remote/internal/config"
	storepkg "family_teacher_remote/internal/db"
	"family_teacher_remote/internal/storage"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gofiber/fiber/v2"
)

func TestStudentArtifactMutationsRejectEnrollmentRevokedBeforeTransactionLock(t *testing.T) {
	t.Run("student delete", func(t *testing.T) {
		db, mock := newHandlerSQLMock(t)
		defer db.Close()
		storageSvc := newTeacherSessionDeleteStorage(t)

		expectActiveEnrollmentLookup(mock)
		expectTeacherUserLookup(mock)
		mock.ExpectBegin()
		expectRevokedEnrollmentLock(mock)
		mock.ExpectRollback()

		app := buildArtifactSyncDeleteTestApp(
			db,
			storageSvc,
			[]string{"test-secret"},
		)
		request := httptest.NewRequest(
			http.MethodPost,
			"/api/artifacts/delete",
			bytes.NewBufferString(
				`{"artifact_id":"`+teacherSessionDeleteArtifactID+`","base_sha256":"server-sha","overwrite_server":true}`,
			),
		)
		request.Header.Set(
			"Authorization",
			"Bearer "+signTestJWT(
				t,
				"test-secret",
				teacherSessionDeleteStudentUserID,
				true,
			),
		)
		request.Header.Set("Content-Type", "application/json")
		response, err := app.Test(request)
		if err != nil {
			t.Fatalf("app.Test() error = %v", err)
		}
		defer response.Body.Close()
		assertForbiddenResponse(t, response)
		assertSQLMockExpectations(t, mock)
	})

	t.Run("teacher session delete", func(t *testing.T) {
		db, mock := newHandlerSQLMock(t)
		defer db.Close()
		storageSvc := newTeacherSessionDeleteStorage(t)

		expectTeacherSessionDeleteAuthorization(
			mock,
			teacherSessionDeleteTeacherUserID,
			teacherSessionDeleteTeacherAccountID,
		)
		mock.ExpectBegin()
		expectTeacherSessionDeleteEnrollmentLock(mock, "deleted")
		mock.ExpectRollback()

		response := performTeacherSessionDeleteRequest(
			t,
			buildTeacherSessionDeleteTestApp(db, storageSvc),
			teacherSessionDeleteTeacherUserID,
			"delete-me",
			"server-sha",
		)
		defer response.Body.Close()
		assertForbiddenResponse(t, response)
		assertSQLMockExpectations(t, mock)
	})

	t.Run("student upload", func(t *testing.T) {
		db, mock := newHandlerSQLMock(t)
		defer db.Close()
		storageSvc := newTeacherSessionDeleteStorage(t)
		zipBytes, shaValue, err := artifactsync.BuildStudentKpArtifactZipFromMap(
			map[string]interface{}{
				"schema":                 artifactsync.StudentKpArtifactSchema,
				"course_id":              teacherSessionDeleteCourseID,
				"course_subject":         "UK_MATH_7-13",
				"kp_key":                 teacherSessionDeleteKpKey,
				"teacher_remote_user_id": teacherSessionDeleteTeacherUserID,
				"student_remote_user_id": teacherSessionDeleteStudentUserID,
				"updated_at":             "2026-07-26T10:47:04Z",
				"sessions":               []interface{}{},
			},
		)
		if err != nil {
			t.Fatalf("BuildStudentKpArtifactZipFromMap() error = %v", err)
		}

		expectActiveEnrollmentLookup(mock)
		expectTeacherUserLookup(mock)
		mock.ExpectBegin()
		expectRevokedEnrollmentLock(mock)
		mock.ExpectRollback()

		app := buildArtifactSyncUploadTestApp(db, storageSvc)
		request := buildStudentArtifactUploadRequest(t, zipBytes, shaValue, "")
		response, err := app.Test(request)
		if err != nil {
			t.Fatalf("app.Test() error = %v", err)
		}
		defer response.Body.Close()
		assertForbiddenResponse(t, response)
		relPath, err := artifactsync.StudentKpVersionedStorageRelPath(
			teacherSessionDeleteStudentUserID,
			teacherSessionDeleteCourseID,
			teacherSessionDeleteKpKey,
			shaValue,
		)
		if err != nil {
			t.Fatalf("StudentKpVersionedStorageRelPath() error = %v", err)
		}
		if _, err := os.Stat(storageSvc.AbsolutePath(relPath)); !os.IsNotExist(err) {
			t.Fatalf("revoked upload created artifact file: %v", err)
		}
		assertSQLMockExpectations(t, mock)
	})
}

func expectActiveEnrollmentLookup(mock sqlmock.Sqlmock) {
	mock.ExpectQuery(`(?s)SELECT id\s+FROM enrollments\s+WHERE student_id = \? AND course_id = \? AND status = 'active'\s+LIMIT 1`).
		WithArgs(
			teacherSessionDeleteStudentUserID,
			teacherSessionDeleteCourseID,
		).
		WillReturnRows(
			sqlmock.NewRows([]string{"id"}).
				AddRow(teacherSessionDeleteEnrollmentID),
		)
}

func expectTeacherUserLookup(mock sqlmock.Sqlmock) {
	mock.ExpectQuery(`(?s)SELECT ta.user_id\s+FROM courses c\s+JOIN teacher_accounts ta ON ta.id = c.teacher_id\s+WHERE c.id = \?\s+LIMIT 1`).
		WithArgs(teacherSessionDeleteCourseID).
		WillReturnRows(
			sqlmock.NewRows([]string{"user_id"}).
				AddRow(teacherSessionDeleteTeacherUserID),
		)
}

func expectRevokedEnrollmentLock(mock sqlmock.Sqlmock) {
	mock.ExpectQuery(`(?s)SELECT status\s+FROM enrollments\s+WHERE id = \? AND student_id = \? AND course_id = \?\s+LIMIT 1\s+FOR UPDATE`).
		WithArgs(
			teacherSessionDeleteEnrollmentID,
			teacherSessionDeleteStudentUserID,
			teacherSessionDeleteCourseID,
		).
		WillReturnRows(sqlmock.NewRows([]string{"status"}).AddRow("deleted"))
}

func buildArtifactSyncUploadTestApp(
	db *sql.DB,
	storageSvc *storage.Service,
) *fiber.App {
	deps := Dependencies{
		Config: config.Config{
			JWTVerifySecrets: []string{"test-secret"},
		},
		Store:   &storepkg.Store{DB: db},
		Storage: storageSvc,
	}
	artifactSync := NewArtifactSyncHandler(deps)
	app := fiber.New()
	app.Post("/api/artifacts/upload", artifactSync.Upload)
	app.Post("/api/artifacts/upload-batch", artifactSync.UploadBatch)
	return app
}

func buildStudentArtifactUploadRequest(
	t *testing.T,
	zipBytes []byte,
	shaValue string,
	baseSHA string,
) *http.Request {
	t.Helper()
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	fields := map[string]string{
		"artifact_id":   teacherSessionDeleteArtifactID,
		"base_sha256":   baseSHA,
		"sha256":        shaValue,
		"artifact_type": "student_kp",
	}
	for name, value := range fields {
		if err := writer.WriteField(name, value); err != nil {
			t.Fatalf("WriteField(%q) error = %v", name, err)
		}
	}
	part, err := writer.CreateFormFile("artifact", "student-kp.zip")
	if err != nil {
		t.Fatalf("CreateFormFile() error = %v", err)
	}
	if _, err := part.Write(zipBytes); err != nil {
		t.Fatalf("multipart artifact write error = %v", err)
	}
	if err := writer.Close(); err != nil {
		t.Fatalf("multipart writer close error = %v", err)
	}
	request := httptest.NewRequest(
		http.MethodPost,
		"/api/artifacts/upload",
		&body,
	)
	request.Header.Set(
		"Authorization",
		"Bearer "+signTestJWT(
			t,
			"test-secret",
			teacherSessionDeleteStudentUserID,
			true,
		),
	)
	request.Header.Set("Content-Type", writer.FormDataContentType())
	return request
}

func assertForbiddenResponse(t *testing.T, response *http.Response) {
	t.Helper()
	if response.StatusCode == http.StatusForbidden {
		return
	}
	body, _ := io.ReadAll(response.Body)
	t.Fatalf(
		"status = %d, want %d (body=%q)",
		response.StatusCode,
		http.StatusForbidden,
		string(body),
	)
}
