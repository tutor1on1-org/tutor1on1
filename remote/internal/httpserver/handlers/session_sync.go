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
	UpdatedAt     string `json:"updated_at"`
	Envelope      string `json:"envelope"`
	EnvelopeHash  string `json:"envelope_hash"`
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
	if strings.TrimSpace(req.SessionSyncID) == "" ||
		req.CourseID <= 0 ||
		req.StudentUserID <= 0 ||
		strings.TrimSpace(req.UpdatedAt) == "" ||
		strings.TrimSpace(req.Envelope) == "" {
		return fiber.NewError(fiber.StatusBadRequest, "missing required fields")
	}
	updatedAt, err := parseTime(req.UpdatedAt)
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "updated_at invalid")
	}
	envelopeBytes, err := base64.StdEncoding.DecodeString(req.Envelope)
	if err != nil || len(envelopeBytes) == 0 {
		return fiber.NewError(fiber.StatusBadRequest, "envelope invalid")
	}
	teacherUserID, err := getTeacherUserIDForCourse(h.cfg.Store.DB, req.CourseID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusNotFound, "course not found")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "course lookup failed")
	}
	if userID != teacherUserID && userID != req.StudentUserID {
		return fiber.NewError(fiber.StatusForbidden, "forbidden")
	}
	if userID == teacherUserID {
		ok, err := isEnrolled(h.cfg.Store.DB, req.StudentUserID, req.CourseID)
		if err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "enrollment check failed")
		}
		if !ok {
			return fiber.NewError(fiber.StatusForbidden, "student not enrolled")
		}
	} else {
		ok, err := isEnrolled(h.cfg.Store.DB, userID, req.CourseID)
		if err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "enrollment check failed")
		}
		if !ok {
			return fiber.NewError(fiber.StatusForbidden, "forbidden")
		}
	}
	_, err = h.cfg.Store.DB.Exec(
		`INSERT INTO session_text_sync
		 (session_sync_id, course_id, teacher_user_id, student_user_id, sender_user_id, updated_at, payload_size, envelope, envelope_hash)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
		 ON DUPLICATE KEY UPDATE
		   course_id = VALUES(course_id),
		   teacher_user_id = VALUES(teacher_user_id),
		   student_user_id = VALUES(student_user_id),
		   sender_user_id = VALUES(sender_user_id),
		   updated_at = VALUES(updated_at),
		   payload_size = VALUES(payload_size),
		   envelope = VALUES(envelope),
		   envelope_hash = VALUES(envelope_hash)`,
		strings.TrimSpace(req.SessionSyncID),
		req.CourseID,
		teacherUserID,
		req.StudentUserID,
		userID,
		updatedAt,
		len(envelopeBytes),
		envelopeBytes,
		strings.TrimSpace(req.EnvelopeHash),
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "session sync save failed")
	}
	return c.JSON(fiber.Map{"status": "ok"})
}

func (h *SessionSyncHandler) List(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	limit, err := parseLimitQuery(c, 200, 500)
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
	query := `SELECT id, session_sync_id, course_id, teacher_user_id, student_user_id, sender_user_id, updated_at, envelope, envelope_hash
		 FROM session_text_sync
		 WHERE (teacher_user_id = ? OR student_user_id = ?) AND updated_at > ?
		 ORDER BY updated_at ASC, id ASC
		 LIMIT ?`
	args := []any{userID, userID, sinceTime, limit}
	if sinceID > 0 {
		query = `SELECT id, session_sync_id, course_id, teacher_user_id, student_user_id, sender_user_id, updated_at, envelope, envelope_hash
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
