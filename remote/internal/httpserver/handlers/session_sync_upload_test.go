package handlers

import (
	"database/sql"
	"encoding/base64"
	"testing"
	"time"

	storepkg "family_teacher_remote/internal/db"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestSessionSyncSaveUploadsSkipsStaleUpdate(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	handler := NewSessionSyncHandler(
		Dependencies{
			Store: &storepkg.Store{DB: db},
		},
	)

	userID := int64(21)
	courseID := int64(31)
	teacherUserID := int64(41)
	studentUserID := userID
	sessionSyncID := "session-stale"
	existingUpdatedAt := time.Date(2026, 3, 10, 8, 0, 0, 0, time.UTC)

	mock.ExpectBegin()
	mock.ExpectPrepare(`SELECT updated_at FROM session_text_sync`)
	mock.ExpectPrepare(`INSERT INTO session_text_sync`)
	mock.ExpectPrepare(`UPDATE session_text_sync`)
	mock.ExpectQuery(`SELECT ta.user_id`).
		WithArgs(courseID).
		WillReturnRows(sqlmock.NewRows([]string{"user_id"}).AddRow(teacherUserID))
	mock.ExpectQuery(`SELECT 1 FROM enrollments`).
		WithArgs(userID, courseID).
		WillReturnRows(sqlmock.NewRows([]string{"1"}).AddRow(1))
	mock.ExpectQuery(`SELECT updated_at FROM session_text_sync`).
		WithArgs(sessionSyncID).
		WillReturnRows(
			sqlmock.NewRows([]string{"updated_at"}).
				AddRow(existingUpdatedAt),
		)
	mock.ExpectCommit()

	savedCount, err := handler.saveUploads(
		userID,
		[]uploadSessionRequest{
			{
				SessionSyncID: sessionSyncID,
				CourseID:      courseID,
				StudentUserID: studentUserID,
				ChapterKey:    "1.1",
				UpdatedAt:     "2026-03-10T07:59:00Z",
				Envelope:      base64.StdEncoding.EncodeToString([]byte("stale")),
				EnvelopeHash:  "hash-stale",
				ContentHash:   "content-hash-stale",
			},
		},
	)
	if err != nil {
		t.Fatalf("saveUploads() error = %v", err)
	}
	if savedCount != 0 {
		t.Fatalf("savedCount = %d, want 0", savedCount)
	}

	assertSQLMockExpectations(t, mock)
}

func TestSessionSyncSaveUploadsUpdatesWhenIncomingIsNewer(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	handler := NewSessionSyncHandler(
		Dependencies{
			Store: &storepkg.Store{DB: db},
		},
	)

	userID := int64(22)
	courseID := int64(32)
	teacherUserID := int64(42)
	studentUserID := userID
	sessionSyncID := "session-newer"
	existingUpdatedAt := time.Date(2026, 3, 10, 8, 0, 0, 0, time.UTC)
	incomingUpdatedAt := time.Date(2026, 3, 10, 8, 1, 0, 0, time.UTC)
	envelopeBytes := []byte("newer-payload")

	mock.ExpectBegin()
	mock.ExpectPrepare(`SELECT updated_at FROM session_text_sync`)
	mock.ExpectPrepare(`INSERT INTO session_text_sync`)
	mock.ExpectPrepare(`UPDATE session_text_sync`)
	mock.ExpectQuery(`SELECT ta.user_id`).
		WithArgs(courseID).
		WillReturnRows(sqlmock.NewRows([]string{"user_id"}).AddRow(teacherUserID))
	mock.ExpectQuery(`SELECT 1 FROM enrollments`).
		WithArgs(userID, courseID).
		WillReturnRows(sqlmock.NewRows([]string{"1"}).AddRow(1))
	mock.ExpectQuery(`SELECT updated_at FROM session_text_sync`).
		WithArgs(sessionSyncID).
		WillReturnRows(
			sqlmock.NewRows([]string{"updated_at"}).
				AddRow(existingUpdatedAt),
		)
	mock.ExpectExec(`UPDATE session_text_sync`).
		WithArgs(
			courseID,
			teacherUserID,
			studentUserID,
			userID,
			"1.1",
			"1.1",
			incomingUpdatedAt,
			len(envelopeBytes),
			envelopeBytes,
			"hash-newer",
			"content-hash-newer",
			sessionSyncID,
		).
		WillReturnResult(sqlmock.NewResult(0, 1))
	emptyState2 := encodeSyncDownloadState2(syncDownloadState2Aggregate{})
	mock.ExpectExec(`DELETE FROM sync_download_state_items`).
		WithArgs(teacherUserID, syncDownloadItemKindProgressChunk).
		WillReturnResult(sqlmock.NewResult(0, 0))
	mock.ExpectQuery(`SELECT state2\s+FROM sync_download_state2`).
		WithArgs(teacherUserID).
		WillReturnRows(sqlmock.NewRows([]string{"state2"}).AddRow(emptyState2))
	mock.ExpectQuery(`SELECT user_id, item_kind, scope_key, course_id, student_user_id, updated_at, content_hash FROM sync_download_state_items`).
		WithArgs(teacherUserID, syncDownloadItemKindSession, sessionSyncID).
		WillReturnError(sql.ErrNoRows)
	mock.ExpectExec(`INSERT INTO sync_download_state_items`).
		WithArgs(
			teacherUserID,
			syncDownloadItemKindSession,
			sessionSyncID,
			courseID,
			studentUserID,
			incomingUpdatedAt,
			"content-hash-newer",
		).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec(`DELETE FROM sync_download_state_items`).
		WithArgs(studentUserID, syncDownloadItemKindProgressChunk).
		WillReturnResult(sqlmock.NewResult(0, 0))
	mock.ExpectQuery(`SELECT state2\s+FROM sync_download_state2`).
		WithArgs(studentUserID).
		WillReturnRows(sqlmock.NewRows([]string{"state2"}).AddRow(emptyState2))
	mock.ExpectQuery(`SELECT user_id, item_kind, scope_key, course_id, student_user_id, updated_at, content_hash FROM sync_download_state_items`).
		WithArgs(studentUserID, syncDownloadItemKindSession, sessionSyncID).
		WillReturnError(sql.ErrNoRows)
	mock.ExpectExec(`INSERT INTO sync_download_state_items`).
		WithArgs(
			studentUserID,
			syncDownloadItemKindSession,
			sessionSyncID,
			courseID,
			studentUserID,
			incomingUpdatedAt,
			"content-hash-newer",
		).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec(`INSERT INTO sync_download_state2`).
		WithArgs(teacherUserID, sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec(`INSERT INTO sync_download_state2`).
		WithArgs(studentUserID, sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	savedCount, err := handler.saveUploads(
		userID,
		[]uploadSessionRequest{
			{
				SessionSyncID: sessionSyncID,
				CourseID:      courseID,
				StudentUserID: studentUserID,
				ChapterKey:    "1.1",
				UpdatedAt:     incomingUpdatedAt.Format(time.RFC3339),
				Envelope:      base64.StdEncoding.EncodeToString(envelopeBytes),
				EnvelopeHash:  "hash-newer",
				ContentHash:   "content-hash-newer",
			},
		},
	)
	if err != nil {
		t.Fatalf("saveUploads() error = %v", err)
	}
	if savedCount != 1 {
		t.Fatalf("savedCount = %d, want 1", savedCount)
	}

	assertSQLMockExpectations(t, mock)
}
