package handlers

import (
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
			sessionSyncID,
		).
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
