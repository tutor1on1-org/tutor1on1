package handlers

import (
	"crypto/sha256"
	"database/sql"
	"encoding/binary"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"
)

const (
	syncDownloadItemKindSession       = "session"
	syncDownloadItemKindProgressRow   = "progress_row"
	syncDownloadItemKindProgressChunk = "progress_chunk"
	syncDownloadState2Version         = "v2"
	syncDownloadState2WordCount       = 4
)

type syncDownloadSQLExecutor interface {
	Exec(query string, args ...any) (sql.Result, error)
	Query(query string, args ...any) (*sql.Rows, error)
	QueryRow(query string, args ...any) *sql.Row
}

type syncDownloadStateItem struct {
	UserID        int64
	ItemKind      string
	ScopeKey      string
	CourseID      int64
	StudentUserID int64
	UpdatedAt     time.Time
	ContentHash   string
}

type syncDownloadState2Aggregate struct {
	Count uint64
	Sums  [syncDownloadState2WordCount]uint64
	Xors  [syncDownloadState2WordCount]uint64
}

type syncDownloadState2MutationTracker struct {
	exec            syncDownloadSQLExecutor
	aggregateByUser map[int64]syncDownloadState2Aggregate
	dirtyUsers      map[int64]struct{}
	dirtyUserOrder  []int64
}

func buildSyncDownloadStateFingerprint(item syncDownloadStateItem) string {
	return strings.Join([]string{
		strings.TrimSpace(item.ItemKind),
		strings.TrimSpace(item.ScopeKey),
		strings.TrimSpace(item.ContentHash),
	}, "|")
}

func buildSyncDownloadState2FingerprintWords(fingerprint string) [syncDownloadState2WordCount]uint64 {
	sum := sha256.Sum256([]byte(strings.TrimSpace(fingerprint)))
	words := [syncDownloadState2WordCount]uint64{}
	for index := 0; index < syncDownloadState2WordCount; index++ {
		start := index * 8
		words[index] = binary.BigEndian.Uint64(sum[start : start+8])
	}
	return words
}

func (aggregate *syncDownloadState2Aggregate) addFingerprint(fingerprint string) {
	trimmed := strings.TrimSpace(fingerprint)
	if trimmed == "" {
		return
	}
	words := buildSyncDownloadState2FingerprintWords(trimmed)
	aggregate.Count++
	for index, word := range words {
		aggregate.Sums[index] += word
		aggregate.Xors[index] ^= word
	}
}

func (aggregate *syncDownloadState2Aggregate) removeFingerprint(fingerprint string) {
	trimmed := strings.TrimSpace(fingerprint)
	if trimmed == "" {
		return
	}
	words := buildSyncDownloadState2FingerprintWords(trimmed)
	if aggregate.Count > 0 {
		aggregate.Count--
	}
	for index, word := range words {
		aggregate.Sums[index] -= word
		aggregate.Xors[index] ^= word
	}
}

func encodeSyncDownloadState2(aggregate syncDownloadState2Aggregate) string {
	parts := make([]string, 0, 2+syncDownloadState2WordCount*2)
	parts = append(parts, syncDownloadState2Version)
	parts = append(parts, fmt.Sprintf("%016x", aggregate.Count))
	for _, value := range aggregate.Sums {
		parts = append(parts, fmt.Sprintf("%016x", value))
	}
	for _, value := range aggregate.Xors {
		parts = append(parts, fmt.Sprintf("%016x", value))
	}
	return strings.Join(parts, ":")
}

func parseSyncDownloadState2(state2 string) (syncDownloadState2Aggregate, error) {
	parts := strings.Split(strings.TrimSpace(state2), ":")
	expectedLength := 2 + syncDownloadState2WordCount*2
	if len(parts) != expectedLength {
		return syncDownloadState2Aggregate{}, fmt.Errorf("invalid sync download state2 parts: %d", len(parts))
	}
	if parts[0] != syncDownloadState2Version {
		return syncDownloadState2Aggregate{}, fmt.Errorf("invalid sync download state2 version: %s", parts[0])
	}
	count, err := strconv.ParseUint(parts[1], 16, 64)
	if err != nil {
		return syncDownloadState2Aggregate{}, err
	}
	aggregate := syncDownloadState2Aggregate{Count: count}
	for index := 0; index < syncDownloadState2WordCount; index++ {
		value, parseErr := strconv.ParseUint(parts[2+index], 16, 64)
		if parseErr != nil {
			return syncDownloadState2Aggregate{}, parseErr
		}
		aggregate.Sums[index] = value
	}
	for index := 0; index < syncDownloadState2WordCount; index++ {
		value, parseErr := strconv.ParseUint(parts[2+syncDownloadState2WordCount+index], 16, 64)
		if parseErr != nil {
			return syncDownloadState2Aggregate{}, parseErr
		}
		aggregate.Xors[index] = value
	}
	return aggregate, nil
}

func buildSyncDownloadState2(fingerprints []string) string {
	aggregate := syncDownloadState2Aggregate{}
	for _, fingerprint := range fingerprints {
		aggregate.addFingerprint(fingerprint)
	}
	return encodeSyncDownloadState2(aggregate)
}

func resolveSyncDownloadContentHash(currentHash string, envelope []byte) string {
	hashValue := strings.TrimSpace(currentHash)
	if hashValue != "" {
		return hashValue
	}
	if len(envelope) == 0 {
		return ""
	}
	return buildWeakETag(envelope)
}

func uniqueInt64s(values []int64) []int64 {
	if len(values) == 0 {
		return []int64{}
	}
	seen := map[int64]struct{}{}
	results := make([]int64, 0, len(values))
	for _, value := range values {
		if value <= 0 {
			continue
		}
		if _, exists := seen[value]; exists {
			continue
		}
		seen[value] = struct{}{}
		results = append(results, value)
	}
	return results
}

func normalizeSyncDownloadStateItem(item syncDownloadStateItem) (syncDownloadStateItem, bool) {
	normalized := syncDownloadStateItem{
		UserID:        item.UserID,
		ItemKind:      strings.TrimSpace(item.ItemKind),
		ScopeKey:      strings.TrimSpace(item.ScopeKey),
		CourseID:      item.CourseID,
		StudentUserID: item.StudentUserID,
		UpdatedAt:     item.UpdatedAt.UTC(),
		ContentHash:   strings.TrimSpace(item.ContentHash),
	}
	if normalized.UserID <= 0 || normalized.CourseID <= 0 || normalized.StudentUserID <= 0 {
		return syncDownloadStateItem{}, false
	}
	if normalized.ItemKind == "" || normalized.ScopeKey == "" || normalized.ContentHash == "" {
		return syncDownloadStateItem{}, false
	}
	return normalized, true
}

func buildSessionDownloadStateItems(
	teacherUserID int64,
	studentUserID int64,
	courseID int64,
	sessionSyncID string,
	updatedAt time.Time,
	contentHash string,
) []syncDownloadStateItem {
	items := []syncDownloadStateItem{}
	for _, ownerUserID := range uniqueInt64s([]int64{teacherUserID, studentUserID}) {
		items = append(items, syncDownloadStateItem{
			UserID:        ownerUserID,
			ItemKind:      syncDownloadItemKindSession,
			ScopeKey:      strings.TrimSpace(sessionSyncID),
			CourseID:      courseID,
			StudentUserID: studentUserID,
			UpdatedAt:     updatedAt.UTC(),
			ContentHash:   strings.TrimSpace(contentHash),
		})
	}
	return items
}

func buildProgressRowDownloadStateItems(
	teacherUserID int64,
	studentUserID int64,
	courseID int64,
	kpKey string,
	updatedAt time.Time,
	contentHash string,
) []syncDownloadStateItem {
	scopeKey := buildProgressRowStateScopeKey(studentUserID, courseID, kpKey)
	items := []syncDownloadStateItem{}
	for _, ownerUserID := range uniqueInt64s([]int64{teacherUserID, studentUserID}) {
		items = append(items, syncDownloadStateItem{
			UserID:        ownerUserID,
			ItemKind:      syncDownloadItemKindProgressRow,
			ScopeKey:      scopeKey,
			CourseID:      courseID,
			StudentUserID: studentUserID,
			UpdatedAt:     updatedAt.UTC(),
			ContentHash:   strings.TrimSpace(contentHash),
		})
	}
	return items
}

func buildProgressChunkDownloadStateItems(
	teacherUserID int64,
	studentUserID int64,
	courseID int64,
	chapterKey string,
	updatedAt time.Time,
	contentHash string,
) []syncDownloadStateItem {
	scopeKey := buildProgressChunkStateScopeKey(studentUserID, courseID, chapterKey)
	items := []syncDownloadStateItem{}
	for _, ownerUserID := range uniqueInt64s([]int64{teacherUserID, studentUserID}) {
		items = append(items, syncDownloadStateItem{
			UserID:        ownerUserID,
			ItemKind:      syncDownloadItemKindProgressChunk,
			ScopeKey:      scopeKey,
			CourseID:      courseID,
			StudentUserID: studentUserID,
			UpdatedAt:     updatedAt.UTC(),
			ContentHash:   strings.TrimSpace(contentHash),
		})
	}
	return items
}

func buildProgressRowStateScopeKey(studentUserID int64, courseID int64, kpKey string) string {
	return strconv.FormatInt(studentUserID, 10) + ":" +
		strconv.FormatInt(courseID, 10) + ":" +
		strings.TrimSpace(kpKey)
}

func buildProgressChunkStateScopeKey(studentUserID int64, courseID int64, chapterKey string) string {
	normalizedChapterKey := strings.TrimSpace(chapterKey)
	if normalizedChapterKey == "" {
		normalizedChapterKey = "ungrouped"
	}
	return strconv.FormatInt(studentUserID, 10) + ":" +
		strconv.FormatInt(courseID, 10) + ":" +
		normalizedChapterKey
}

func rawUpsertSyncDownloadStateItems(
	exec syncDownloadSQLExecutor,
	items []syncDownloadStateItem,
) error {
	for _, item := range items {
		normalized, ok := normalizeSyncDownloadStateItem(item)
		if !ok {
			continue
		}
		if _, err := exec.Exec(
			`INSERT INTO sync_download_state_items
			 (user_id, item_kind, scope_key, course_id, student_user_id, updated_at, content_hash)
			 VALUES (?, ?, ?, ?, ?, ?, ?)
			 ON DUPLICATE KEY UPDATE
			   course_id = VALUES(course_id),
			   student_user_id = VALUES(student_user_id),
			   updated_at = VALUES(updated_at),
			   content_hash = VALUES(content_hash)`,
			normalized.UserID,
			normalized.ItemKind,
			normalized.ScopeKey,
			normalized.CourseID,
			normalized.StudentUserID,
			normalized.UpdatedAt,
			normalized.ContentHash,
		); err != nil {
			return err
		}
	}
	return nil
}

func listSyncDownloadStateItems(
	exec syncDownloadSQLExecutor,
	userID int64,
) ([]syncDownloadStateItem, error) {
	if _, err := pruneLegacyProgressChunkSyncDownloadState(exec, userID); err != nil {
		return nil, err
	}
	rows, err := exec.Query(
		`SELECT user_id, item_kind, scope_key, course_id, student_user_id, updated_at, content_hash
		 FROM sync_download_state_items
		 WHERE user_id = ? AND item_kind <> ?
		 ORDER BY item_kind ASC, scope_key ASC`,
		userID,
		syncDownloadItemKindProgressChunk,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	results := []syncDownloadStateItem{}
	for rows.Next() {
		var item syncDownloadStateItem
		if err := rows.Scan(
			&item.UserID,
			&item.ItemKind,
			&item.ScopeKey,
			&item.CourseID,
			&item.StudentUserID,
			&item.UpdatedAt,
			&item.ContentHash,
		); err != nil {
			return nil, err
		}
		normalized, ok := normalizeSyncDownloadStateItem(item)
		if !ok {
			continue
		}
		results = append(results, normalized)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return results, nil
}

func rebuildSyncDownloadState2(
	exec syncDownloadSQLExecutor,
	userID int64,
) error {
	items, err := listSyncDownloadStateItems(exec, userID)
	if err != nil {
		return err
	}
	fingerprints := make([]string, 0, len(items))
	for _, item := range items {
		fingerprints = append(fingerprints, buildSyncDownloadStateFingerprint(item))
	}
	_, err = exec.Exec(
		`INSERT INTO sync_download_state2 (user_id, state2, updated_at)
		 VALUES (?, ?, UTC_TIMESTAMP())
		 ON DUPLICATE KEY UPDATE
		   state2 = VALUES(state2),
		   updated_at = VALUES(updated_at)`,
		userID,
		buildSyncDownloadState2(fingerprints),
	)
	return err
}

func readSyncDownloadState2(
	exec syncDownloadSQLExecutor,
	userID int64,
) (string, error) {
	pruned, err := pruneLegacyProgressChunkSyncDownloadState(exec, userID)
	if err != nil {
		return "", err
	}
	if pruned {
		if err := rebuildSyncDownloadState2(exec, userID); err != nil {
			return "", err
		}
	}
	var state2 string
	if err := exec.QueryRow(
		`SELECT state2 FROM sync_download_state2 WHERE user_id = ?`,
		userID,
	).Scan(&state2); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			if err := backfillSyncDownloadStateForUser(exec, userID); err != nil {
				return "", err
			}
			if err := rebuildSyncDownloadState2(exec, userID); err != nil {
				return "", err
			}
			if scanErr := exec.QueryRow(
				`SELECT state2 FROM sync_download_state2 WHERE user_id = ?`,
				userID,
			).Scan(&state2); scanErr != nil {
				if errors.Is(scanErr, sql.ErrNoRows) {
					return encodeSyncDownloadState2(syncDownloadState2Aggregate{}), nil
				}
				return "", scanErr
			}
			return strings.TrimSpace(state2), nil
		}
		return "", err
	}
	return strings.TrimSpace(state2), nil
}

func ensureSyncDownloadStateInitialized(db *sql.DB, userID int64) error {
	var existing int
	err := db.QueryRow(
		`SELECT 1 FROM sync_download_state2 WHERE user_id = ? LIMIT 1`,
		userID,
	).Scan(&existing)
	if err == nil {
		return nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return err
	}
	if err := backfillSyncDownloadStateForUser(db, userID); err != nil {
		return err
	}
	return rebuildSyncDownloadState2(db, userID)
}

func newSyncDownloadState2MutationTracker(
	exec syncDownloadSQLExecutor,
) *syncDownloadState2MutationTracker {
	return &syncDownloadState2MutationTracker{
		exec:            exec,
		aggregateByUser: map[int64]syncDownloadState2Aggregate{},
		dirtyUsers:      map[int64]struct{}{},
		dirtyUserOrder:  []int64{},
	}
}

func (tracker *syncDownloadState2MutationTracker) loadAggregate(userID int64) (syncDownloadState2Aggregate, error) {
	if aggregate, exists := tracker.aggregateByUser[userID]; exists {
		return aggregate, nil
	}
	pruned, err := pruneLegacyProgressChunkSyncDownloadState(tracker.exec, userID)
	if err != nil {
		return syncDownloadState2Aggregate{}, err
	}
	if pruned {
		if err := rebuildSyncDownloadState2(tracker.exec, userID); err != nil {
			return syncDownloadState2Aggregate{}, err
		}
	}
	var state2 string
	err = tracker.exec.QueryRow(
		`SELECT state2
		 FROM sync_download_state2
		 WHERE user_id = ?
		 LIMIT 1
		 FOR UPDATE`,
		userID,
	).Scan(&state2)
	switch {
	case err == nil:
		aggregate, parseErr := parseSyncDownloadState2(state2)
		if parseErr != nil {
			return syncDownloadState2Aggregate{}, parseErr
		}
		tracker.aggregateByUser[userID] = aggregate
		return aggregate, nil
	case errors.Is(err, sql.ErrNoRows):
		if err := backfillSyncDownloadStateForUser(tracker.exec, userID); err != nil {
			return syncDownloadState2Aggregate{}, err
		}
		if err := rebuildSyncDownloadState2(tracker.exec, userID); err != nil {
			return syncDownloadState2Aggregate{}, err
		}
		var rebuiltState2 string
		if scanErr := tracker.exec.QueryRow(
			`SELECT state2
			 FROM sync_download_state2
			 WHERE user_id = ?
			 LIMIT 1
			 FOR UPDATE`,
			userID,
		).Scan(&rebuiltState2); scanErr != nil {
			return syncDownloadState2Aggregate{}, scanErr
		}
		aggregate, parseErr := parseSyncDownloadState2(rebuiltState2)
		if parseErr != nil {
			return syncDownloadState2Aggregate{}, parseErr
		}
		tracker.aggregateByUser[userID] = aggregate
		return aggregate, nil
	default:
		return syncDownloadState2Aggregate{}, err
	}
}

func (tracker *syncDownloadState2MutationTracker) setAggregate(userID int64, aggregate syncDownloadState2Aggregate) {
	tracker.aggregateByUser[userID] = aggregate
	if _, exists := tracker.dirtyUsers[userID]; exists {
		return
	}
	tracker.dirtyUsers[userID] = struct{}{}
	tracker.dirtyUserOrder = append(tracker.dirtyUserOrder, userID)
}

func (tracker *syncDownloadState2MutationTracker) persist() error {
	for _, userID := range tracker.dirtyUserOrder {
		aggregate := tracker.aggregateByUser[userID]
		if _, err := tracker.exec.Exec(
			`INSERT INTO sync_download_state2 (user_id, state2, updated_at)
			 VALUES (?, ?, UTC_TIMESTAMP())
			 ON DUPLICATE KEY UPDATE
			   state2 = VALUES(state2),
			   updated_at = VALUES(updated_at)`,
			userID,
			encodeSyncDownloadState2(aggregate),
		); err != nil {
			return err
		}
	}
	return nil
}

func findSyncDownloadStateItemForUpdate(
	exec syncDownloadSQLExecutor,
	userID int64,
	itemKind string,
	scopeKey string,
) (syncDownloadStateItem, bool, error) {
	var item syncDownloadStateItem
	err := exec.QueryRow(
		`SELECT user_id, item_kind, scope_key, course_id, student_user_id, updated_at, content_hash
		 FROM sync_download_state_items
		 WHERE user_id = ? AND item_kind = ? AND scope_key = ?
		 LIMIT 1
		 FOR UPDATE`,
		userID,
		strings.TrimSpace(itemKind),
		strings.TrimSpace(scopeKey),
	).Scan(
		&item.UserID,
		&item.ItemKind,
		&item.ScopeKey,
		&item.CourseID,
		&item.StudentUserID,
		&item.UpdatedAt,
		&item.ContentHash,
	)
	switch {
	case err == nil:
		normalized, ok := normalizeSyncDownloadStateItem(item)
		if !ok {
			return syncDownloadStateItem{}, false, nil
		}
		return normalized, true, nil
	case errors.Is(err, sql.ErrNoRows):
		return syncDownloadStateItem{}, false, nil
	default:
		return syncDownloadStateItem{}, false, err
	}
}

func upsertSyncDownloadStateItems(
	exec syncDownloadSQLExecutor,
	items []syncDownloadStateItem,
) error {
	tracker := newSyncDownloadState2MutationTracker(exec)
	for _, item := range items {
		normalized, ok := normalizeSyncDownloadStateItem(item)
		if !ok {
			continue
		}
		aggregate, err := tracker.loadAggregate(normalized.UserID)
		if err != nil {
			return err
		}
		existing, found, err := findSyncDownloadStateItemForUpdate(
			exec,
			normalized.UserID,
			normalized.ItemKind,
			normalized.ScopeKey,
		)
		if err != nil {
			return err
		}
		if found {
			aggregate.removeFingerprint(buildSyncDownloadStateFingerprint(existing))
		}
		aggregate.addFingerprint(buildSyncDownloadStateFingerprint(normalized))
		if _, err := exec.Exec(
			`INSERT INTO sync_download_state_items
			 (user_id, item_kind, scope_key, course_id, student_user_id, updated_at, content_hash)
			 VALUES (?, ?, ?, ?, ?, ?, ?)
			 ON DUPLICATE KEY UPDATE
			   course_id = VALUES(course_id),
			   student_user_id = VALUES(student_user_id),
			   updated_at = VALUES(updated_at),
			   content_hash = VALUES(content_hash)`,
			normalized.UserID,
			normalized.ItemKind,
			normalized.ScopeKey,
			normalized.CourseID,
			normalized.StudentUserID,
			normalized.UpdatedAt,
			normalized.ContentHash,
		); err != nil {
			return err
		}
		tracker.setAggregate(normalized.UserID, aggregate)
	}
	return tracker.persist()
}

func backfillSyncDownloadStateForUser(
	exec syncDownloadSQLExecutor,
	userID int64,
) error {
	sessionRows, err := exec.Query(
		`SELECT course_id, teacher_user_id, student_user_id, session_sync_id, updated_at, content_hash, envelope_hash, envelope
		 FROM session_text_sync
		 WHERE teacher_user_id = ? OR student_user_id = ?`,
		userID,
		userID,
	)
	if err != nil {
		return err
	}
	sessionItems := []syncDownloadStateItem{}
	for sessionRows.Next() {
		var (
			courseID      int64
			teacherUserID int64
			studentUserID int64
			sessionSyncID string
			updatedAt     time.Time
			contentHash   sql.NullString
			envelopeHash  sql.NullString
			envelopeBytes []byte
		)
		if err := sessionRows.Scan(
			&courseID,
			&teacherUserID,
			&studentUserID,
			&sessionSyncID,
			&updatedAt,
			&contentHash,
			&envelopeHash,
			&envelopeBytes,
		); err != nil {
			sessionRows.Close()
			return err
		}
		_ = teacherUserID
		resolvedContentHash := resolveSyncDownloadContentHash(
			contentHash.String,
			envelopeBytes,
		)
		sessionItems = append(sessionItems, syncDownloadStateItem{
			UserID:        userID,
			ItemKind:      syncDownloadItemKindSession,
			ScopeKey:      strings.TrimSpace(sessionSyncID),
			CourseID:      courseID,
			StudentUserID: studentUserID,
			UpdatedAt:     updatedAt.UTC(),
			ContentHash:   resolvedContentHash,
		})
	}
	if err := sessionRows.Err(); err != nil {
		sessionRows.Close()
		return err
	}
	sessionRows.Close()
	if err := rawUpsertSyncDownloadStateItems(exec, sessionItems); err != nil {
		return err
	}

	progressRows, err := exec.Query(
		`SELECT course_id, teacher_user_id, student_user_id, kp_key, updated_at, content_hash, envelope_hash, envelope
		 FROM progress_sync
		 WHERE teacher_user_id = ? OR student_user_id = ?`,
		userID,
		userID,
	)
	if err != nil {
		return err
	}
	progressItems := []syncDownloadStateItem{}
	for progressRows.Next() {
		var (
			courseID      int64
			teacherUserID int64
			studentUserID int64
			kpKey         string
			updatedAt     sql.NullTime
			contentHash   sql.NullString
			envelopeHash  sql.NullString
			envelopeBytes []byte
		)
		if err := progressRows.Scan(
			&courseID,
			&teacherUserID,
			&studentUserID,
			&kpKey,
			&updatedAt,
			&contentHash,
			&envelopeHash,
			&envelopeBytes,
		); err != nil {
			progressRows.Close()
			return err
		}
		_ = teacherUserID
		if !updatedAt.Valid {
			continue
		}
		resolvedContentHash := resolveSyncDownloadContentHash(
			contentHash.String,
			envelopeBytes,
		)
		progressItems = append(progressItems, syncDownloadStateItem{
			UserID:        userID,
			ItemKind:      syncDownloadItemKindProgressRow,
			ScopeKey:      buildProgressRowStateScopeKey(studentUserID, courseID, kpKey),
			CourseID:      courseID,
			StudentUserID: studentUserID,
			UpdatedAt:     updatedAt.Time.UTC(),
			ContentHash:   resolvedContentHash,
		})
	}
	if err := progressRows.Err(); err != nil {
		progressRows.Close()
		return err
	}
	progressRows.Close()
	if err := rawUpsertSyncDownloadStateItems(exec, progressItems); err != nil {
		return err
	}
	_, err = exec.Exec(
		`DELETE FROM sync_download_state_items
		 WHERE user_id = ? AND item_kind = ?`,
		userID,
		syncDownloadItemKindProgressChunk,
	)
	return err
}

func pruneLegacyProgressChunkSyncDownloadState(
	exec syncDownloadSQLExecutor,
	userID int64,
) (bool, error) {
	result, err := exec.Exec(
		`DELETE FROM sync_download_state_items
		 WHERE user_id = ? AND item_kind = ?`,
		userID,
		syncDownloadItemKindProgressChunk,
	)
	if err != nil {
		return false, err
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return true, nil
	}
	return affected > 0, nil
}

func listSyncDownloadStateItemsForDelete(
	exec syncDownloadSQLExecutor,
	courseID int64,
	studentUserID *int64,
) ([]syncDownloadStateItem, error) {
	query := `SELECT user_id, item_kind, scope_key, course_id, student_user_id, updated_at, content_hash
		 FROM sync_download_state_items
		 WHERE course_id = ?`
	args := []any{courseID}
	if studentUserID != nil {
		query += ` AND student_user_id = ?`
		args = append(args, *studentUserID)
	}
	query += ` FOR UPDATE`
	rows, err := exec.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	results := []syncDownloadStateItem{}
	for rows.Next() {
		var item syncDownloadStateItem
		if err := rows.Scan(
			&item.UserID,
			&item.ItemKind,
			&item.ScopeKey,
			&item.CourseID,
			&item.StudentUserID,
			&item.UpdatedAt,
			&item.ContentHash,
		); err != nil {
			return nil, err
		}
		normalized, ok := normalizeSyncDownloadStateItem(item)
		if !ok {
			continue
		}
		results = append(results, normalized)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return results, nil
}

func deleteSyncDownloadStateItems(
	exec syncDownloadSQLExecutor,
	items []syncDownloadStateItem,
	deleteQuery string,
	deleteArgs ...any,
) error {
	tracker := newSyncDownloadState2MutationTracker(exec)
	for _, item := range items {
		aggregate, err := tracker.loadAggregate(item.UserID)
		if err != nil {
			return err
		}
		aggregate.removeFingerprint(buildSyncDownloadStateFingerprint(item))
		tracker.setAggregate(item.UserID, aggregate)
	}
	if _, err := exec.Exec(deleteQuery, deleteArgs...); err != nil {
		return err
	}
	return tracker.persist()
}

func deleteSyncDownloadStateByCourseAndStudent(
	exec syncDownloadSQLExecutor,
	courseID int64,
	studentUserID int64,
) error {
	items, err := listSyncDownloadStateItemsForDelete(exec, courseID, &studentUserID)
	if err != nil {
		return err
	}
	if len(items) == 0 {
		return nil
	}
	return deleteSyncDownloadStateItems(
		exec,
		items,
		`DELETE FROM sync_download_state_items
		 WHERE course_id = ? AND student_user_id = ?`,
		courseID,
		studentUserID,
	)
}

func deleteSyncDownloadStateByCourse(
	exec syncDownloadSQLExecutor,
	courseID int64,
) error {
	items, err := listSyncDownloadStateItemsForDelete(exec, courseID, nil)
	if err != nil {
		return err
	}
	if len(items) == 0 {
		return nil
	}
	return deleteSyncDownloadStateItems(
		exec,
		items,
		`DELETE FROM sync_download_state_items
		 WHERE course_id = ?`,
		courseID,
	)
}
