package handlers

import (
	"database/sql"
	"errors"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
)

type EnrollmentHandler struct {
	cfg Dependencies
}

func NewEnrollmentHandler(deps Dependencies) *EnrollmentHandler {
	return &EnrollmentHandler{cfg: deps}
}

type enrollmentRequestPayload struct {
	CourseID int64  `json:"course_id"`
	Message  string `json:"message"`
}

func (h *EnrollmentHandler) CreateRequest(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTSecret)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	isTeacher, _, err := isTeacherAccount(h.cfg.Store.DB, userID)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "role lookup failed")
	}
	if isTeacher {
		return fiber.NewError(fiber.StatusForbidden, "student account required")
	}
	var req enrollmentRequestPayload
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	if req.CourseID <= 0 {
		return fiber.NewError(fiber.StatusBadRequest, "course_id required")
	}
	message := strings.TrimSpace(req.Message)

	var (
		teacherID  int64
		visibility string
	)
	row := h.cfg.Store.DB.QueryRow(
		`SELECT c.teacher_id, ce.visibility
		 FROM courses c
		 JOIN course_catalog_entries ce ON ce.course_id = c.id
		 WHERE c.id = ? LIMIT 1`,
		req.CourseID,
	)
	if err := row.Scan(&teacherID, &visibility); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusNotFound, "course not found")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "course lookup failed")
	}
	if visibility == "private" {
		return fiber.NewError(fiber.StatusForbidden, "course not available")
	}

	if enrolled, err := h.isEnrolled(userID, req.CourseID, teacherID); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "enrollment check failed")
	} else if enrolled {
		return fiber.NewError(fiber.StatusConflict, "already enrolled")
	}

	var pendingID int64
	row = h.cfg.Store.DB.QueryRow(
		`SELECT id FROM enrollment_requests
		 WHERE student_id = ? AND course_id = ? AND status = 'pending'
		 LIMIT 1`,
		userID, req.CourseID,
	)
	if err := row.Scan(&pendingID); err == nil {
		return fiber.NewError(fiber.StatusConflict, "request already pending")
	} else if err != sql.ErrNoRows {
		return fiber.NewError(fiber.StatusInternalServerError, "request lookup failed")
	}

	result, err := h.cfg.Store.DB.Exec(
		`INSERT INTO enrollment_requests (student_id, teacher_id, course_id, message, status)
		 VALUES (?, ?, ?, ?, 'pending')`,
		userID,
		teacherID,
		req.CourseID,
		nullableString(message),
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "request insert failed")
	}
	requestID, _ := result.LastInsertId()
	return c.JSON(fiber.Map{
		"request_id": requestID,
		"status":     "pending",
	})
}

func (h *EnrollmentHandler) ListStudentRequests(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTSecret)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	rows, err := h.cfg.Store.DB.Query(
		`SELECT er.id, er.course_id, er.status, er.message, er.created_at, er.resolved_at,
		        c.subject, t.id, t.display_name
		 FROM enrollment_requests er
		 JOIN courses c ON er.course_id = c.id
		 JOIN teacher_accounts t ON er.teacher_id = t.id
		 WHERE er.student_id = ?
		 ORDER BY er.created_at DESC`,
		userID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "request list failed")
	}
	defer rows.Close()

	type requestSummary struct {
		RequestID   int64  `json:"request_id"`
		CourseID    int64  `json:"course_id"`
		Status      string `json:"status"`
		Message     string `json:"message"`
		CreatedAt   string `json:"created_at"`
		ResolvedAt  string `json:"resolved_at"`
		CourseName  string `json:"course_subject"`
		TeacherID   int64  `json:"teacher_id"`
		TeacherName string `json:"teacher_name"`
	}

	results := []requestSummary{}
	for rows.Next() {
		var (
			id         int64
			courseID   int64
			status     string
			message    sql.NullString
			createdAt  time.Time
			resolvedAt sql.NullTime
			subject    string
			teacherID  int64
			teacherName string
		)
		if err := rows.Scan(
			&id,
			&courseID,
			&status,
			&message,
			&createdAt,
			&resolvedAt,
			&subject,
			&teacherID,
			&teacherName,
		); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "request list failed")
		}
		resolved := ""
		if resolvedAt.Valid {
			resolved = resolvedAt.Time.Format(timeLayout)
		}
		results = append(results, requestSummary{
			RequestID:   id,
			CourseID:    courseID,
			Status:      status,
			Message:     message.String,
			CreatedAt:   createdAt.Format(timeLayout),
			ResolvedAt:  resolved,
			CourseName:  subject,
			TeacherID:   teacherID,
			TeacherName: teacherName,
		})
	}
	return c.JSON(results)
}

func (h *EnrollmentHandler) ListEnrollments(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTSecret)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	rows, err := h.cfg.Store.DB.Query(
		`SELECT e.id, e.course_id, e.teacher_id, e.status, e.assigned_at,
		        c.subject, t.display_name
		 FROM enrollments e
		 JOIN courses c ON e.course_id = c.id
		 JOIN teacher_accounts t ON e.teacher_id = t.id
		 WHERE e.student_id = ? AND e.status = 'active'
		 ORDER BY e.assigned_at DESC`,
		userID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "enrollment list failed")
	}
	defer rows.Close()

	type enrollmentSummary struct {
		EnrollmentID int64  `json:"enrollment_id"`
		CourseID     int64  `json:"course_id"`
		TeacherID    int64  `json:"teacher_id"`
		Status       string `json:"status"`
		AssignedAt   string `json:"assigned_at"`
		CourseName   string `json:"course_subject"`
		TeacherName  string `json:"teacher_name"`
	}

	results := []enrollmentSummary{}
	for rows.Next() {
		var (
			id        int64
			courseID  int64
			teacherID int64
			status    string
			assigned  time.Time
			subject   string
			teacherName string
		)
		if err := rows.Scan(
			&id,
			&courseID,
			&teacherID,
			&status,
			&assigned,
			&subject,
			&teacherName,
		); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "enrollment list failed")
		}
		results = append(results, enrollmentSummary{
			EnrollmentID: id,
			CourseID:     courseID,
			TeacherID:    teacherID,
			Status:       status,
			AssignedAt:   assigned.Format(timeLayout),
			CourseName:   subject,
			TeacherName:  teacherName,
		})
	}
	return c.JSON(results)
}

func (h *EnrollmentHandler) ListTeacherRequests(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTSecret)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	teacherID, err := getTeacherAccountID(h.cfg.Store.DB, userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusForbidden, "teacher account required")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "teacher lookup failed")
	}
	rows, err := h.cfg.Store.DB.Query(
		`SELECT er.id, er.course_id, er.student_id, er.message, er.status, er.created_at,
		        u.username, c.subject
		 FROM enrollment_requests er
		 JOIN users u ON er.student_id = u.id
		 JOIN courses c ON er.course_id = c.id
		 WHERE er.teacher_id = ? AND er.status = 'pending'
		 ORDER BY er.created_at ASC`,
		teacherID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "request list failed")
	}
	defer rows.Close()

	type teacherRequest struct {
		RequestID   int64  `json:"request_id"`
		CourseID    int64  `json:"course_id"`
		StudentID   int64  `json:"student_id"`
		StudentName string `json:"student_username"`
		Message     string `json:"message"`
		Status      string `json:"status"`
		CreatedAt   string `json:"created_at"`
		CourseName  string `json:"course_subject"`
	}

	results := []teacherRequest{}
	for rows.Next() {
		var (
			id        int64
			courseID  int64
			studentID int64
			message   sql.NullString
			status    string
			createdAt time.Time
			studentName string
			subject   string
		)
		if err := rows.Scan(
			&id,
			&courseID,
			&studentID,
			&message,
			&status,
			&createdAt,
			&studentName,
			&subject,
		); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "request list failed")
		}
		results = append(results, teacherRequest{
			RequestID:   id,
			CourseID:    courseID,
			StudentID:   studentID,
			StudentName: studentName,
			Message:     message.String,
			Status:      status,
			CreatedAt:   createdAt.Format(timeLayout),
			CourseName:  subject,
		})
	}
	return c.JSON(results)
}

func (h *EnrollmentHandler) ApproveRequest(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTSecret)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	teacherID, err := getTeacherAccountID(h.cfg.Store.DB, userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusForbidden, "teacher account required")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "teacher lookup failed")
	}
	requestID, err := parseInt64Param(c, "id")
	if err != nil {
		return err
	}

	tx, err := h.cfg.Store.DB.Begin()
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "transaction failed")
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	var (
		studentID int64
		courseID  int64
		status    string
	)
	row := tx.QueryRow(
		`SELECT student_id, course_id, status
		 FROM enrollment_requests
		 WHERE id = ? AND teacher_id = ? LIMIT 1`,
		requestID, teacherID,
	)
	if err := row.Scan(&studentID, &courseID, &status); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusNotFound, "request not found")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "request lookup failed")
	}
	if status != "pending" {
		return fiber.NewError(fiber.StatusBadRequest, "request already resolved")
	}
	if _, err := tx.Exec(
		"UPDATE enrollment_requests SET status = 'approved', resolved_at = NOW() WHERE id = ?",
		requestID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "request update failed")
	}
	var existing int64
	row = tx.QueryRow(
		`SELECT id FROM enrollments
		 WHERE student_id = ? AND course_id = ? AND teacher_id = ? AND status = 'active'
		 LIMIT 1`,
		studentID, courseID, teacherID,
	)
	if err := row.Scan(&existing); err != nil {
		if !errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusInternalServerError, "enrollment lookup failed")
		}
		if _, err := tx.Exec(
			`INSERT INTO enrollments (student_id, teacher_id, course_id, status, assigned_at)
			 VALUES (?, ?, ?, 'active', NOW())`,
			studentID, teacherID, courseID,
		); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "enrollment insert failed")
		}
	}
	if err := tx.Commit(); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "commit failed")
	}
	return c.JSON(fiber.Map{"status": "approved"})
}

func (h *EnrollmentHandler) RejectRequest(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTSecret)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	teacherID, err := getTeacherAccountID(h.cfg.Store.DB, userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusForbidden, "teacher account required")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "teacher lookup failed")
	}
	requestID, err := parseInt64Param(c, "id")
	if err != nil {
		return err
	}
	result, err := h.cfg.Store.DB.Exec(
		`UPDATE enrollment_requests
		 SET status = 'rejected', resolved_at = NOW()
		 WHERE id = ? AND teacher_id = ? AND status = 'pending'`,
		requestID, teacherID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "request update failed")
	}
	affected, err := result.RowsAffected()
	if err != nil || affected == 0 {
		return fiber.NewError(fiber.StatusNotFound, "request not found")
	}
	return c.JSON(fiber.Map{"status": "rejected"})
}

func (h *EnrollmentHandler) isEnrolled(studentID int64, courseID int64, teacherID int64) (bool, error) {
	row := h.cfg.Store.DB.QueryRow(
		`SELECT 1 FROM enrollments
		 WHERE student_id = ? AND course_id = ? AND teacher_id = ? AND status = 'active'
		 LIMIT 1`,
		studentID, courseID, teacherID,
	)
	var ok int
	if err := row.Scan(&ok); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return false, nil
		}
		return false, err
	}
	return true, nil
}

