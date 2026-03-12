package handlers

import (
	"database/sql"
	"errors"
	"strconv"
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

type quitRequestPayload struct {
	Reason string `json:"reason"`
}

func (h *EnrollmentHandler) CreateRequest(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
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

func (h *EnrollmentHandler) CreateQuitRequest(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
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
	enrollmentID, err := parseInt64Param(c, "id")
	if err != nil {
		return err
	}
	var req quitRequestPayload
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	reason := strings.TrimSpace(req.Reason)

	var (
		teacherID int64
		courseID  int64
		status    string
	)
	row := h.cfg.Store.DB.QueryRow(
		`SELECT teacher_id, course_id, status
		 FROM enrollments
		 WHERE id = ? AND student_id = ? LIMIT 1`,
		enrollmentID,
		userID,
	)
	if err := row.Scan(&teacherID, &courseID, &status); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusNotFound, "enrollment not found")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "enrollment lookup failed")
	}
	if status != "active" {
		return fiber.NewError(fiber.StatusBadRequest, "enrollment not active")
	}
	var pendingID int64
	row = h.cfg.Store.DB.QueryRow(
		`SELECT id FROM course_quit_requests
		 WHERE student_id = ? AND course_id = ? AND status = 'pending'
		 LIMIT 1`,
		userID, courseID,
	)
	if err := row.Scan(&pendingID); err == nil {
		return fiber.NewError(fiber.StatusConflict, "quit request already pending")
	} else if err != sql.ErrNoRows {
		return fiber.NewError(fiber.StatusInternalServerError, "quit request lookup failed")
	}
	result, err := h.cfg.Store.DB.Exec(
		`INSERT INTO course_quit_requests (student_id, teacher_id, course_id, reason, status)
		 VALUES (?, ?, ?, ?, 'pending')`,
		userID,
		teacherID,
		courseID,
		nullableString(reason),
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "quit request insert failed")
	}
	requestID, _ := result.LastInsertId()
	return c.JSON(fiber.Map{
		"request_id": requestID,
		"status":     "pending",
	})
}

func (h *EnrollmentHandler) ListStudentRequests(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
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
			id          int64
			courseID    int64
			status      string
			message     sql.NullString
			createdAt   time.Time
			resolvedAt  sql.NullTime
			subject     string
			teacherID   int64
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

func (h *EnrollmentHandler) ListStudentQuitRequests(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	rows, err := h.cfg.Store.DB.Query(
		`SELECT qr.id, qr.course_id, qr.status, qr.reason, qr.created_at, qr.resolved_at,
		        c.subject, ta.id, ta.display_name
		 FROM course_quit_requests qr
		 JOIN courses c ON qr.course_id = c.id
		 JOIN teacher_accounts ta ON qr.teacher_id = ta.id
		 WHERE qr.student_id = ?
		 ORDER BY qr.created_at DESC`,
		userID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "quit request list failed")
	}
	defer rows.Close()

	type requestSummary struct {
		RequestID   int64  `json:"request_id"`
		CourseID    int64  `json:"course_id"`
		Status      string `json:"status"`
		Reason      string `json:"reason"`
		CreatedAt   string `json:"created_at"`
		ResolvedAt  string `json:"resolved_at"`
		CourseName  string `json:"course_subject"`
		TeacherID   int64  `json:"teacher_id"`
		TeacherName string `json:"teacher_name"`
	}

	results := []requestSummary{}
	for rows.Next() {
		var (
			id          int64
			courseID    int64
			status      string
			reason      sql.NullString
			createdAt   time.Time
			resolvedAt  sql.NullTime
			subject     string
			teacherID   int64
			teacherName string
		)
		if err := rows.Scan(
			&id,
			&courseID,
			&status,
			&reason,
			&createdAt,
			&resolvedAt,
			&subject,
			&teacherID,
			&teacherName,
		); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "quit request list failed")
		}
		resolved := ""
		if resolvedAt.Valid {
			resolved = resolvedAt.Time.Format(timeLayout)
		}
		results = append(results, requestSummary{
			RequestID:   id,
			CourseID:    courseID,
			Status:      status,
			Reason:      reason.String,
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
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	rows, err := h.cfg.Store.DB.Query(
		`SELECT e.id, e.course_id, t.user_id, e.status, e.assigned_at,
		        c.subject, t.display_name,
		        (
		          SELECT bv.id FROM bundles b
		          JOIN bundle_versions bv ON bv.bundle_id = b.id
		          WHERE b.course_id = e.course_id
		          ORDER BY bv.version DESC, bv.id DESC
		          LIMIT 1
		        ) AS latest_bundle_version_id,
		        (
		          SELECT bv.hash FROM bundles b
		          JOIN bundle_versions bv ON bv.bundle_id = b.id
		          WHERE b.course_id = e.course_id
		          ORDER BY bv.version DESC, bv.id DESC
		          LIMIT 1
		        ) AS latest_bundle_hash,
		        (
		          SELECT bv.oss_path FROM bundles b
		          JOIN bundle_versions bv ON bv.bundle_id = b.id
		          WHERE b.course_id = e.course_id
		          ORDER BY bv.version DESC, bv.id DESC
		          LIMIT 1
		        ) AS latest_bundle_oss_path
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
		EnrollmentID          int64  `json:"enrollment_id"`
		CourseID              int64  `json:"course_id"`
		TeacherID             int64  `json:"teacher_id"`
		Status                string `json:"status"`
		AssignedAt            string `json:"assigned_at"`
		CourseName            string `json:"course_subject"`
		TeacherName           string `json:"teacher_name"`
		LatestBundleVersionID int64  `json:"latest_bundle_version_id"`
		LatestBundleHash      string `json:"latest_bundle_hash"`
	}

	results := []enrollmentSummary{}
	for rows.Next() {
		var (
			id           int64
			courseID     int64
			teacherID    int64
			status       string
			assigned     time.Time
			subject      string
			teacherName  string
			latestBundle sql.NullInt64
			latestHash   sql.NullString
			latestRel    sql.NullString
		)
		if err := rows.Scan(
			&id,
			&courseID,
			&teacherID,
			&status,
			&assigned,
			&subject,
			&teacherName,
			&latestBundle,
			&latestHash,
			&latestRel,
		); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "enrollment list failed")
		}
		resolvedHash, _, _, hashErr := ensureStoredBundleHash(
			h.cfg.Store.DB,
			h.cfg.Storage,
			latestBundle.Int64,
			latestHash.String,
			latestRel.String,
		)
		if hashErr != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "enrollment list failed")
		}
		results = append(results, enrollmentSummary{
			EnrollmentID:          id,
			CourseID:              courseID,
			TeacherID:             teacherID,
			Status:                status,
			AssignedAt:            assigned.Format(timeLayout),
			CourseName:            subject,
			TeacherName:           teacherName,
			LatestBundleVersionID: latestBundle.Int64,
			LatestBundleHash:      resolvedHash,
		})
	}
	if err := rows.Err(); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "enrollment list failed")
	}
	return respondJSONWithETag(c, results)
}

func (h *EnrollmentHandler) ListTeacherRequests(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
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
			id          int64
			courseID    int64
			studentID   int64
			message     sql.NullString
			status      string
			createdAt   time.Time
			studentName string
			subject     string
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

func (h *EnrollmentHandler) ListTeacherQuitRequests(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
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
		`SELECT qr.id, qr.course_id, qr.student_id, qr.reason, qr.status, qr.created_at,
		        u.username, c.subject
		 FROM course_quit_requests qr
		 JOIN users u ON qr.student_id = u.id
		 JOIN courses c ON qr.course_id = c.id
		 WHERE qr.teacher_id = ? AND qr.status = 'pending'
		 ORDER BY qr.created_at ASC`,
		teacherID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "quit request list failed")
	}
	defer rows.Close()

	type teacherQuitRequest struct {
		RequestID   int64  `json:"request_id"`
		CourseID    int64  `json:"course_id"`
		StudentID   int64  `json:"student_id"`
		StudentName string `json:"student_username"`
		Reason      string `json:"reason"`
		Status      string `json:"status"`
		CreatedAt   string `json:"created_at"`
		CourseName  string `json:"course_subject"`
	}

	results := []teacherQuitRequest{}
	for rows.Next() {
		var (
			id          int64
			courseID    int64
			studentID   int64
			reason      sql.NullString
			status      string
			createdAt   time.Time
			studentName string
			subject     string
		)
		if err := rows.Scan(
			&id,
			&courseID,
			&studentID,
			&reason,
			&status,
			&createdAt,
			&studentName,
			&subject,
		); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "quit request list failed")
		}
		results = append(results, teacherQuitRequest{
			RequestID:   id,
			CourseID:    courseID,
			StudentID:   studentID,
			StudentName: studentName,
			Reason:      reason.String,
			Status:      status,
			CreatedAt:   createdAt.Format(timeLayout),
			CourseName:  subject,
		})
	}
	return c.JSON(results)
}

func (h *EnrollmentHandler) ApproveRequest(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
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
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
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

func (h *EnrollmentHandler) ApproveQuitRequest(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
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
		 FROM course_quit_requests
		 WHERE id = ? AND teacher_id = ? LIMIT 1`,
		requestID, teacherID,
	)
	if err := row.Scan(&studentID, &courseID, &status); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusNotFound, "quit request not found")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "quit request lookup failed")
	}
	if status != "pending" {
		return fiber.NewError(fiber.StatusBadRequest, "quit request already resolved")
	}
	if _, err := tx.Exec(
		"UPDATE course_quit_requests SET status = 'approved', resolved_at = NOW() WHERE id = ?",
		requestID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "quit request update failed")
	}
	result, err := tx.Exec(
		`UPDATE enrollments
		 SET status = 'deleted'
		 WHERE student_id = ? AND teacher_id = ? AND course_id = ? AND status = 'active'`,
		studentID, teacherID, courseID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "enrollment update failed")
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "enrollment update failed")
	}
	if affected == 0 {
		return fiber.NewError(fiber.StatusBadRequest, "enrollment not active")
	}
	if _, err := tx.Exec(
		`DELETE FROM session_text_sync WHERE course_id = ? AND student_user_id = ?`,
		courseID, studentID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "session sync delete failed")
	}
	if _, err := tx.Exec(
		`DELETE FROM progress_sync WHERE course_id = ? AND student_user_id = ?`,
		courseID, studentID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "progress sync delete failed")
	}
	if _, err := tx.Exec(
		`DELETE FROM e2ee_events WHERE course_id = ? AND (sender_user_id = ? OR recipient_user_id = ?)`,
		courseID, studentID, studentID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "events delete failed")
	}
	if _, err := tx.Exec(
		`INSERT INTO enrollment_deletion_events (student_id, teacher_user_id, course_id, reason)
		 VALUES (?, ?, ?, 'quit_approved')`,
		studentID, userID, courseID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "deletion event insert failed")
	}
	if err := tx.Commit(); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "commit failed")
	}
	return c.JSON(fiber.Map{"status": "approved"})
}

func (h *EnrollmentHandler) RejectQuitRequest(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
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
		`UPDATE course_quit_requests
		 SET status = 'rejected', resolved_at = NOW()
		 WHERE id = ? AND teacher_id = ? AND status = 'pending'`,
		requestID, teacherID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "quit request update failed")
	}
	affected, err := result.RowsAffected()
	if err != nil || affected == 0 {
		return fiber.NewError(fiber.StatusNotFound, "quit request not found")
	}
	return c.JSON(fiber.Map{"status": "rejected"})
}

func (h *EnrollmentHandler) ListDeletionEvents(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	limit, err := parseLimitQuery(c, 200, 500)
	if err != nil {
		return err
	}
	sinceID := int64(0)
	sinceRaw := strings.TrimSpace(c.Query("since_id"))
	if sinceRaw != "" {
		parsed, err := strconv.ParseInt(sinceRaw, 10, 64)
		if err != nil || parsed < 0 {
			return fiber.NewError(fiber.StatusBadRequest, "since_id invalid")
		}
		sinceID = parsed
	}
	rows, err := h.cfg.Store.DB.Query(
		`SELECT ede.id, ede.student_id, ede.teacher_user_id, ede.course_id, ede.reason, ede.created_at
		 FROM enrollment_deletion_events ede
		 WHERE ede.id > ?
		   AND (ede.student_id = ? OR ede.teacher_user_id = ?)
		   AND NOT EXISTS (
		     SELECT 1 FROM enrollments e
		     WHERE e.student_id = ede.student_id
		       AND e.course_id = ede.course_id
		       AND e.status = 'active'
		   )
		 ORDER BY ede.id ASC
		 LIMIT ?`,
		sinceID, userID, userID, limit,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "deletion event list failed")
	}
	defer rows.Close()

	type deletionEvent struct {
		EventID       int64  `json:"event_id"`
		StudentID     int64  `json:"student_id"`
		TeacherUserID int64  `json:"teacher_user_id"`
		CourseID      int64  `json:"course_id"`
		Reason        string `json:"reason"`
		CreatedAt     string `json:"created_at"`
	}
	results := []deletionEvent{}
	for rows.Next() {
		var (
			eventID       int64
			studentID     int64
			teacherUserID int64
			courseID      int64
			reason        string
			createdAt     time.Time
		)
		if err := rows.Scan(
			&eventID,
			&studentID,
			&teacherUserID,
			&courseID,
			&reason,
			&createdAt,
		); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "deletion event list failed")
		}
		results = append(results, deletionEvent{
			EventID:       eventID,
			StudentID:     studentID,
			TeacherUserID: teacherUserID,
			CourseID:      courseID,
			Reason:        reason,
			CreatedAt:     createdAt.Format(timeLayout),
		})
	}
	if err := rows.Err(); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "deletion event list failed")
	}
	return c.JSON(results)
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
