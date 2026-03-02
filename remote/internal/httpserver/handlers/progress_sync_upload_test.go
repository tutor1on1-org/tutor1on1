package handlers

import (
	"encoding/base64"
	"testing"
	"time"

	storepkg "family_teacher_remote/internal/db"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestProgressSyncSaveUploadsSkipsStaleUpdateAndWritesAudit(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	handler := NewProgressSyncHandler(
		Dependencies{
			Store: &storepkg.Store{DB: db},
		},
	)

	userID := int64(11)
	courseID := int64(10)
	teacherUserID := int64(9)
	kpKey := "1.1.1.1"
	deviceID := "device-a"
	incomingUpdatedAtRaw := "2026-03-01T23:23:59Z"
	incomingUpdatedAt, err := time.Parse(time.RFC3339, incomingUpdatedAtRaw)
	if err != nil {
		t.Fatalf("time.Parse() error = %v", err)
	}
	existingUpdatedAt := time.Date(2026, 3, 2, 0, 0, 0, 0, time.UTC)

	mock.ExpectBegin()
	mock.ExpectPrepare(`SELECT lit_percent, question_level, updated_at FROM progress_sync`)
	mock.ExpectPrepare(`INSERT INTO progress_sync`)
	mock.ExpectPrepare(`UPDATE progress_sync`)
	mock.ExpectPrepare(`INSERT INTO progress_sync_audit`)
	mock.ExpectQuery(`SELECT ta.user_id`).
		WithArgs(courseID).
		WillReturnRows(sqlmock.NewRows([]string{"user_id"}).AddRow(teacherUserID))
	mock.ExpectQuery(`SELECT 1 FROM enrollments`).
		WithArgs(userID, courseID).
		WillReturnRows(sqlmock.NewRows([]string{"1"}).AddRow(1))
	mock.ExpectQuery(`SELECT lit_percent, question_level, updated_at FROM progress_sync`).
		WithArgs(courseID, userID, kpKey).
		WillReturnRows(
			sqlmock.NewRows([]string{"lit_percent", "question_level", "updated_at"}).
				AddRow(100, "hard", existingUpdatedAt),
		)
	mock.ExpectExec(`INSERT INTO progress_sync_audit`).
		WithArgs(
			courseID,
			userID,
			teacherUserID,
			kpKey,
			userID,
			deviceID,
			progressSyncAuditActionSkipStale,
			100,
			33,
			"hard",
			"easy",
			existingUpdatedAt,
			incomingUpdatedAt,
		).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	savedCount, err := handler.saveUploads(
		userID,
		deviceID,
		[]uploadProgressRequest{
			{
				CourseID:      courseID,
				KpKey:         kpKey,
				Lit:           false,
				LitPercent:    33,
				QuestionLevel: "easy",
				UpdatedAt:     incomingUpdatedAtRaw,
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

func TestProgressSyncSaveUploadsUpdatesWhenIncomingIsNewerAndWritesAudit(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	handler := NewProgressSyncHandler(
		Dependencies{
			Store: &storepkg.Store{DB: db},
		},
	)

	userID := int64(11)
	courseID := int64(10)
	teacherUserID := int64(9)
	kpKey := "1.1.1.1"
	deviceID := "device-b"
	incomingUpdatedAtRaw := "2026-03-02T00:10:00Z"
	incomingUpdatedAt, err := time.Parse(time.RFC3339, incomingUpdatedAtRaw)
	if err != nil {
		t.Fatalf("time.Parse() error = %v", err)
	}
	existingUpdatedAt := time.Date(2026, 3, 2, 0, 0, 0, 0, time.UTC)
	summaryValid := true
	envelopeBytes := []byte("payload-bytes")

	mock.ExpectBegin()
	mock.ExpectPrepare(`SELECT lit_percent, question_level, updated_at FROM progress_sync`)
	mock.ExpectPrepare(`INSERT INTO progress_sync`)
	mock.ExpectPrepare(`UPDATE progress_sync`)
	mock.ExpectPrepare(`INSERT INTO progress_sync_audit`)
	mock.ExpectQuery(`SELECT ta.user_id`).
		WithArgs(courseID).
		WillReturnRows(sqlmock.NewRows([]string{"user_id"}).AddRow(teacherUserID))
	mock.ExpectQuery(`SELECT 1 FROM enrollments`).
		WithArgs(userID, courseID).
		WillReturnRows(sqlmock.NewRows([]string{"1"}).AddRow(1))
	mock.ExpectQuery(`SELECT lit_percent, question_level, updated_at FROM progress_sync`).
		WithArgs(courseID, userID, kpKey).
		WillReturnRows(
			sqlmock.NewRows([]string{"lit_percent", "question_level", "updated_at"}).
				AddRow(33, "easy", existingUpdatedAt),
		)
	mock.ExpectExec(`UPDATE progress_sync`).
		WithArgs(
			teacherUserID,
			true,
			66,
			"medium",
			"updated summary",
			"updated raw",
			sqlmock.AnyArg(),
			incomingUpdatedAt,
			envelopeBytes,
			"hash-1",
			courseID,
			userID,
			kpKey,
		).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec(`INSERT INTO progress_sync_audit`).
		WithArgs(
			courseID,
			userID,
			teacherUserID,
			kpKey,
			userID,
			deviceID,
			progressSyncAuditActionUpdate,
			33,
			66,
			"easy",
			"medium",
			existingUpdatedAt,
			incomingUpdatedAt,
		).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	savedCount, err := handler.saveUploads(
		userID,
		deviceID,
		[]uploadProgressRequest{
			{
				CourseID:           courseID,
				KpKey:              kpKey,
				Lit:                true,
				LitPercent:         66,
				QuestionLevel:      "medium",
				SummaryText:        "updated summary",
				SummaryRawResponse: "updated raw",
				SummaryValid:       &summaryValid,
				UpdatedAt:          incomingUpdatedAtRaw,
				Envelope:           base64.StdEncoding.EncodeToString(envelopeBytes),
				EnvelopeHash:       "hash-1",
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
