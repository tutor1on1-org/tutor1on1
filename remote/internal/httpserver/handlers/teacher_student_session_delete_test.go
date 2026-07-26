package handlers

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"io"
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

const (
	teacherSessionDeleteTeacherUserID    = int64(901)
	teacherSessionDeleteTeacherAccountID = int64(81)
	teacherSessionDeleteStudentUserID    = int64(3001)
	teacherSessionDeleteCourseID         = int64(200)
	teacherSessionDeleteEnrollmentID     = int64(7001)
	teacherSessionDeleteArtifactID       = "student_kp:3001:200:1.1"
	teacherSessionDeleteKpKey            = "1.1"
	teacherSessionDeleteStorageRelPath   = "student_kp/3001/200/1.1.zip"
)

func TestDeleteStudentSessionAsTeacherRewritesArtifactAndResetsProgress(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()
	storageSvc := newTeacherSessionDeleteStorage(t)

	payload := teacherSessionDeletePayload([]interface{}{
		teacherSessionDeleteSession("delete-me", "remove-session"),
		teacherSessionDeleteSession("keep-me", "preserve-session"),
	})
	payload["progress"] = map[string]interface{}{
		"lit":           true,
		"lit_percent":   float64(120),
		"mastery_level": float64(4),
	}
	payload["mistakes"] = []interface{}{
		map[string]interface{}{
			"mistake_tag":     "sign error",
			"mistake_tag_key": "sign error",
			"evidence_json":   `{"source":"review"}`,
			"occurrences":     float64(3),
			"future_field":    "preserve-mistake",
		},
	}
	payload["future_top_level_payload"] = map[string]interface{}{
		"mode": "preserve-top-level",
	}
	baseSHA := writeTeacherSessionDeleteArtifact(t, storageSvc, payload)

	expectTeacherSessionDeleteAuthorization(
		mock,
		teacherSessionDeleteTeacherUserID,
		teacherSessionDeleteTeacherAccountID,
	)
	mock.ExpectBegin()
	expectTeacherSessionDeleteEnrollmentLock(mock, "active")
	expectTeacherSessionDeleteArtifactLookup(mock, baseSHA)
	mock.ExpectExec(`(?s)UPDATE student_kp_artifacts\s+SET teacher_user_id = \?,\s+storage_rel_path = \?,\s+sha256 = \?,\s+last_modified = \?\s+WHERE artifact_id = \? AND student_user_id = \? AND sha256 = \?`).
		WithArgs(
			teacherSessionDeleteTeacherUserID,
			sqlmock.AnyArg(),
			sqlmock.AnyArg(),
			sqlmock.AnyArg(),
			teacherSessionDeleteArtifactID,
			teacherSessionDeleteStudentUserID,
			baseSHA,
		).
		WillReturnResult(sqlmock.NewResult(1, 1))
	expectedState2 := expectStudentKpVisibilityMutation(
		mock,
		false,
		"state-sha-after-session-delete",
	)
	mock.ExpectCommit()

	response := performTeacherSessionDeleteRequest(
		t,
		buildTeacherSessionDeleteTestApp(db, storageSvc),
		teacherSessionDeleteTeacherUserID,
		"delete-me",
		baseSHA,
	)
	if response.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(response.Body)
		_ = response.Body.Close()
		t.Fatalf("status = %d, want %d (body=%q)", response.StatusCode, http.StatusOK, string(body))
	}
	defer response.Body.Close()

	var responsePayload map[string]interface{}
	if err := json.NewDecoder(response.Body).Decode(&responsePayload); err != nil {
		t.Fatalf("response json error = %v", err)
	}
	if got := responsePayload["status"]; got != "session_deleted" {
		t.Fatalf("status = %v, want session_deleted", got)
	}
	if got := responsePayload["artifact_deleted"]; got != false {
		t.Fatalf("artifact_deleted = %v, want false", got)
	}
	nextSHA, _ := responsePayload["sha256"].(string)
	if nextSHA == "" || nextSHA == baseSHA {
		t.Fatalf("sha256 = %q, want a new non-empty hash", nextSHA)
	}
	if got := responsePayload["state2"]; got != expectedState2 {
		t.Fatalf("state2 = %v", got)
	}

	rewrittenRelPath, err := artifactsync.StudentKpVersionedStorageRelPath(
		teacherSessionDeleteStudentUserID,
		teacherSessionDeleteCourseID,
		teacherSessionDeleteKpKey,
		nextSHA,
	)
	if err != nil {
		t.Fatalf("StudentKpVersionedStorageRelPath error = %v", err)
	}
	rewrittenBytes, err := os.ReadFile(storageSvc.AbsolutePath(rewrittenRelPath))
	if err != nil {
		t.Fatalf("ReadFile rewritten artifact error = %v", err)
	}
	rewritten, readSHA, err := artifactsync.ReadStudentKpArtifactPayloadMap(rewrittenBytes)
	if err != nil {
		t.Fatalf("ReadStudentKpArtifactPayloadMap error = %v", err)
	}
	if readSHA != nextSHA {
		t.Fatalf("rewritten sha256 = %q, want %q", readSHA, nextSHA)
	}
	if _, exists := rewritten["progress"]; exists {
		t.Fatal("progress remained after teacher session deletion")
	}
	sessions, ok := rewritten["sessions"].([]interface{})
	if !ok || len(sessions) != 1 {
		t.Fatalf("sessions = %#v, want one remaining session", rewritten["sessions"])
	}
	remainingSession, ok := sessions[0].(map[string]interface{})
	if !ok || remainingSession["session_sync_id"] != "keep-me" {
		t.Fatalf("remaining session = %#v, want keep-me", sessions[0])
	}
	if got := remainingSession["future_session_field"]; got != "preserve-session" {
		t.Fatalf("future_session_field = %v, want preserve-session", got)
	}
	mistakes, ok := rewritten["mistakes"].([]interface{})
	if !ok || len(mistakes) != 1 {
		t.Fatalf("mistakes = %#v, want one preserved mistake", rewritten["mistakes"])
	}
	mistake, ok := mistakes[0].(map[string]interface{})
	if !ok || mistake["future_field"] != "preserve-mistake" {
		t.Fatalf("preserved mistake = %#v", mistakes[0])
	}
	future, ok := rewritten["future_top_level_payload"].(map[string]interface{})
	if !ok || future["mode"] != "preserve-top-level" {
		t.Fatalf("future top-level payload = %#v", rewritten["future_top_level_payload"])
	}
	assertSQLMockExpectations(t, mock)
}

func TestDeleteStudentSessionAsTeacherDeletesEmptyArtifact(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()
	storageSvc := newTeacherSessionDeleteStorage(t)

	payload := teacherSessionDeletePayload([]interface{}{
		teacherSessionDeleteSession("delete-me", ""),
	})
	payload["progress"] = map[string]interface{}{"lit": true}
	baseSHA := writeTeacherSessionDeleteArtifact(t, storageSvc, payload)

	expectTeacherSessionDeleteAuthorization(
		mock,
		teacherSessionDeleteTeacherUserID,
		teacherSessionDeleteTeacherAccountID,
	)
	mock.ExpectBegin()
	expectTeacherSessionDeleteEnrollmentLock(mock, "active")
	expectTeacherSessionDeleteArtifactLookup(mock, baseSHA)
	mock.ExpectExec(`(?s)DELETE FROM student_kp_artifacts\s+WHERE artifact_id = \? AND student_user_id = \? AND sha256 = \?`).
		WithArgs(
			teacherSessionDeleteArtifactID,
			teacherSessionDeleteStudentUserID,
			baseSHA,
		).
		WillReturnResult(sqlmock.NewResult(0, 1))
	expectStudentKpVisibilityMutation(mock, true, "")
	mock.ExpectCommit()

	response := performTeacherSessionDeleteRequest(
		t,
		buildTeacherSessionDeleteTestApp(db, storageSvc),
		teacherSessionDeleteTeacherUserID,
		"delete-me",
		baseSHA,
	)
	if response.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(response.Body)
		_ = response.Body.Close()
		t.Fatalf("status = %d, want %d (body=%q)", response.StatusCode, http.StatusOK, string(body))
	}
	defer response.Body.Close()

	var responsePayload map[string]interface{}
	if err := json.NewDecoder(response.Body).Decode(&responsePayload); err != nil {
		t.Fatalf("response json error = %v", err)
	}
	if got := responsePayload["artifact_deleted"]; got != true {
		t.Fatalf("artifact_deleted = %v, want true", got)
	}
	if got := responsePayload["sha256"]; got != "" {
		t.Fatalf("sha256 = %v, want empty", got)
	}
	if _, err := os.Stat(storageSvc.AbsolutePath(teacherSessionDeleteStorageRelPath)); err != nil {
		t.Fatalf("retained artifact file missing after logical delete: %v", err)
	}
	assertSQLMockExpectations(t, mock)
}

func TestDeleteStudentSessionAsTeacherPreservesUnknownTopLevelDataOnLastSession(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()
	storageSvc := newTeacherSessionDeleteStorage(t)

	payload := teacherSessionDeletePayload([]interface{}{
		teacherSessionDeleteSession("delete-me", ""),
	})
	payload["progress"] = map[string]interface{}{"lit": true}
	payload["future_top_level_payload"] = map[string]interface{}{
		"large_integer": json.Number("9007199254740993"),
	}
	baseSHA := writeTeacherSessionDeleteArtifact(t, storageSvc, payload)

	expectTeacherSessionDeleteAuthorization(
		mock,
		teacherSessionDeleteTeacherUserID,
		teacherSessionDeleteTeacherAccountID,
	)
	mock.ExpectBegin()
	expectTeacherSessionDeleteEnrollmentLock(mock, "active")
	expectTeacherSessionDeleteArtifactLookup(mock, baseSHA)
	mock.ExpectExec(`(?s)UPDATE student_kp_artifacts\s+SET teacher_user_id = \?,\s+storage_rel_path = \?,\s+sha256 = \?,\s+last_modified = \?\s+WHERE artifact_id = \? AND student_user_id = \? AND sha256 = \?`).
		WithArgs(
			teacherSessionDeleteTeacherUserID,
			sqlmock.AnyArg(),
			sqlmock.AnyArg(),
			sqlmock.AnyArg(),
			teacherSessionDeleteArtifactID,
			teacherSessionDeleteStudentUserID,
			baseSHA,
		).
		WillReturnResult(sqlmock.NewResult(1, 1))
	expectStudentKpVisibilityMutation(mock, false, "state-sha-after-last-session")
	mock.ExpectCommit()

	response := performTeacherSessionDeleteRequest(
		t,
		buildTeacherSessionDeleteTestApp(db, storageSvc),
		teacherSessionDeleteTeacherUserID,
		"delete-me",
		baseSHA,
	)
	if response.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(response.Body)
		_ = response.Body.Close()
		t.Fatalf("status = %d, want %d (body=%q)", response.StatusCode, http.StatusOK, string(body))
	}
	defer response.Body.Close()
	var responsePayload map[string]interface{}
	if err := json.NewDecoder(response.Body).Decode(&responsePayload); err != nil {
		t.Fatalf("response json error = %v", err)
	}
	if got := responsePayload["artifact_deleted"]; got != false {
		t.Fatalf("artifact_deleted = %v, want false", got)
	}
	nextSHA, _ := responsePayload["sha256"].(string)
	rewrittenRelPath, err := artifactsync.StudentKpVersionedStorageRelPath(
		teacherSessionDeleteStudentUserID,
		teacherSessionDeleteCourseID,
		teacherSessionDeleteKpKey,
		nextSHA,
	)
	if err != nil {
		t.Fatalf("StudentKpVersionedStorageRelPath error = %v", err)
	}
	rewrittenBytes, err := os.ReadFile(storageSvc.AbsolutePath(rewrittenRelPath))
	if err != nil {
		t.Fatalf("ReadFile rewritten artifact error = %v", err)
	}
	rewritten, _, err := artifactsync.ReadStudentKpArtifactPayloadMap(rewrittenBytes)
	if err != nil {
		t.Fatalf("ReadStudentKpArtifactPayloadMap error = %v", err)
	}
	if _, exists := rewritten["progress"]; exists {
		t.Fatal("progress remained after last-session deletion")
	}
	if sessions, ok := rewritten["sessions"].([]interface{}); !ok || len(sessions) != 0 {
		t.Fatalf("sessions = %#v, want empty list", rewritten["sessions"])
	}
	future, ok := rewritten["future_top_level_payload"].(map[string]interface{})
	if !ok || future["large_integer"] != json.Number("9007199254740993") {
		t.Fatalf("future top-level payload = %#v", rewritten["future_top_level_payload"])
	}
	assertSQLMockExpectations(t, mock)
}

func TestDeleteStudentSessionAsTeacherIsIdempotentAfterCommittedResponseLoss(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()
	storageSvc := newTeacherSessionDeleteStorage(t)
	payload := teacherSessionDeletePayload([]interface{}{
		teacherSessionDeleteSession("keep-me", ""),
	})
	currentSHA := writeTeacherSessionDeleteArtifact(t, storageSvc, payload)

	expectTeacherSessionDeleteAuthorization(
		mock,
		teacherSessionDeleteTeacherUserID,
		teacherSessionDeleteTeacherAccountID,
	)
	mock.ExpectBegin()
	expectTeacherSessionDeleteEnrollmentLock(mock, "active")
	expectTeacherSessionDeleteArtifactLookup(mock, currentSHA)
	mock.ExpectRollback()
	expectedState2 := artifactsync.BuildState2([]artifactsync.State2Item{
		{
			ArtifactID: teacherSessionDeleteArtifactID,
			SHA256:     currentSHA,
		},
	})
	mock.ExpectQuery(`(?s)SELECT state2\s+FROM artifact_state2\s+WHERE user_id = \?`).
		WithArgs(teacherSessionDeleteTeacherUserID).
		WillReturnRows(sqlmock.NewRows([]string{"state2"}).AddRow(expectedState2))

	response := performTeacherSessionDeleteRequest(
		t,
		buildTeacherSessionDeleteTestApp(db, storageSvc),
		teacherSessionDeleteTeacherUserID,
		"delete-me",
		"stale-base-from-lost-response",
	)
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(response.Body)
		t.Fatalf("status = %d, want %d (body=%q)", response.StatusCode, http.StatusOK, string(body))
	}
	var responsePayload map[string]interface{}
	if err := json.NewDecoder(response.Body).Decode(&responsePayload); err != nil {
		t.Fatalf("response json error = %v", err)
	}
	if got := responsePayload["status"]; got != "session_already_deleted" {
		t.Fatalf("status = %v, want session_already_deleted", got)
	}
	if got := responsePayload["sha256"]; got != currentSHA {
		t.Fatalf("sha256 = %v, want %s", got, currentSHA)
	}
	assertSQLMockExpectations(t, mock)
}

func TestDeleteStudentSessionAsTeacherIsIdempotentAfterArtifactDeletion(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()
	storageSvc := newTeacherSessionDeleteStorage(t)

	expectTeacherSessionDeleteAuthorization(
		mock,
		teacherSessionDeleteTeacherUserID,
		teacherSessionDeleteTeacherAccountID,
	)
	mock.ExpectBegin()
	expectTeacherSessionDeleteEnrollmentLock(mock, "active")
	mock.ExpectQuery(`(?s)SELECT sha256, storage_rel_path\s+FROM student_kp_artifacts\s+WHERE artifact_id = \?\s+LIMIT 1`).
		WithArgs(teacherSessionDeleteArtifactID).
		WillReturnError(sql.ErrNoRows)
	mock.ExpectRollback()
	expectedState2 := artifactsync.BuildState2(nil)
	mock.ExpectQuery(`(?s)SELECT state2\s+FROM artifact_state2\s+WHERE user_id = \?`).
		WithArgs(teacherSessionDeleteTeacherUserID).
		WillReturnRows(sqlmock.NewRows([]string{"state2"}).AddRow(expectedState2))

	response := performTeacherSessionDeleteRequest(
		t,
		buildTeacherSessionDeleteTestApp(db, storageSvc),
		teacherSessionDeleteTeacherUserID,
		"delete-me",
		"stale-base-from-lost-response",
	)
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(response.Body)
		t.Fatalf("status = %d, want %d (body=%q)", response.StatusCode, http.StatusOK, string(body))
	}
	var responsePayload map[string]interface{}
	if err := json.NewDecoder(response.Body).Decode(&responsePayload); err != nil {
		t.Fatalf("response json error = %v", err)
	}
	if got := responsePayload["status"]; got != "session_already_deleted" {
		t.Fatalf("status = %v, want session_already_deleted", got)
	}
	if got := responsePayload["artifact_deleted"]; got != true {
		t.Fatalf("artifact_deleted = %v, want true", got)
	}
	assertSQLMockExpectations(t, mock)
}

func TestDeleteStudentSessionAsTeacherRejectsUnauthorizedCallers(t *testing.T) {
	tests := []struct {
		name         string
		expectAccess func(sqlmock.Sqlmock)
	}{
		{
			name: "inactive or non-teacher account",
			expectAccess: func(mock sqlmock.Sqlmock) {
				mock.ExpectQuery(`SELECT id FROM teacher_accounts WHERE user_id = \? AND status = 'active' LIMIT 1`).
					WithArgs(teacherSessionDeleteTeacherUserID).
					WillReturnError(sql.ErrNoRows)
			},
		},
		{
			name: "teacher does not own course",
			expectAccess: func(mock sqlmock.Sqlmock) {
				mock.ExpectQuery(`SELECT id FROM teacher_accounts WHERE user_id = \? AND status = 'active' LIMIT 1`).
					WithArgs(teacherSessionDeleteTeacherUserID).
					WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(teacherSessionDeleteTeacherAccountID))
				mock.ExpectQuery(`(?s)SELECT 1\s+FROM courses\s+WHERE id = \? AND teacher_id = \?\s+LIMIT 1`).
					WithArgs(teacherSessionDeleteCourseID, teacherSessionDeleteTeacherAccountID).
					WillReturnError(sql.ErrNoRows)
			},
		},
		{
			name: "student is not actively enrolled",
			expectAccess: func(mock sqlmock.Sqlmock) {
				mock.ExpectQuery(`SELECT id FROM teacher_accounts WHERE user_id = \? AND status = 'active' LIMIT 1`).
					WithArgs(teacherSessionDeleteTeacherUserID).
					WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(teacherSessionDeleteTeacherAccountID))
				mock.ExpectQuery(`(?s)SELECT 1\s+FROM courses\s+WHERE id = \? AND teacher_id = \?\s+LIMIT 1`).
					WithArgs(teacherSessionDeleteCourseID, teacherSessionDeleteTeacherAccountID).
					WillReturnRows(sqlmock.NewRows([]string{"found"}).AddRow(1))
				mock.ExpectQuery(`(?s)SELECT id\s+FROM enrollments\s+WHERE student_id = \? AND course_id = \? AND status = 'active'\s+LIMIT 1`).
					WithArgs(teacherSessionDeleteStudentUserID, teacherSessionDeleteCourseID).
					WillReturnError(sql.ErrNoRows)
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			db, mock := newHandlerSQLMock(t)
			defer db.Close()
			storageSvc := newTeacherSessionDeleteStorage(t)
			original := []byte("must remain unchanged")
			if _, _, err := storageSvc.SaveRelativePath(
				teacherSessionDeleteStorageRelPath,
				bytes.NewReader(original),
			); err != nil {
				t.Fatalf("SaveRelativePath error = %v", err)
			}
			test.expectAccess(mock)

			response := performTeacherSessionDeleteRequest(
				t,
				buildTeacherSessionDeleteTestApp(db, storageSvc),
				teacherSessionDeleteTeacherUserID,
				"delete-me",
				"base-sha",
			)
			defer response.Body.Close()
			if response.StatusCode != http.StatusForbidden {
				body, _ := io.ReadAll(response.Body)
				t.Fatalf("status = %d, want %d (body=%q)", response.StatusCode, http.StatusForbidden, string(body))
			}
			after, err := os.ReadFile(storageSvc.AbsolutePath(teacherSessionDeleteStorageRelPath))
			if err != nil {
				t.Fatalf("ReadFile unchanged artifact error = %v", err)
			}
			if !bytes.Equal(after, original) {
				t.Fatalf("unauthorized request mutated artifact: got %q", string(after))
			}
			assertSQLMockExpectations(t, mock)
		})
	}
}

func TestDeleteStudentSessionAsTeacherRejectsStaleBaseWithoutMutation(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()
	storageSvc := newTeacherSessionDeleteStorage(t)
	payload := teacherSessionDeletePayload([]interface{}{
		teacherSessionDeleteSession("delete-me", ""),
	})
	currentSHA := writeTeacherSessionDeleteArtifact(t, storageSvc, payload)
	before, err := os.ReadFile(storageSvc.AbsolutePath(teacherSessionDeleteStorageRelPath))
	if err != nil {
		t.Fatalf("ReadFile original artifact error = %v", err)
	}

	expectTeacherSessionDeleteAuthorization(
		mock,
		teacherSessionDeleteTeacherUserID,
		teacherSessionDeleteTeacherAccountID,
	)
	mock.ExpectBegin()
	expectTeacherSessionDeleteEnrollmentLock(mock, "active")
	expectTeacherSessionDeleteArtifactLookup(mock, currentSHA)
	mock.ExpectRollback()

	response := performTeacherSessionDeleteRequest(
		t,
		buildTeacherSessionDeleteTestApp(db, storageSvc),
		teacherSessionDeleteTeacherUserID,
		"delete-me",
		"stale-base-sha",
	)
	defer response.Body.Close()
	if response.StatusCode != http.StatusConflict {
		body, _ := io.ReadAll(response.Body)
		t.Fatalf("status = %d, want %d (body=%q)", response.StatusCode, http.StatusConflict, string(body))
	}
	var responsePayload map[string]interface{}
	if err := json.NewDecoder(response.Body).Decode(&responsePayload); err != nil {
		t.Fatalf("response json error = %v", err)
	}
	if got := responsePayload["conflict_type"]; got != "server_changed" {
		t.Fatalf("conflict_type = %v, want server_changed", got)
	}
	after, err := os.ReadFile(storageSvc.AbsolutePath(teacherSessionDeleteStorageRelPath))
	if err != nil {
		t.Fatalf("ReadFile unchanged artifact error = %v", err)
	}
	if !bytes.Equal(after, before) {
		t.Fatal("stale-base request mutated artifact bytes")
	}
	assertSQLMockExpectations(t, mock)
}

func newTeacherSessionDeleteStorage(t *testing.T) *storage.Service {
	t.Helper()
	storageSvc, err := storage.New(storage.Config{
		Root:           t.TempDir(),
		BundleMaxBytes: 1 << 20,
	})
	if err != nil {
		t.Fatalf("storage.New() error = %v", err)
	}
	return storageSvc
}

func teacherSessionDeletePayload(sessions []interface{}) map[string]interface{} {
	return map[string]interface{}{
		"schema":                 artifactsync.StudentKpArtifactSchema,
		"course_id":              float64(teacherSessionDeleteCourseID),
		"course_subject":         "UK_MATH_7-13",
		"kp_key":                 teacherSessionDeleteKpKey,
		"teacher_remote_user_id": float64(teacherSessionDeleteTeacherUserID),
		"student_remote_user_id": float64(teacherSessionDeleteStudentUserID),
		"student_username":       "albert",
		"updated_at":             "2026-07-26T10:47:04Z",
		"sessions":               sessions,
	}
}

func teacherSessionDeleteSession(sessionSyncID string, futureField string) map[string]interface{} {
	session := map[string]interface{}{
		"session_sync_id":        sessionSyncID,
		"course_id":              float64(teacherSessionDeleteCourseID),
		"kp_key":                 teacherSessionDeleteKpKey,
		"started_at":             "2026-07-26T10:00:00Z",
		"student_remote_user_id": float64(teacherSessionDeleteStudentUserID),
		"teacher_remote_user_id": float64(teacherSessionDeleteTeacherUserID),
		"updated_at":             "2026-07-26T10:47:04Z",
		"messages": []interface{}{
			map[string]interface{}{
				"role":         "assistant",
				"content":      "  preserve surrounding whitespace  ",
				"parsed_json":  `{"finished":true}`,
				"created_at":   "2026-07-26T10:47:04Z",
				"future_field": "preserve-message",
			},
		},
	}
	if futureField != "" {
		session["future_session_field"] = futureField
	}
	return session
}

func writeTeacherSessionDeleteArtifact(
	t *testing.T,
	storageSvc *storage.Service,
	payload map[string]interface{},
) string {
	t.Helper()
	zipBytes, builtSHA, err := artifactsync.BuildStudentKpArtifactZipFromMap(payload)
	if err != nil {
		t.Fatalf("BuildStudentKpArtifactZipFromMap error = %v", err)
	}
	if _, storedSHA, err := storageSvc.SaveRelativePath(
		teacherSessionDeleteStorageRelPath,
		bytes.NewReader(zipBytes),
	); err != nil {
		t.Fatalf("SaveRelativePath error = %v", err)
	} else if storedSHA != builtSHA {
		t.Fatalf("stored sha256 = %q, want %q", storedSHA, builtSHA)
	}
	return builtSHA
}

func expectTeacherSessionDeleteAuthorization(
	mock sqlmock.Sqlmock,
	teacherUserID int64,
	teacherAccountID int64,
) {
	mock.ExpectQuery(`SELECT id FROM teacher_accounts WHERE user_id = \? AND status = 'active' LIMIT 1`).
		WithArgs(teacherUserID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(teacherAccountID))
	mock.ExpectQuery(`(?s)SELECT 1\s+FROM courses\s+WHERE id = \? AND teacher_id = \?\s+LIMIT 1`).
		WithArgs(teacherSessionDeleteCourseID, teacherAccountID).
		WillReturnRows(sqlmock.NewRows([]string{"found"}).AddRow(1))
	mock.ExpectQuery(`(?s)SELECT id\s+FROM enrollments\s+WHERE student_id = \? AND course_id = \? AND status = 'active'\s+LIMIT 1`).
		WithArgs(teacherSessionDeleteStudentUserID, teacherSessionDeleteCourseID).
		WillReturnRows(
			sqlmock.NewRows([]string{"id"}).
				AddRow(teacherSessionDeleteEnrollmentID),
		)
}

func expectTeacherSessionDeleteEnrollmentLock(
	mock sqlmock.Sqlmock,
	status string,
) {
	mock.ExpectQuery(`(?s)SELECT status\s+FROM enrollments\s+WHERE id = \? AND student_id = \? AND course_id = \?\s+LIMIT 1\s+FOR UPDATE`).
		WithArgs(
			teacherSessionDeleteEnrollmentID,
			teacherSessionDeleteStudentUserID,
			teacherSessionDeleteCourseID,
		).
		WillReturnRows(sqlmock.NewRows([]string{"status"}).AddRow(status))
}

func expectTeacherSessionDeleteArtifactLookup(mock sqlmock.Sqlmock, shaValue string) {
	mock.ExpectQuery(`(?s)SELECT sha256, storage_rel_path\s+FROM student_kp_artifacts\s+WHERE artifact_id = \?\s+LIMIT 1`).
		WithArgs(teacherSessionDeleteArtifactID).
		WillReturnRows(
			sqlmock.NewRows([]string{"sha256", "storage_rel_path"}).
				AddRow(shaValue, teacherSessionDeleteStorageRelPath),
		)
}

func expectStudentKpVisibilityMutation(
	mock sqlmock.Sqlmock,
	deleted bool,
	stateSHA string,
) string {
	stateItems := []artifactsync.State2Item{}
	if !deleted {
		stateItems = append(stateItems, artifactsync.State2Item{
			ArtifactID: teacherSessionDeleteArtifactID,
			SHA256:     stateSHA,
		})
	}
	expectedState2 := artifactsync.BuildState2(stateItems)
	userIDs := []int64{
		teacherSessionDeleteTeacherUserID,
		teacherSessionDeleteStudentUserID,
	}
	for _, userID := range userIDs {
		mock.ExpectQuery(`(?s)SELECT state2\s+FROM artifact_state2\s+WHERE user_id = \?\s+FOR UPDATE`).
			WithArgs(userID).
			WillReturnRows(sqlmock.NewRows([]string{"state2"}).AddRow("previous-state2"))
	}
	for _, userID := range userIDs {
		mock.ExpectExec(`(?s)DELETE FROM artifact_state1_items\s+WHERE user_id = \? AND artifact_id = \?`).
			WithArgs(userID, teacherSessionDeleteArtifactID).
			WillReturnResult(sqlmock.NewResult(0, 1))
		if !deleted {
			mock.ExpectExec(`(?s)INSERT INTO artifact_state1_items\s+\(user_id, artifact_id, artifact_class, course_id, teacher_user_id, student_user_id, kp_key, bundle_version_id, storage_rel_path, sha256, last_modified\)\s+VALUES \(\?, \?, 'student_kp', \?, \?, \?, \?, NULL, \?, \?, \?\)`).
				WithArgs(
					userID,
					teacherSessionDeleteArtifactID,
					teacherSessionDeleteCourseID,
					teacherSessionDeleteTeacherUserID,
					teacherSessionDeleteStudentUserID,
					teacherSessionDeleteKpKey,
					sqlmock.AnyArg(),
					sqlmock.AnyArg(),
					sqlmock.AnyArg(),
				).
				WillReturnResult(sqlmock.NewResult(1, 1))
		}
		stateRows := sqlmock.NewRows([]string{"artifact_id", "sha256"})
		if !deleted {
			stateRows.AddRow(teacherSessionDeleteArtifactID, stateSHA)
		}
		mock.ExpectQuery(`(?s)SELECT artifact_id, sha256\s+FROM artifact_state1_items\s+WHERE user_id = \?\s+ORDER BY artifact_id ASC`).
			WithArgs(userID).
			WillReturnRows(stateRows)
		mock.ExpectExec(`(?s)INSERT INTO artifact_state2 \(user_id, state2, updated_at\)\s+VALUES \(\?, \?, \?\)\s+ON DUPLICATE KEY UPDATE`).
			WithArgs(userID, expectedState2, sqlmock.AnyArg()).
			WillReturnResult(sqlmock.NewResult(1, 1))
	}
	return expectedState2
}

func buildTeacherSessionDeleteTestApp(
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
	app.Post(
		"/api/teacher/student-sessions/delete",
		artifactSync.DeleteStudentSessionAsTeacher,
	)
	return app
}

func performTeacherSessionDeleteRequest(
	t *testing.T,
	app *fiber.App,
	teacherUserID int64,
	sessionSyncID string,
	baseSHA string,
) *http.Response {
	t.Helper()
	body, err := json.Marshal(map[string]string{
		"artifact_id":     teacherSessionDeleteArtifactID,
		"session_sync_id": sessionSyncID,
		"base_sha256":     baseSHA,
	})
	if err != nil {
		t.Fatalf("json.Marshal request error = %v", err)
	}
	request := httptest.NewRequest(
		http.MethodPost,
		"/api/teacher/student-sessions/delete",
		bytes.NewReader(body),
	)
	request.Header.Set(
		"Authorization",
		"Bearer "+signTestJWT(t, "test-secret", teacherUserID, true),
	)
	request.Header.Set("Content-Type", "application/json")
	response, err := app.Test(request)
	if err != nil {
		t.Fatalf("app.Test() error = %v", err)
	}
	return response
}
