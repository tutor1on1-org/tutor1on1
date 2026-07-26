package handlers

import (
	"bytes"
	"encoding/json"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"testing"

	"family_teacher_remote/internal/artifactsync"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestStudentArtifactUploadRetryAcceptsAlreadyCommittedSHA(t *testing.T) {
	tests := []struct {
		name         string
		buildRequest func(*testing.T, []byte, string) *http.Request
	}{
		{
			name: "single upload",
			buildRequest: func(t *testing.T, zipBytes []byte, shaValue string) *http.Request {
				return buildStudentArtifactUploadRequest(
					t,
					zipBytes,
					shaValue,
					"stale-base-before-committed-upload",
				)
			},
		},
		{
			name: "batch upload",
			buildRequest: func(t *testing.T, zipBytes []byte, shaValue string) *http.Request {
				return buildStudentArtifactUploadBatchRequest(
					t,
					zipBytes,
					shaValue,
					"stale-base-before-committed-upload",
				)
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			db, mock := newHandlerSQLMock(t)
			defer db.Close()
			storageSvc := newTeacherSessionDeleteStorage(t)
			zipBytes, shaValue := buildStudentArtifactUploadBytes(t)
			relPath, err := artifactsync.StudentKpVersionedStorageRelPath(
				teacherSessionDeleteStudentUserID,
				teacherSessionDeleteCourseID,
				teacherSessionDeleteKpKey,
				shaValue,
			)
			if err != nil {
				t.Fatalf("StudentKpVersionedStorageRelPath() error = %v", err)
			}
			if _, storedSHA, err := storageSvc.SaveRelativePath(
				relPath,
				bytes.NewReader(zipBytes),
			); err != nil {
				t.Fatalf("SaveRelativePath() error = %v", err)
			} else if storedSHA != shaValue {
				t.Fatalf("stored sha256 = %q, want %q", storedSHA, shaValue)
			}

			expectIdempotentStudentArtifactUpload(
				mock,
				relPath,
				shaValue,
			)
			app := buildArtifactSyncUploadTestApp(db, storageSvc)
			request := test.buildRequest(t, zipBytes, shaValue)
			response, err := app.Test(request)
			if err != nil {
				t.Fatalf("app.Test() error = %v", err)
			}
			defer response.Body.Close()
			if response.StatusCode != http.StatusOK {
				body, _ := io.ReadAll(response.Body)
				t.Fatalf(
					"status = %d, want %d (body=%q)",
					response.StatusCode,
					http.StatusOK,
					string(body),
				)
			}
			assertSQLMockExpectations(t, mock)
		})
	}
}

func buildStudentArtifactUploadBytes(t *testing.T) ([]byte, string) {
	t.Helper()
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
	return zipBytes, shaValue
}

func expectIdempotentStudentArtifactUpload(
	mock sqlmock.Sqlmock,
	relPath string,
	shaValue string,
) {
	expectActiveEnrollmentLookup(mock)
	expectTeacherUserLookup(mock)
	mock.ExpectBegin()
	mock.ExpectQuery(`(?s)SELECT status\s+FROM enrollments\s+WHERE id = \? AND student_id = \? AND course_id = \?\s+LIMIT 1\s+FOR UPDATE`).
		WithArgs(
			teacherSessionDeleteEnrollmentID,
			teacherSessionDeleteStudentUserID,
			teacherSessionDeleteCourseID,
		).
		WillReturnRows(sqlmock.NewRows([]string{"status"}).AddRow("active"))
	mock.ExpectQuery(`(?s)SELECT sha256, storage_rel_path\s+FROM student_kp_artifacts\s+WHERE artifact_id = \?\s+LIMIT 1\s+FOR UPDATE`).
		WithArgs(teacherSessionDeleteArtifactID).
		WillReturnRows(
			sqlmock.NewRows([]string{"sha256", "storage_rel_path"}).
				AddRow(shaValue, relPath),
		)
	mock.ExpectExec(`(?s)INSERT INTO student_kp_artifacts\s+\(artifact_id, course_id, teacher_user_id, student_user_id, kp_key, storage_rel_path, sha256, last_modified\)\s+VALUES \(\?, \?, \?, \?, \?, \?, \?, \?\)\s+ON DUPLICATE KEY UPDATE`).
		WithArgs(
			teacherSessionDeleteArtifactID,
			teacherSessionDeleteCourseID,
			teacherSessionDeleteTeacherUserID,
			teacherSessionDeleteStudentUserID,
			teacherSessionDeleteKpKey,
			relPath,
			shaValue,
			sqlmock.AnyArg(),
		).
		WillReturnResult(sqlmock.NewResult(1, 1))
	expectStudentKpVisibilityMutation(mock, false, shaValue)
	mock.ExpectCommit()
}

func buildStudentArtifactUploadBatchRequest(
	t *testing.T,
	zipBytes []byte,
	shaValue string,
	baseSHA string,
) *http.Request {
	t.Helper()
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	manifest, err := json.Marshal(map[string]interface{}{
		"items": []map[string]interface{}{
			{
				"artifact_id":      teacherSessionDeleteArtifactID,
				"file_field":       "artifact_0",
				"base_sha256":      baseSHA,
				"sha256":           shaValue,
				"overwrite_server": false,
			},
		},
	})
	if err != nil {
		t.Fatalf("json.Marshal() error = %v", err)
	}
	if err := writer.WriteField("manifest", string(manifest)); err != nil {
		t.Fatalf("WriteField() error = %v", err)
	}
	part, err := writer.CreateFormFile("artifact_0", "student-kp.zip")
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
		"/api/artifacts/upload-batch",
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
