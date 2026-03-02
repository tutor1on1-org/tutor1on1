package handlers

import (
	"database/sql"
	"encoding/base64"
	"errors"
	"log"
	"strconv"
	"strings"
	"time"

	mysqlDriver "github.com/go-sql-driver/mysql"
	"github.com/gofiber/fiber/v2"
)

type ProgressSyncHandler struct {
	cfg Dependencies
}

func NewProgressSyncHandler(deps Dependencies) *ProgressSyncHandler {
	return &ProgressSyncHandler{cfg: deps}
}

type uploadProgressRequest struct {
	CourseID           int64  `json:"course_id"`
	KpKey              string `json:"kp_key"`
	Lit                bool   `json:"lit"`
	LitPercent         int    `json:"lit_percent"`
	QuestionLevel      string `json:"question_level"`
	SummaryText        string `json:"summary_text"`
	SummaryRawResponse string `json:"summary_raw_response"`
	SummaryValid       *bool  `json:"summary_valid"`
	UpdatedAt          string `json:"updated_at"`
	Envelope           string `json:"envelope"`
	EnvelopeHash       string `json:"envelope_hash"`
}

type uploadProgressBatchRequest struct {
	Items []uploadProgressRequest `json:"items"`
}

type uploadProgressChunkRequest struct {
	CourseID     int64  `json:"course_id"`
	ChapterKey   string `json:"chapter_key"`
	ItemCount    int    `json:"item_count"`
	UpdatedAt    string `json:"updated_at"`
	Envelope     string `json:"envelope"`
	EnvelopeHash string `json:"envelope_hash"`
}

type uploadProgressChunkBatchRequest struct {
	Items []uploadProgressChunkRequest `json:"items"`
}

func (h *ProgressSyncHandler) Upload(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	var req uploadProgressRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	savedCount, err := h.saveUploads(userID, []uploadProgressRequest{req})
	if err != nil {
		return err
	}
	return c.JSON(fiber.Map{
		"status":      "ok",
		"saved_count": savedCount,
	})
}

func (h *ProgressSyncHandler) UploadBatch(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	var req uploadProgressBatchRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	if len(req.Items) == 0 {
		return fiber.NewError(fiber.StatusBadRequest, "items required")
	}
	savedCount, err := h.saveUploads(userID, req.Items)
	if err != nil {
		return err
	}
	return c.JSON(fiber.Map{
		"status":      "ok",
		"saved_count": savedCount,
	})
}

func (h *ProgressSyncHandler) UploadChunksBatch(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	var req uploadProgressChunkBatchRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	if len(req.Items) == 0 {
		return fiber.NewError(fiber.StatusBadRequest, "items required")
	}
	savedCount, err := h.saveChunkUploads(userID, req.Items)
	if err != nil {
		return err
	}
	return c.JSON(fiber.Map{
		"status":      "ok",
		"saved_count": savedCount,
	})
}

func (h *ProgressSyncHandler) saveUploads(
	userID int64,
	items []uploadProgressRequest,
) (int, error) {
	tx, err := h.cfg.Store.DB.Begin()
	if err != nil {
		return 0, fiber.NewError(fiber.StatusInternalServerError, "transaction failed")
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()

	stmt, err := tx.Prepare(
		`INSERT INTO progress_sync
		 (course_id, teacher_user_id, student_user_id, kp_key, lit, lit_percent, question_level, summary_text, summary_raw_response, summary_valid, updated_at, envelope, envelope_hash)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		 ON DUPLICATE KEY UPDATE
		   teacher_user_id = VALUES(teacher_user_id),
		   lit = VALUES(lit),
		   lit_percent = VALUES(lit_percent),
		   question_level = VALUES(question_level),
		   summary_text = VALUES(summary_text),
		   summary_raw_response = VALUES(summary_raw_response),
		   summary_valid = VALUES(summary_valid),
		   updated_at = VALUES(updated_at),
		   envelope = VALUES(envelope),
		   envelope_hash = VALUES(envelope_hash)`,
	)
	if err != nil {
		log.Printf(
			"progress sync statement prepare failed: user_id=%d items=%d error=%v",
			userID,
			len(items),
			err,
		)
		status, message := classifyProgressSyncSaveError(err)
		return 0, fiber.NewError(status, message)
	}
	defer stmt.Close()

	teacherUserIDByCourse := map[int64]int64{}
	enrollmentByCourse := map[int64]bool{}
	savedCount := 0

	for _, item := range items {
		kpKey := strings.TrimSpace(item.KpKey)
		if item.CourseID <= 0 || kpKey == "" || strings.TrimSpace(item.UpdatedAt) == "" {
			return 0, fiber.NewError(fiber.StatusBadRequest, "missing required fields")
		}
		updatedAt, err := parseTime(item.UpdatedAt)
		if err != nil {
			return 0, fiber.NewError(fiber.StatusBadRequest, "updated_at invalid")
		}

		teacherUserID, known := teacherUserIDByCourse[item.CourseID]
		if !known {
			teacherUserID, err = getTeacherUserIDForCourse(h.cfg.Store.DB, item.CourseID)
			if err != nil {
				if errors.Is(err, sql.ErrNoRows) {
					return 0, fiber.NewError(fiber.StatusNotFound, "course not found")
				}
				return 0, fiber.NewError(fiber.StatusInternalServerError, "course lookup failed")
			}
			teacherUserIDByCourse[item.CourseID] = teacherUserID
		}

		enrolled, known := enrollmentByCourse[item.CourseID]
		if !known {
			enrolled, err = isEnrolled(h.cfg.Store.DB, userID, item.CourseID)
			if err != nil {
				return 0, fiber.NewError(fiber.StatusInternalServerError, "enrollment check failed")
			}
			enrollmentByCourse[item.CourseID] = enrolled
		}
		if !enrolled {
			return 0, fiber.NewError(fiber.StatusForbidden, "forbidden")
		}

		litPercent := item.LitPercent
		if litPercent < 0 {
			litPercent = 0
		}
		if litPercent > 100 {
			litPercent = 100
		}
		envelope := strings.TrimSpace(item.Envelope)
		var envelopeBytes []byte
		if envelope != "" {
			decodedEnvelope, err := base64.StdEncoding.DecodeString(envelope)
			if err != nil || len(decodedEnvelope) == 0 {
				return 0, fiber.NewError(fiber.StatusBadRequest, "envelope invalid")
			}
			envelopeBytes = decodedEnvelope
		}

		if _, err := stmt.Exec(
			item.CourseID,
			teacherUserID,
			userID,
			kpKey,
			item.Lit,
			litPercent,
			nullableString(item.QuestionLevel),
			nullableString(item.SummaryText),
			nullableString(item.SummaryRawResponse),
			item.SummaryValid,
			updatedAt,
			envelopeBytes,
			nullableString(item.EnvelopeHash),
		); err != nil {
			log.Printf(
				"progress sync save failed: user_id=%d course_id=%d kp_key=%q updated_at=%q error=%v",
				userID,
				item.CourseID,
				kpKey,
				item.UpdatedAt,
				err,
			)
			status, message := classifyProgressSyncSaveError(err)
			return 0, fiber.NewError(status, message)
		}
		savedCount++
	}

	if err := tx.Commit(); err != nil {
		return 0, fiber.NewError(fiber.StatusInternalServerError, "commit failed")
	}
	committed = true
	return savedCount, nil
}

func (h *ProgressSyncHandler) saveChunkUploads(
	userID int64,
	items []uploadProgressChunkRequest,
) (int, error) {
	tx, err := h.cfg.Store.DB.Begin()
	if err != nil {
		return 0, fiber.NewError(fiber.StatusInternalServerError, "transaction failed")
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()

	stmt, err := tx.Prepare(
		`INSERT INTO progress_sync_chunks
		 (course_id, teacher_user_id, student_user_id, chapter_key, item_count, updated_at, envelope, envelope_hash)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		 ON DUPLICATE KEY UPDATE
		   teacher_user_id = VALUES(teacher_user_id),
		   item_count = VALUES(item_count),
		   updated_at = VALUES(updated_at),
		   envelope = VALUES(envelope),
		   envelope_hash = VALUES(envelope_hash)`,
	)
	if err != nil {
		log.Printf(
			"progress chunk sync statement prepare failed: user_id=%d items=%d error=%v",
			userID,
			len(items),
			err,
		)
		status, message := classifyProgressSyncSaveError(err)
		return 0, fiber.NewError(status, message)
	}
	defer stmt.Close()

	teacherUserIDByCourse := map[int64]int64{}
	enrollmentByCourse := map[int64]bool{}
	savedCount := 0

	for _, item := range items {
		if item.CourseID <= 0 || strings.TrimSpace(item.UpdatedAt) == "" {
			return 0, fiber.NewError(fiber.StatusBadRequest, "missing required fields")
		}
		updatedAt, err := parseTime(item.UpdatedAt)
		if err != nil {
			return 0, fiber.NewError(fiber.StatusBadRequest, "updated_at invalid")
		}
		chapterKey := strings.TrimSpace(item.ChapterKey)
		if chapterKey == "" {
			chapterKey = "ungrouped"
		}
		itemCount := item.ItemCount
		if itemCount < 0 {
			itemCount = 0
		}

		teacherUserID, known := teacherUserIDByCourse[item.CourseID]
		if !known {
			teacherUserID, err = getTeacherUserIDForCourse(h.cfg.Store.DB, item.CourseID)
			if err != nil {
				if errors.Is(err, sql.ErrNoRows) {
					return 0, fiber.NewError(fiber.StatusNotFound, "course not found")
				}
				return 0, fiber.NewError(fiber.StatusInternalServerError, "course lookup failed")
			}
			teacherUserIDByCourse[item.CourseID] = teacherUserID
		}

		enrolled, known := enrollmentByCourse[item.CourseID]
		if !known {
			enrolled, err = isEnrolled(h.cfg.Store.DB, userID, item.CourseID)
			if err != nil {
				return 0, fiber.NewError(fiber.StatusInternalServerError, "enrollment check failed")
			}
			enrollmentByCourse[item.CourseID] = enrolled
		}
		if !enrolled {
			return 0, fiber.NewError(fiber.StatusForbidden, "forbidden")
		}

		envelope := strings.TrimSpace(item.Envelope)
		decodedEnvelope, err := base64.StdEncoding.DecodeString(envelope)
		if err != nil || len(decodedEnvelope) == 0 {
			return 0, fiber.NewError(fiber.StatusBadRequest, "envelope invalid")
		}

		if _, err := stmt.Exec(
			item.CourseID,
			teacherUserID,
			userID,
			chapterKey,
			itemCount,
			updatedAt,
			decodedEnvelope,
			nullableString(item.EnvelopeHash),
		); err != nil {
			log.Printf(
				"progress chunk sync save failed: user_id=%d course_id=%d chapter_key=%q updated_at=%q error=%v",
				userID,
				item.CourseID,
				chapterKey,
				item.UpdatedAt,
				err,
			)
			status, message := classifyProgressSyncSaveError(err)
			return 0, fiber.NewError(status, message)
		}
		savedCount++
	}

	if err := tx.Commit(); err != nil {
		return 0, fiber.NewError(fiber.StatusInternalServerError, "commit failed")
	}
	committed = true
	return savedCount, nil
}

func (h *ProgressSyncHandler) List(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	limit, err := parseLimitQuery(c, 1000, 5000)
	if err != nil {
		return err
	}
	since := strings.TrimSpace(c.Query("since"))
	sinceTime := time.Time{}
	if since != "" {
		parsed, err := parseTime(since)
		if err != nil {
			return fiber.NewError(fiber.StatusBadRequest, "since invalid")
		}
		sinceTime = parsed
	}
	sinceIDRaw := strings.TrimSpace(c.Query("since_id"))
	var sinceID int64
	if sinceIDRaw != "" {
		parsed, err := strconv.ParseInt(sinceIDRaw, 10, 64)
		if err != nil || parsed < 0 {
			return fiber.NewError(fiber.StatusBadRequest, "since_id invalid")
		}
		if since == "" && parsed > 0 {
			return fiber.NewError(fiber.StatusBadRequest, "since_id requires since")
		}
		sinceID = parsed
	}
	query := `SELECT p.id, p.course_id, c.subject, p.teacher_user_id, p.student_user_id, p.kp_key, p.lit, p.lit_percent,
		        p.question_level, p.summary_text, p.summary_raw_response, p.summary_valid, p.updated_at, p.envelope, p.envelope_hash
		 FROM progress_sync p
		 JOIN courses c ON c.id = p.course_id
		 WHERE p.student_user_id = ? AND p.updated_at > ?
		 ORDER BY p.updated_at ASC, p.id ASC
		 LIMIT ?`
	args := []any{userID, sinceTime, limit}
	if sinceID > 0 {
		query = `SELECT p.id, p.course_id, c.subject, p.teacher_user_id, p.student_user_id, p.kp_key, p.lit, p.lit_percent,
		        p.question_level, p.summary_text, p.summary_raw_response, p.summary_valid, p.updated_at, p.envelope, p.envelope_hash
		 FROM progress_sync p
		 JOIN courses c ON c.id = p.course_id
		 WHERE p.student_user_id = ?
		   AND (p.updated_at > ? OR (p.updated_at = ? AND p.id > ?))
		 ORDER BY p.updated_at ASC, p.id ASC
		 LIMIT ?`
		args = []any{userID, sinceTime, sinceTime, sinceID, limit}
	}
	rows, err := h.cfg.Store.DB.Query(query, args...)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "progress sync list failed")
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
			envelopeBytes      []byte
			envelopeHash       sql.NullString
			updatedAt          string
		)
		var updatedAtTime sql.NullTime
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
		); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "progress sync list failed")
		}
		updatedAt = ""
		if updatedAtTime.Valid {
			updatedAt = updatedAtTime.Time.UTC().Format(time.RFC3339)
		}
		encodedEnvelope := ""
		if len(envelopeBytes) > 0 {
			encodedEnvelope = base64.StdEncoding.EncodeToString(envelopeBytes)
		}
		hashValue := ""
		if envelopeHash.Valid {
			hashValue = envelopeHash.String
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
			"envelope":             encodedEnvelope,
			"envelope_hash":        hashValue,
		})
	}
	if err := rows.Err(); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "progress sync list failed")
	}
	return respondJSONWithETag(c, results)
}

func (h *ProgressSyncHandler) ListChunks(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	limit, err := parseLimitQuery(c, 1000, 5000)
	if err != nil {
		return err
	}
	since := strings.TrimSpace(c.Query("since"))
	sinceTime := time.Time{}
	if since != "" {
		parsed, err := parseTime(since)
		if err != nil {
			return fiber.NewError(fiber.StatusBadRequest, "since invalid")
		}
		sinceTime = parsed
	}
	sinceIDRaw := strings.TrimSpace(c.Query("since_id"))
	var sinceID int64
	if sinceIDRaw != "" {
		parsed, err := strconv.ParseInt(sinceIDRaw, 10, 64)
		if err != nil || parsed < 0 {
			return fiber.NewError(fiber.StatusBadRequest, "since_id invalid")
		}
		if since == "" && parsed > 0 {
			return fiber.NewError(fiber.StatusBadRequest, "since_id requires since")
		}
		sinceID = parsed
	}
	query := `SELECT p.id, p.course_id, c.subject, p.teacher_user_id, p.student_user_id, p.chapter_key, p.item_count, p.updated_at, p.envelope, p.envelope_hash
		 FROM progress_sync_chunks p
		 JOIN courses c ON c.id = p.course_id
		 WHERE p.student_user_id = ? AND p.updated_at > ?
		 ORDER BY p.updated_at ASC, p.id ASC
		 LIMIT ?`
	args := []any{userID, sinceTime, limit}
	if sinceID > 0 {
		query = `SELECT p.id, p.course_id, c.subject, p.teacher_user_id, p.student_user_id, p.chapter_key, p.item_count, p.updated_at, p.envelope, p.envelope_hash
		 FROM progress_sync_chunks p
		 JOIN courses c ON c.id = p.course_id
		 WHERE p.student_user_id = ?
		   AND (p.updated_at > ? OR (p.updated_at = ? AND p.id > ?))
		 ORDER BY p.updated_at ASC, p.id ASC
		 LIMIT ?`
		args = []any{userID, sinceTime, sinceTime, sinceID, limit}
	}
	rows, err := h.cfg.Store.DB.Query(query, args...)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "progress chunk sync list failed")
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
		); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "progress chunk sync list failed")
		}
		updatedAt := ""
		if updatedAtTime.Valid {
			updatedAt = updatedAtTime.Time.UTC().Format(time.RFC3339)
		}
		encodedEnvelope := ""
		if len(envelopeBytes) > 0 {
			encodedEnvelope = base64.StdEncoding.EncodeToString(envelopeBytes)
		}
		hashValue := ""
		if envelopeHash.Valid {
			hashValue = envelopeHash.String
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
			"envelope":        encodedEnvelope,
			"envelope_hash":   hashValue,
		})
	}
	if err := rows.Err(); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "progress chunk sync list failed")
	}
	return respondJSONWithETag(c, results)
}

func nullableBoolToInterface(value sql.NullBool) interface{} {
	if !value.Valid {
		return nil
	}
	return value.Bool
}

func classifyProgressSyncSaveError(err error) (int, string) {
	var mysqlErr *mysqlDriver.MySQLError
	if errors.As(err, &mysqlErr) {
		switch mysqlErr.Number {
		case 1048:
			return fiber.StatusBadRequest, "progress sync required field missing"
		case 1265, 1366:
			return fiber.StatusBadRequest, "progress sync payload invalid"
		case 1406:
			return fiber.StatusBadRequest, "progress sync payload too large"
		}
	}
	return fiber.StatusInternalServerError, "progress sync save failed"
}
