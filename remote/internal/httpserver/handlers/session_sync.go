package handlers

import (
	"database/sql"
	"encoding/base64"
	"errors"
	"strconv"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
)

type SessionSyncHandler struct {
	cfg Dependencies
}

func NewSessionSyncHandler(deps Dependencies) *SessionSyncHandler {
	return &SessionSyncHandler{cfg: deps}
}

type uploadSessionRequest struct {
	SessionSyncID string `json:"session_sync_id"`
	CourseID      int64  `json:"course_id"`
	StudentUserID int64  `json:"student_user_id"`
	ChapterKey    string `json:"chapter_key"`
	UpdatedAt     string `json:"updated_at"`
	Envelope      string `json:"envelope"`
	EnvelopeHash  string `json:"envelope_hash"`
}

type uploadSessionBatchRequest struct {
	Items []uploadSessionRequest `json:"items"`
}

func (h *SessionSyncHandler) Upload(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	var req uploadSessionRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	savedCount, err := h.saveUploads(userID, []uploadSessionRequest{req})
	if err != nil {
		return err
	}
	return c.JSON(fiber.Map{
		"status":      "ok",
		"saved_count": savedCount,
	})
}

func (h *SessionSyncHandler) UploadBatch(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	var req uploadSessionBatchRequest
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

func (h *SessionSyncHandler) saveUploads(
	userID int64,
	items []uploadSessionRequest,
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
		`INSERT INTO session_text_sync
		 (session_sync_id, course_id, teacher_user_id, student_user_id, sender_user_id, chapter_key, updated_at, payload_size, envelope, envelope_hash)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		 ON DUPLICATE KEY UPDATE
		   course_id = VALUES(course_id),
		   teacher_user_id = VALUES(teacher_user_id),
		   student_user_id = VALUES(student_user_id),
		   sender_user_id = VALUES(sender_user_id),
		   chapter_key = IF(VALUES(chapter_key) <> '', VALUES(chapter_key), chapter_key),
		   updated_at = VALUES(updated_at),
		   payload_size = VALUES(payload_size),
		   envelope = VALUES(envelope),
		   envelope_hash = VALUES(envelope_hash)`,
	)
	if err != nil {
		return 0, fiber.NewError(fiber.StatusInternalServerError, "session sync save failed")
	}
	defer stmt.Close()

	teacherUserIDByCourse := map[int64]int64{}
	enrollmentByStudentCourse := map[string]bool{}
	savedCount := 0

	for _, item := range items {
		if strings.TrimSpace(item.SessionSyncID) == "" ||
			item.CourseID <= 0 ||
			item.StudentUserID <= 0 ||
			strings.TrimSpace(item.UpdatedAt) == "" ||
			strings.TrimSpace(item.Envelope) == "" {
			return 0, fiber.NewError(fiber.StatusBadRequest, "missing required fields")
		}
		updatedAt, err := parseTime(item.UpdatedAt)
		if err != nil {
			return 0, fiber.NewError(fiber.StatusBadRequest, "updated_at invalid")
		}
		envelopeBytes, err := base64.StdEncoding.DecodeString(item.Envelope)
		if err != nil {
			return 0, fiber.NewError(fiber.StatusBadRequest, "envelope invalid")
		}
		if len(envelopeBytes) == 0 {
			return 0, fiber.NewError(fiber.StatusBadRequest, "envelope invalid")
		}

		teacherUserID, knownTeacher := teacherUserIDByCourse[item.CourseID]
		if !knownTeacher {
			teacherUserID, err = getTeacherUserIDForCourse(h.cfg.Store.DB, item.CourseID)
			if err != nil {
				if errors.Is(err, sql.ErrNoRows) {
					return 0, fiber.NewError(fiber.StatusNotFound, "course not found")
				}
				return 0, fiber.NewError(fiber.StatusInternalServerError, "course lookup failed")
			}
			teacherUserIDByCourse[item.CourseID] = teacherUserID
		}

		if userID != teacherUserID && userID != item.StudentUserID {
			return 0, fiber.NewError(fiber.StatusForbidden, "forbidden")
		}

		var enrolled bool
		if userID == teacherUserID {
			enrollmentKey := strconv.FormatInt(item.StudentUserID, 10) + ":" + strconv.FormatInt(item.CourseID, 10)
			var knownEnrollment bool
			enrolled, knownEnrollment = enrollmentByStudentCourse[enrollmentKey]
			if !knownEnrollment {
				enrolled, err = isEnrolled(h.cfg.Store.DB, item.StudentUserID, item.CourseID)
				if err != nil {
					return 0, fiber.NewError(fiber.StatusInternalServerError, "enrollment check failed")
				}
				enrollmentByStudentCourse[enrollmentKey] = enrolled
			}
			if !enrolled {
				return 0, fiber.NewError(fiber.StatusForbidden, "student not enrolled")
			}
		} else {
			enrollmentKey := strconv.FormatInt(userID, 10) + ":" + strconv.FormatInt(item.CourseID, 10)
			var knownEnrollment bool
			enrolled, knownEnrollment = enrollmentByStudentCourse[enrollmentKey]
			if !knownEnrollment {
				enrolled, err = isEnrolled(h.cfg.Store.DB, userID, item.CourseID)
				if err != nil {
					return 0, fiber.NewError(fiber.StatusInternalServerError, "enrollment check failed")
				}
				enrollmentByStudentCourse[enrollmentKey] = enrolled
			}
			if !enrolled {
				return 0, fiber.NewError(fiber.StatusForbidden, "forbidden")
			}
		}

		chapterKey := strings.TrimSpace(item.ChapterKey)
		if _, err := stmt.Exec(
			strings.TrimSpace(item.SessionSyncID),
			item.CourseID,
			teacherUserID,
			item.StudentUserID,
			userID,
			chapterKey,
			updatedAt,
			len(envelopeBytes),
			envelopeBytes,
			strings.TrimSpace(item.EnvelopeHash),
		); err != nil {
			return 0, fiber.NewError(fiber.StatusInternalServerError, "session sync save failed")
		}
		savedCount++
	}

	if err := tx.Commit(); err != nil {
		return 0, fiber.NewError(fiber.StatusInternalServerError, "commit failed")
	}
	committed = true
	return savedCount, nil
}

func (h *SessionSyncHandler) List(c *fiber.Ctx) error {
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
	query := `SELECT id, session_sync_id, course_id, teacher_user_id, student_user_id, sender_user_id, chapter_key, updated_at, envelope, envelope_hash
		 FROM session_text_sync
		 WHERE (teacher_user_id = ? OR student_user_id = ?) AND updated_at > ?
		 ORDER BY updated_at ASC, id ASC
		 LIMIT ?`
	args := []any{userID, userID, sinceTime, limit}
	if sinceID > 0 {
		query = `SELECT id, session_sync_id, course_id, teacher_user_id, student_user_id, sender_user_id, chapter_key, updated_at, envelope, envelope_hash
		 FROM session_text_sync
		 WHERE (teacher_user_id = ? OR student_user_id = ?)
		   AND (updated_at > ? OR (updated_at = ? AND id > ?))
		 ORDER BY updated_at ASC, id ASC
		 LIMIT ?`
		args = []any{userID, userID, sinceTime, sinceTime, sinceID, limit}
	}
	rows, err := h.cfg.Store.DB.Query(query, args...)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "session sync list failed")
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
		); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "session sync list failed")
		}
		hashValue := ""
		if envelopeHash.Valid {
			hashValue = envelopeHash.String
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
			"envelope_hash":   hashValue,
		})
	}
	if err := rows.Err(); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "session sync list failed")
	}
	return respondJSONWithETag(c, results)
}

func getTeacherUserIDForCourse(db *sql.DB, courseID int64) (int64, error) {
	row := db.QueryRow(
		`SELECT ta.user_id
		 FROM courses c
		 JOIN teacher_accounts ta ON c.teacher_id = ta.id
		 WHERE c.id = ?`,
		courseID,
	)
	var teacherUserID int64
	if err := row.Scan(&teacherUserID); err != nil {
		return 0, err
	}
	return teacherUserID, nil
}

func parseTime(value string) (time.Time, error) {
	if strings.TrimSpace(value) == "" {
		return time.Time{}, errors.New("empty")
	}
	if parsed, err := time.Parse(time.RFC3339, value); err == nil {
		return parsed, nil
	}
	if parsed, err := time.Parse("2006-01-02 15:04:05", value); err == nil {
		return parsed, nil
	}
	return time.Time{}, errors.New("invalid time")
}
