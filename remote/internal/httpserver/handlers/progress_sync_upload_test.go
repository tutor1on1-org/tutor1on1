package handlers

import (
	"database/sql"
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
			"content-hash-1",
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
	scopeKey := buildProgressRowStateScopeKey(userID, courseID, kpKey)
	emptyState2 := encodeSyncDownloadState2(syncDownloadState2Aggregate{})
	mock.ExpectExec(`DELETE FROM sync_download_state_items`).
		WithArgs(teacherUserID, syncDownloadItemKindProgressChunk).
		WillReturnResult(sqlmock.NewResult(0, 0))
	mock.ExpectQuery(`SELECT state2\s+FROM sync_download_state2`).
		WithArgs(teacherUserID).
		WillReturnRows(sqlmock.NewRows([]string{"state2"}).AddRow(emptyState2))
	mock.ExpectQuery(`SELECT user_id, item_kind, scope_key, course_id, student_user_id, updated_at, content_hash FROM sync_download_state_items`).
		WithArgs(teacherUserID, syncDownloadItemKindProgressRow, scopeKey).
		WillReturnError(sql.ErrNoRows)
	mock.ExpectExec(`INSERT INTO sync_download_state_items`).
		WithArgs(
			teacherUserID,
			syncDownloadItemKindProgressRow,
			scopeKey,
			courseID,
			userID,
			incomingUpdatedAt,
			"content-hash-1",
		).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec(`DELETE FROM sync_download_state_items`).
		WithArgs(userID, syncDownloadItemKindProgressChunk).
		WillReturnResult(sqlmock.NewResult(0, 0))
	mock.ExpectQuery(`SELECT state2\s+FROM sync_download_state2`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"state2"}).AddRow(emptyState2))
	mock.ExpectQuery(`SELECT user_id, item_kind, scope_key, course_id, student_user_id, updated_at, content_hash FROM sync_download_state_items`).
		WithArgs(userID, syncDownloadItemKindProgressRow, scopeKey).
		WillReturnError(sql.ErrNoRows)
	mock.ExpectExec(`INSERT INTO sync_download_state_items`).
		WithArgs(
			userID,
			syncDownloadItemKindProgressRow,
			scopeKey,
			courseID,
			userID,
			incomingUpdatedAt,
			"content-hash-1",
		).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec(`INSERT INTO sync_download_state2`).
		WithArgs(teacherUserID, sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec(`INSERT INTO sync_download_state2`).
		WithArgs(userID, sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(0, 1))
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
				ContentHash:        "content-hash-1",
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

func TestProgressSyncSaveUploadsSkipsWeakerIncomingUpdate(t *testing.T) {
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
	deviceID := "device-c"
	incomingUpdatedAtRaw := "2026-03-02T00:10:00Z"
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
				ContentHash:   "content-hash-weaker",
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

func TestProgressSyncSaveChunkUploadsSkipsStaleUpdate(t *testing.T) {
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
	chapterKey := "1.1"
	existingUpdatedAt := time.Date(2026, 3, 2, 0, 0, 0, 0, time.UTC)

	mock.ExpectBegin()
	mock.ExpectPrepare(`SELECT updated_at FROM progress_sync_chunks`)
	mock.ExpectPrepare(`INSERT INTO progress_sync_chunks`)
	mock.ExpectPrepare(`UPDATE progress_sync_chunks`)
	mock.ExpectQuery(`SELECT ta.user_id`).
		WithArgs(courseID).
		WillReturnRows(sqlmock.NewRows([]string{"user_id"}).AddRow(teacherUserID))
	mock.ExpectQuery(`SELECT 1 FROM enrollments`).
		WithArgs(userID, courseID).
		WillReturnRows(sqlmock.NewRows([]string{"1"}).AddRow(1))
	mock.ExpectQuery(`SELECT updated_at FROM progress_sync_chunks`).
		WithArgs(courseID, userID, chapterKey).
		WillReturnRows(
			sqlmock.NewRows([]string{"updated_at"}).
				AddRow(existingUpdatedAt),
		)
	mock.ExpectCommit()

	savedCount, err := handler.saveChunkUploads(
		userID,
		[]uploadProgressChunkRequest{
			{
				CourseID:     courseID,
				ChapterKey:   chapterKey,
				ItemCount:    3,
				UpdatedAt:    "2026-03-01T23:59:00Z",
				Envelope:     base64.StdEncoding.EncodeToString([]byte("chunk-stale")),
				EnvelopeHash: "chunk-hash-stale",
				ContentHash:  "chunk-content-hash-stale",
			},
		},
	)
	if err != nil {
		t.Fatalf("saveChunkUploads() error = %v", err)
	}
	if savedCount != 0 {
		t.Fatalf("savedCount = %d, want 0", savedCount)
	}

	assertSQLMockExpectations(t, mock)
}

func TestProgressSyncSaveChunkUploadsUpdatesWhenIncomingIsNewer(t *testing.T) {
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
	chapterKey := "1.1"
	existingUpdatedAt := time.Date(2026, 3, 2, 0, 0, 0, 0, time.UTC)
	incomingUpdatedAt := time.Date(2026, 3, 2, 0, 10, 0, 0, time.UTC)
	envelopeBytes := []byte("chunk-newer")

	mock.ExpectBegin()
	mock.ExpectPrepare(`SELECT updated_at FROM progress_sync_chunks`)
	mock.ExpectPrepare(`INSERT INTO progress_sync_chunks`)
	mock.ExpectPrepare(`UPDATE progress_sync_chunks`)
	mock.ExpectQuery(`SELECT ta.user_id`).
		WithArgs(courseID).
		WillReturnRows(sqlmock.NewRows([]string{"user_id"}).AddRow(teacherUserID))
	mock.ExpectQuery(`SELECT 1 FROM enrollments`).
		WithArgs(userID, courseID).
		WillReturnRows(sqlmock.NewRows([]string{"1"}).AddRow(1))
	mock.ExpectQuery(`SELECT updated_at FROM progress_sync_chunks`).
		WithArgs(courseID, userID, chapterKey).
		WillReturnRows(
			sqlmock.NewRows([]string{"updated_at"}).
				AddRow(existingUpdatedAt),
		)
	mock.ExpectExec(`UPDATE progress_sync_chunks`).
		WithArgs(
			teacherUserID,
			4,
			incomingUpdatedAt,
			envelopeBytes,
			sqlmock.AnyArg(),
			"chunk-content-hash-newer",
			courseID,
			userID,
			chapterKey,
		).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	savedCount, err := handler.saveChunkUploads(
		userID,
		[]uploadProgressChunkRequest{
			{
				CourseID:     courseID,
				ChapterKey:   chapterKey,
				ItemCount:    4,
				UpdatedAt:    incomingUpdatedAt.Format(time.RFC3339),
				Envelope:     base64.StdEncoding.EncodeToString(envelopeBytes),
				EnvelopeHash: "chunk-hash-newer",
				ContentHash:  "chunk-content-hash-newer",
			},
		},
	)
	if err != nil {
		t.Fatalf("saveChunkUploads() error = %v", err)
	}
	if savedCount != 1 {
		t.Fatalf("savedCount = %d, want 1", savedCount)
	}

	assertSQLMockExpectations(t, mock)
}
