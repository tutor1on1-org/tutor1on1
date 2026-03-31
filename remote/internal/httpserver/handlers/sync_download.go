package handlers

import (
	"database/sql"
	"encoding/base64"
	"strconv"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
)

type SyncDownloadHandler struct {
	cfg Dependencies
}

func NewSyncDownloadHandler(deps Dependencies) *SyncDownloadHandler {
	return &SyncDownloadHandler{cfg: deps}
}

type syncDownloadManifestResponse struct {
	Sessions       []fiber.Map `json:"sessions"`
	ProgressChunks []fiber.Map `json:"progress_chunks"`
	ProgressRows   []fiber.Map `json:"progress_rows"`
}

type syncDownloadState2Response struct {
	State2 string `json:"state2"`
}

type syncDownloadFetchRequest struct {
	SessionSyncIDs []string                       `json:"session_sync_ids"`
	ProgressChunks []syncDownloadProgressChunkKey `json:"progress_chunks"`
	ProgressRows   []syncDownloadProgressRowKey   `json:"progress_rows"`
}

type syncDownloadProgressChunkKey struct {
	StudentUserID int64  `json:"student_user_id"`
	CourseID      int64  `json:"course_id"`
	ChapterKey    string `json:"chapter_key"`
}

type syncDownloadProgressRowKey struct {
	StudentUserID int64  `json:"student_user_id"`
	CourseID      int64  `json:"course_id"`
	KpKey         string `json:"kp_key"`
}

func (h *SyncDownloadHandler) Manifest(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	includeProgress := strings.EqualFold(
		strings.TrimSpace(c.Query("include_progress")),
		"true",
	)
	if _, err := readSyncDownloadState2(h.cfg.Store.DB, userID); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "sync download manifest failed")
	}
	items, err := listSyncDownloadStateItems(h.cfg.Store.DB, userID)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "sync download manifest failed")
	}
	response := buildSyncDownloadManifestResponse(items, includeProgress)
	return respondJSONWithETag(c, response)
}

func (h *SyncDownloadHandler) State2(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	state2, err := readSyncDownloadState2(h.cfg.Store.DB, userID)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "sync download state2 failed")
	}
	return c.JSON(syncDownloadState2Response{State2: state2})
}

func (h *SyncDownloadHandler) State1(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	state2, err := readSyncDownloadState2(h.cfg.Store.DB, userID)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "sync download state1 failed")
	}
	items, err := listSyncDownloadStateItems(h.cfg.Store.DB, userID)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "sync download state1 failed")
	}
	response := buildSyncDownloadManifestResponse(items, true)
	return c.JSON(fiber.Map{
		"state2":          state2,
		"sessions":        response.Sessions,
		"progress_chunks": response.ProgressChunks,
		"progress_rows":   response.ProgressRows,
	})
}

func buildSyncDownloadManifestResponse(
	items []syncDownloadStateItem,
	includeProgress bool,
) syncDownloadManifestResponse {
	response := syncDownloadManifestResponse{
		Sessions:       []fiber.Map{},
		ProgressChunks: []fiber.Map{},
		ProgressRows:   []fiber.Map{},
	}
	for _, item := range items {
		switch item.ItemKind {
		case syncDownloadItemKindSession:
			response.Sessions = append(response.Sessions, fiber.Map{
				"session_sync_id": item.ScopeKey,
				"updated_at":      item.UpdatedAt.UTC().Format(time.RFC3339),
				"content_hash":    item.ContentHash,
			})
		case syncDownloadItemKindProgressRow:
			if !includeProgress {
				continue
			}
			parts := strings.SplitN(item.ScopeKey, ":", 3)
			if len(parts) != 3 {
				continue
			}
			studentUserID, parseErr := strconv.ParseInt(strings.TrimSpace(parts[0]), 10, 64)
			if parseErr != nil {
				continue
			}
			courseID, parseErr := strconv.ParseInt(strings.TrimSpace(parts[1]), 10, 64)
			if parseErr != nil {
				continue
			}
			response.ProgressRows = append(response.ProgressRows, fiber.Map{
				"student_user_id": studentUserID,
				"course_id":       courseID,
				"kp_key":          parts[2],
				"updated_at":      item.UpdatedAt.UTC().Format(time.RFC3339),
				"content_hash":    item.ContentHash,
			})
		}
	}
	return response
}

func (h *SyncDownloadHandler) Fetch(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	var req syncDownloadFetchRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}

	sessions, err := h.fetchSessions(userID, req.SessionSyncIDs)
	if err != nil {
		return err
	}
	progressChunks, err := h.fetchProgressChunks(userID, req.ProgressChunks)
	if err != nil {
		return err
	}
	progressRows, err := h.fetchProgressRows(userID, req.ProgressRows)
	if err != nil {
		return err
	}

	return c.JSON(fiber.Map{
		"sessions":        sessions,
		"progress_chunks": progressChunks,
		"progress_rows":   progressRows,
	})
}

func (h *SyncDownloadHandler) listSessionManifest(userID int64) ([]fiber.Map, error) {
	rows, err := h.cfg.Store.DB.Query(
		`SELECT session_sync_id, updated_at, content_hash, envelope
		 FROM session_text_sync
		 WHERE teacher_user_id = ? OR student_user_id = ?
		 ORDER BY updated_at ASC, id ASC`,
		userID,
		userID,
	)
	if err != nil {
		return nil, fiber.NewError(fiber.StatusInternalServerError, "session sync manifest failed")
	}
	defer rows.Close()

	results := []fiber.Map{}
	for rows.Next() {
		var sessionSyncID string
		var updatedAt time.Time
		var contentHash sql.NullString
		var envelope []byte
		if err := rows.Scan(&sessionSyncID, &updatedAt, &contentHash, &envelope); err != nil {
			return nil, fiber.NewError(fiber.StatusInternalServerError, "session sync manifest failed")
		}
		hashValue := resolveSyncDownloadContentHash(contentHash.String, envelope)
		results = append(results, fiber.Map{
			"session_sync_id": sessionSyncID,
			"updated_at":      updatedAt.UTC().Format(time.RFC3339),
			"content_hash":    hashValue,
		})
	}
	if err := rows.Err(); err != nil {
		return nil, fiber.NewError(fiber.StatusInternalServerError, "session sync manifest failed")
	}
	return results, nil
}

func (h *SyncDownloadHandler) listProgressManifest(userID int64) ([]fiber.Map, []fiber.Map, error) {
	var chunkExists int
	chunkErr := h.cfg.Store.DB.QueryRow(
		`SELECT 1 FROM progress_sync_chunks WHERE teacher_user_id = ? OR student_user_id = ? LIMIT 1`,
		userID,
		userID,
	).Scan(&chunkExists)
	if chunkErr != nil && chunkErr != sql.ErrNoRows {
		return nil, nil, fiber.NewError(fiber.StatusInternalServerError, "progress sync manifest failed")
	}
	if chunkErr == nil {
		rows, err := h.cfg.Store.DB.Query(
			`SELECT student_user_id, course_id, chapter_key, updated_at, content_hash, envelope
			 FROM progress_sync_chunks
			 WHERE teacher_user_id = ? OR student_user_id = ?
			 ORDER BY updated_at ASC, id ASC`,
			userID,
			userID,
		)
		if err != nil {
			return nil, nil, fiber.NewError(fiber.StatusInternalServerError, "progress sync manifest failed")
		}
		defer rows.Close()
		results := []fiber.Map{}
		for rows.Next() {
			var studentUserID int64
			var courseID int64
			var chapterKey string
			var updatedAt sql.NullTime
			var contentHash sql.NullString
			var envelope []byte
			if err := rows.Scan(&studentUserID, &courseID, &chapterKey, &updatedAt, &contentHash, &envelope); err != nil {
				return nil, nil, fiber.NewError(fiber.StatusInternalServerError, "progress sync manifest failed")
			}
			hashValue := resolveSyncDownloadContentHash(contentHash.String, envelope)
			updatedAtValue := ""
			if updatedAt.Valid {
				updatedAtValue = updatedAt.Time.UTC().Format(time.RFC3339)
			}
			results = append(results, fiber.Map{
				"student_user_id": studentUserID,
				"course_id":       courseID,
				"chapter_key":     chapterKey,
				"updated_at":      updatedAtValue,
				"content_hash":    hashValue,
			})
		}
		if err := rows.Err(); err != nil {
			return nil, nil, fiber.NewError(fiber.StatusInternalServerError, "progress sync manifest failed")
		}
		return results, []fiber.Map{}, nil
	}

	rows, err := h.cfg.Store.DB.Query(
		`SELECT student_user_id, course_id, kp_key, updated_at, content_hash, envelope
		 FROM progress_sync
		 WHERE teacher_user_id = ? OR student_user_id = ?
		 ORDER BY updated_at ASC, id ASC`,
		userID,
		userID,
	)
	if err != nil {
		return nil, nil, fiber.NewError(fiber.StatusInternalServerError, "progress sync manifest failed")
	}
	defer rows.Close()
	results := []fiber.Map{}
	for rows.Next() {
		var studentUserID int64
		var courseID int64
		var kpKey string
		var updatedAt sql.NullTime
		var contentHash sql.NullString
		var envelope []byte
		if err := rows.Scan(&studentUserID, &courseID, &kpKey, &updatedAt, &contentHash, &envelope); err != nil {
			return nil, nil, fiber.NewError(fiber.StatusInternalServerError, "progress sync manifest failed")
		}
		hashValue := resolveSyncDownloadContentHash(contentHash.String, envelope)
		updatedAtValue := ""
		if updatedAt.Valid {
			updatedAtValue = updatedAt.Time.UTC().Format(time.RFC3339)
		}
		results = append(results, fiber.Map{
			"student_user_id": studentUserID,
			"course_id":       courseID,
			"kp_key":          kpKey,
			"updated_at":      updatedAtValue,
			"content_hash":    hashValue,
		})
	}
	if err := rows.Err(); err != nil {
		return nil, nil, fiber.NewError(fiber.StatusInternalServerError, "progress sync manifest failed")
	}
	return []fiber.Map{}, results, nil
}

func (h *SyncDownloadHandler) fetchSessions(userID int64, requested []string) ([]fiber.Map, error) {
	sessionIDs := uniqueNonEmptyStrings(requested)
	if len(sessionIDs) == 0 {
		return []fiber.Map{}, nil
	}
	args := make([]any, 0, len(sessionIDs)+2)
	args = append(args, userID, userID)
	for _, id := range sessionIDs {
		args = append(args, id)
	}
	query := `SELECT id, session_sync_id, course_id, teacher_user_id, student_user_id, sender_user_id, chapter_key, updated_at, envelope, envelope_hash, content_hash
		 FROM session_text_sync
		 WHERE (teacher_user_id = ? OR student_user_id = ?)
		   AND session_sync_id IN (` + sqlPlaceholders(len(sessionIDs)) + `)
		 ORDER BY updated_at ASC, id ASC`
	rows, err := h.cfg.Store.DB.Query(query, args...)
	if err != nil {
		return nil, fiber.NewError(fiber.StatusInternalServerError, "session sync fetch failed")
	}
	defer rows.Close()

	results := []fiber.Map{}
	for rows.Next() {
		var (
			id            int64
			sessionSyncID string
			courseID      int64
			teacherUserID int64
			studentUserID int64
			senderUserID  int64
			chapterKey    sql.NullString
			updatedAt     time.Time
			envelopeBytes []byte
			envelopeHash  sql.NullString
			contentHash   sql.NullString
		)
		if err := rows.Scan(
			&id,
			&sessionSyncID,
			&courseID,
			&teacherUserID,
			&studentUserID,
			&senderUserID,
			&chapterKey,
			&updatedAt,
			&envelopeBytes,
			&envelopeHash,
			&contentHash,
		); err != nil {
			return nil, fiber.NewError(fiber.StatusInternalServerError, "session sync fetch failed")
		}
		results = append(results, fiber.Map{
			"cursor_id":       id,
			"session_sync_id": sessionSyncID,
			"course_id":       courseID,
			"teacher_user_id": teacherUserID,
			"student_user_id": studentUserID,
			"sender_user_id":  senderUserID,
			"chapter_key":     chapterKey.String,
			"updated_at":      updatedAt.UTC().Format(time.RFC3339),
			"envelope":        base64.StdEncoding.EncodeToString(envelopeBytes),
			"envelope_hash":   envelopeHash.String,
			"content_hash":    contentHash.String,
		})
	}
	if err := rows.Err(); err != nil {
		return nil, fiber.NewError(fiber.StatusInternalServerError, "session sync fetch failed")
	}
	return results, nil
}

func (h *SyncDownloadHandler) fetchProgressChunks(userID int64, requested []syncDownloadProgressChunkKey) ([]fiber.Map, error) {
	keys := uniqueProgressChunkKeys(requested)
	if len(keys) == 0 {
		return []fiber.Map{}, nil
	}
	conditions := make([]string, 0, len(keys))
	args := []any{userID, userID}
	for _, key := range keys {
		conditions = append(conditions, "(p.student_user_id = ? AND p.course_id = ? AND p.chapter_key = ?)")
		args = append(args, key.StudentUserID, key.CourseID, key.ChapterKey)
	}
	query := `SELECT p.id, p.course_id, c.subject, p.teacher_user_id, p.student_user_id, p.chapter_key, p.item_count, p.updated_at, p.envelope, p.envelope_hash, p.content_hash
		 FROM progress_sync_chunks p
		 JOIN courses c ON c.id = p.course_id
		 WHERE (p.teacher_user_id = ? OR p.student_user_id = ?) AND (` + strings.Join(conditions, " OR ") + `)
		 ORDER BY p.updated_at ASC, p.id ASC`
	rows, err := h.cfg.Store.DB.Query(query, args...)
	if err != nil {
		return nil, fiber.NewError(fiber.StatusInternalServerError, "progress chunk sync fetch failed")
	}
	defer rows.Close()

	results := []fiber.Map{}
	for rows.Next() {
		var (
			id            int64
			courseID      int64
			courseSubject string
			teacherUserID int64
			studentUserID int64
			chapterKey    string
			itemCount     int
			updatedAtTime sql.NullTime
			envelopeBytes []byte
			envelopeHash  sql.NullString
			contentHash   sql.NullString
		)
		if err := rows.Scan(
			&id,
			&courseID,
			&courseSubject,
			&teacherUserID,
			&studentUserID,
			&chapterKey,
			&itemCount,
			&updatedAtTime,
			&envelopeBytes,
			&envelopeHash,
			&contentHash,
		); err != nil {
			return nil, fiber.NewError(fiber.StatusInternalServerError, "progress chunk sync fetch failed")
		}
		updatedAt := ""
		if updatedAtTime.Valid {
			updatedAt = updatedAtTime.Time.UTC().Format(time.RFC3339)
		}
		results = append(results, fiber.Map{
			"cursor_id":       id,
			"course_id":       courseID,
			"course_subject":  courseSubject,
			"teacher_user_id": teacherUserID,
			"student_user_id": studentUserID,
			"chapter_key":     chapterKey,
			"item_count":      itemCount,
			"updated_at":      updatedAt,
			"envelope":        base64.StdEncoding.EncodeToString(envelopeBytes),
			"envelope_hash":   envelopeHash.String,
			"content_hash":    contentHash.String,
		})
	}
	if err := rows.Err(); err != nil {
		return nil, fiber.NewError(fiber.StatusInternalServerError, "progress chunk sync fetch failed")
	}
	return results, nil
}

func (h *SyncDownloadHandler) fetchProgressRows(userID int64, requested []syncDownloadProgressRowKey) ([]fiber.Map, error) {
	keys := uniqueProgressRowKeys(requested)
	if len(keys) == 0 {
		return []fiber.Map{}, nil
	}
	conditions := make([]string, 0, len(keys))
	args := []any{userID, userID}
	for _, key := range keys {
		conditions = append(conditions, "(p.student_user_id = ? AND p.course_id = ? AND p.kp_key = ?)")
		args = append(args, key.StudentUserID, key.CourseID, key.KpKey)
	}
	query := `SELECT p.id, p.course_id, c.subject, p.teacher_user_id, p.student_user_id, p.kp_key, p.lit, p.lit_percent,
		        p.question_level, p.summary_text, p.summary_raw_response, p.summary_valid, p.updated_at, p.envelope, p.envelope_hash, p.content_hash
		 FROM progress_sync p
		 JOIN courses c ON c.id = p.course_id
		 WHERE (p.teacher_user_id = ? OR p.student_user_id = ?) AND (` + strings.Join(conditions, " OR ") + `)
		 ORDER BY p.updated_at ASC, p.id ASC`
	rows, err := h.cfg.Store.DB.Query(query, args...)
	if err != nil {
		return nil, fiber.NewError(fiber.StatusInternalServerError, "progress sync fetch failed")
	}
	defer rows.Close()

	results := []fiber.Map{}
	for rows.Next() {
		var (
			id                 int64
			courseID           int64
			courseSubject      string
			teacherUserID      int64
			studentUserID      int64
			kpKey              string
			lit                bool
			litPercent         int
			questionLevel      sql.NullString
			summaryText        sql.NullString
			summaryRawResponse sql.NullString
			summaryValid       sql.NullBool
			updatedAtTime      sql.NullTime
			envelopeBytes      []byte
			envelopeHash       sql.NullString
			contentHash        sql.NullString
		)
		if err := rows.Scan(
			&id,
			&courseID,
			&courseSubject,
			&teacherUserID,
			&studentUserID,
			&kpKey,
			&lit,
			&litPercent,
			&questionLevel,
			&summaryText,
			&summaryRawResponse,
			&summaryValid,
			&updatedAtTime,
			&envelopeBytes,
			&envelopeHash,
			&contentHash,
		); err != nil {
			return nil, fiber.NewError(fiber.StatusInternalServerError, "progress sync fetch failed")
		}
		updatedAt := ""
		if updatedAtTime.Valid {
			updatedAt = updatedAtTime.Time.UTC().Format(time.RFC3339)
		}
		results = append(results, fiber.Map{
			"cursor_id":            id,
			"course_id":            courseID,
			"course_subject":       courseSubject,
			"teacher_user_id":      teacherUserID,
			"student_user_id":      studentUserID,
			"kp_key":               kpKey,
			"lit":                  lit,
			"lit_percent":          litPercent,
			"question_level":       questionLevel.String,
			"summary_text":         summaryText.String,
			"summary_raw_response": summaryRawResponse.String,
			"summary_valid":        nullableBoolToInterface(summaryValid),
			"updated_at":           updatedAt,
			"envelope":             base64.StdEncoding.EncodeToString(envelopeBytes),
			"envelope_hash":        envelopeHash.String,
			"content_hash":         contentHash.String,
		})
	}
	if err := rows.Err(); err != nil {
		return nil, fiber.NewError(fiber.StatusInternalServerError, "progress sync fetch failed")
	}
	return results, nil
}

func sqlPlaceholders(count int) string {
	if count <= 0 {
		return ""
	}
	parts := make([]string, count)
	for i := range parts {
		parts[i] = "?"
	}
	return strings.Join(parts, ",")
}

func uniqueNonEmptyStrings(values []string) []string {
	seen := map[string]struct{}{}
	results := []string{}
	for _, value := range values {
		trimmed := strings.TrimSpace(value)
		if trimmed == "" {
			continue
		}
		if _, exists := seen[trimmed]; exists {
			continue
		}
		seen[trimmed] = struct{}{}
		results = append(results, trimmed)
	}
	return results
}

func uniqueProgressChunkKeys(values []syncDownloadProgressChunkKey) []syncDownloadProgressChunkKey {
	seen := map[string]struct{}{}
	results := []syncDownloadProgressChunkKey{}
	for _, value := range values {
		chapterKey := strings.TrimSpace(value.ChapterKey)
		if value.StudentUserID <= 0 || value.CourseID <= 0 || chapterKey == "" {
			continue
		}
		compound := strconv.FormatInt(value.StudentUserID, 10) + "|" + strconv.FormatInt(value.CourseID, 10) + "|" + chapterKey
		if _, exists := seen[compound]; exists {
			continue
		}
		seen[compound] = struct{}{}
		results = append(results, syncDownloadProgressChunkKey{
			StudentUserID: value.StudentUserID,
			CourseID:      value.CourseID,
			ChapterKey:    chapterKey,
		})
	}
	return results
}

func uniqueProgressRowKeys(values []syncDownloadProgressRowKey) []syncDownloadProgressRowKey {
	seen := map[string]struct{}{}
	results := []syncDownloadProgressRowKey{}
	for _, value := range values {
		kpKey := strings.TrimSpace(value.KpKey)
		if value.StudentUserID <= 0 || value.CourseID <= 0 || kpKey == "" {
			continue
		}
		compound := strconv.FormatInt(value.StudentUserID, 10) + "|" + strconv.FormatInt(value.CourseID, 10) + "|" + kpKey
		if _, exists := seen[compound]; exists {
			continue
		}
		seen[compound] = struct{}{}
		results = append(results, syncDownloadProgressRowKey{
			StudentUserID: value.StudentUserID,
			CourseID:      value.CourseID,
			KpKey:         kpKey,
		})
	}
	return results
}
