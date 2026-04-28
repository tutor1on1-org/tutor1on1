package handlers

import (
	"database/sql"
	"errors"
	"fmt"
	"strings"

	"github.com/gofiber/fiber/v2"
)

type ModerationHandler struct {
	cfg Dependencies
}

func NewModerationHandler(deps Dependencies) *ModerationHandler {
	return &ModerationHandler{cfg: deps}
}

type updateSubjectLabelRequest struct {
	Name     string `json:"name"`
	IsActive *bool  `json:"is_active"`
}

type assignSubjectAdminRequest struct {
	TeacherUserID int64 `json:"teacher_user_id"`
}

type teacherRegistrationDecisionRequest struct {
	Note string `json:"note"`
}

type courseUploadDecisionRequest struct {
	Note string `json:"note"`
}

type adminUserSummary struct {
	UserID        int64                 `json:"user_id"`
	Username      string                `json:"username"`
	Email         string                `json:"email"`
	Role          string                `json:"role"`
	TeacherID     *int64                `json:"teacher_id"`
	TeacherStatus string                `json:"teacher_status"`
	TeacherLabels []subjectLabelSummary `json:"teacher_subject_labels"`
}

type subjectAdminAssignmentSummary struct {
	TeacherID int64  `json:"teacher_id"`
	UserID    int64  `json:"user_id"`
	Username  string `json:"username"`
}

type adminSubjectLabelSummary struct {
	SubjectLabelID int64                           `json:"subject_label_id"`
	Slug           string                          `json:"slug"`
	Name           string                          `json:"name"`
	IsActive       bool                            `json:"is_active"`
	SubjectAdmins  []subjectAdminAssignmentSummary `json:"subject_admins"`
}

type teacherRegistrationRequestSummary struct {
	RequestID     int64                 `json:"request_id"`
	UserID        int64                 `json:"user_id"`
	TeacherID     int64                 `json:"teacher_id"`
	Username      string                `json:"username"`
	DisplayName   string                `json:"display_name"`
	Status        string                `json:"status"`
	CreatedAt     string                `json:"created_at"`
	SubjectLabels []subjectLabelSummary `json:"subject_labels"`
}

type courseUploadRequestSummary struct {
	RequestID           int64                 `json:"request_id"`
	CourseID            int64                 `json:"course_id"`
	BundleID            int64                 `json:"bundle_id"`
	BundleVersionID     int64                 `json:"bundle_version_id"`
	CourseSubject       string                `json:"course_subject"`
	TeacherID           int64                 `json:"teacher_id"`
	TeacherName         string                `json:"teacher_name"`
	Status              string                `json:"status"`
	RequestedVisibility string                `json:"requested_visibility"`
	CreatedAt           string                `json:"created_at"`
	SubjectLabels       []subjectLabelSummary `json:"subject_labels"`
}

func (h *ModerationHandler) ListAdminUsers(c *fiber.Ctx) error {
	if _, err := requireAdminUserID(c, h.cfg); err != nil {
		return err
	}
	rows, err := h.cfg.Store.DB.Query(
		`SELECT u.id, u.username, u.email,
		        ta.id, ta.status,
		        EXISTS(SELECT 1 FROM admin_accounts aa WHERE aa.user_id = u.id) AS is_admin
		 FROM users u
		 LEFT JOIN teacher_accounts ta ON ta.user_id = u.id
		 WHERE u.status <> 'deleted'
		 ORDER BY u.created_at DESC, u.id DESC`,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "user list failed")
	}
	defer rows.Close()
	results := []adminUserSummary{}
	for rows.Next() {
		var (
			userID        int64
			username      string
			email         string
			teacherID     sql.NullInt64
			teacherStatus sql.NullString
			isAdmin       bool
		)
		if err := rows.Scan(&userID, &username, &email, &teacherID, &teacherStatus, &isAdmin); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "user list failed")
		}
		role := "student"
		var teacherIDPtr *int64
		if isAdmin {
			role = "admin"
		} else if teacherID.Valid {
			teacherIDVal := teacherID.Int64
			teacherIDPtr = &teacherIDVal
			switch strings.TrimSpace(strings.ToLower(teacherStatus.String)) {
			case "active":
				role = "teacher"
			case "rejected":
				role = "teacher_rejected"
			default:
				role = "teacher_pending"
			}
		}
		labels := []subjectLabelSummary{}
		if teacherID.Valid {
			labels, err = listTeacherSubjectLabels(h.cfg.Store.DB, teacherID.Int64)
			if err != nil {
				return fiber.NewError(fiber.StatusInternalServerError, "user labels failed")
			}
		}
		results = append(results, adminUserSummary{
			UserID:        userID,
			Username:      username,
			Email:         email,
			Role:          role,
			TeacherID:     teacherIDPtr,
			TeacherStatus: teacherStatus.String,
			TeacherLabels: labels,
		})
	}
	if err := rows.Err(); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "user list failed")
	}
	return c.JSON(results)
}

func (h *ModerationHandler) DeleteUser(c *fiber.Ctx) error {
	adminUserID, err := requireAdminUserID(c, h.cfg)
	if err != nil {
		return err
	}
	userID, err := parseInt64Param(c, "userId")
	if err != nil {
		return err
	}
	if userID == adminUserID {
		return fiber.NewError(fiber.StatusForbidden, "cannot delete current admin user")
	}

	tx, err := h.cfg.Store.DB.Begin()
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "transaction failed")
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()

	var currentStatus string
	if err := tx.QueryRow(
		"SELECT status FROM users WHERE id = ? LIMIT 1 FOR UPDATE",
		userID,
	).Scan(&currentStatus); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusNotFound, "user not found")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "user lookup failed")
	}

	var targetAdminID int64
	if err := tx.QueryRow(
		"SELECT id FROM admin_accounts WHERE user_id = ? LIMIT 1",
		userID,
	).Scan(&targetAdminID); err == nil {
		return fiber.NewError(fiber.StatusForbidden, "cannot delete admin user")
	} else if !errors.Is(err, sql.ErrNoRows) {
		return fiber.NewError(fiber.StatusInternalServerError, "admin lookup failed")
	}

	deleteSteps := []struct {
		query string
		args  []interface{}
	}{
		{
			query: "UPDATE teacher_accounts SET status = 'rejected' WHERE user_id = ?",
			args:  []interface{}{userID},
		},
		{
			query: "DELETE FROM subject_admin_assignments WHERE teacher_user_id = ?",
			args:  []interface{}{userID},
		},
		{
			query: `UPDATE teacher_registration_requests
			 SET status = 'rejected', resolved_at = NOW(), resolved_by_user_id = ?
			 WHERE user_id = ? AND status = 'pending'`,
			args: []interface{}{adminUserID, userID},
		},
		{
			query: `UPDATE course_upload_requests cur
			 JOIN courses c ON c.id = cur.course_id
			 JOIN teacher_accounts ta ON ta.id = c.teacher_id
			 SET cur.status = 'rejected',
			     cur.resolved_at = NOW(),
			     cur.resolved_by_user_id = ?
			 WHERE ta.user_id = ? AND cur.status = 'pending'`,
			args: []interface{}{adminUserID, userID},
		},
		{
			query: `UPDATE enrollment_requests
			 SET status = 'rejected', resolved_at = NOW()
			 WHERE status = 'pending'
			   AND (student_id = ? OR teacher_id IN (
			     SELECT id FROM teacher_accounts WHERE user_id = ?
			   ))`,
			args: []interface{}{userID, userID},
		},
		{
			query: `UPDATE course_quit_requests
			 SET status = 'rejected', resolved_at = NOW()
			 WHERE status = 'pending'
			   AND (student_id = ? OR teacher_id IN (
			     SELECT id FROM teacher_accounts WHERE user_id = ?
			   ))`,
			args: []interface{}{userID, userID},
		},
		{
			query: `UPDATE enrollments
			 SET status = 'deleted'
			 WHERE status = 'active'
			   AND (student_id = ? OR teacher_id IN (
			     SELECT id FROM teacher_accounts WHERE user_id = ?
			   ))`,
			args: []interface{}{userID, userID},
		},
		{
			query: `DELETE FROM teacher_study_mode_overrides
			 WHERE teacher_user_id = ? OR student_user_id = ?`,
			args: []interface{}{userID, userID},
		},
		{
			query: `UPDATE teacher_study_mode_schedules
			 SET status = 'deleted'
			 WHERE status <> 'deleted'
			   AND (teacher_user_id = ? OR student_user_id = ?)`,
			args: []interface{}{userID, userID},
		},
		{
			query: "UPDATE devices SET status = 'deleted' WHERE user_id = ?",
			args:  []interface{}{userID},
		},
		{
			query: "UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = ? AND revoked_at IS NULL",
			args:  []interface{}{userID},
		},
		{
			query: "UPDATE app_user_devices SET auth_session_nonce = NULL WHERE user_id = ?",
			args:  []interface{}{userID},
		},
	}
	for _, step := range deleteSteps {
		if _, err := tx.Exec(step.query, step.args...); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "user delete failed")
		}
	}

	result, err := tx.Exec("UPDATE users SET status = 'deleted' WHERE id = ? AND status <> 'deleted'", userID)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "user delete failed")
	}
	if !strings.EqualFold(strings.TrimSpace(currentStatus), "deleted") {
		affected, err := result.RowsAffected()
		if err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "user delete failed")
		}
		if affected == 0 {
			return fiber.NewError(fiber.StatusInternalServerError, "user delete failed")
		}
	}
	if err := tx.Commit(); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "commit failed")
	}
	committed = true
	return c.JSON(fiber.Map{"status": "deleted", "user_id": userID})
}

func (h *ModerationHandler) ListSubjectLabels(c *fiber.Ctx) error {
	if _, err := requireAdminUserID(c, h.cfg); err != nil {
		return err
	}
	baseLabels, err := listAllSubjectLabels(h.cfg.Store.DB)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "subject labels failed")
	}
	results := make([]adminSubjectLabelSummary, 0, len(baseLabels))
	for _, label := range baseLabels {
		assignments, err := h.listSubjectAdminAssignments(label.ID)
		if err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "subject admins failed")
		}
		results = append(results, adminSubjectLabelSummary{
			SubjectLabelID: label.ID,
			Slug:           label.Slug,
			Name:           label.Name,
			IsActive:       label.IsActive,
			SubjectAdmins:  assignments,
		})
	}
	return c.JSON(results)
}

func (h *ModerationHandler) ListAvailableSubjectLabels(c *fiber.Ctx) error {
	labels, err := listAllSubjectLabels(h.cfg.Store.DB)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "subject labels failed")
	}
	filtered := make([]subjectLabelSummary, 0, len(labels))
	for _, label := range labels {
		if !label.IsActive {
			continue
		}
		filtered = append(filtered, label)
	}
	return c.JSON(filtered)
}

func (h *ModerationHandler) CreateSubjectLabel(c *fiber.Ctx) error {
	if _, err := requireAdminUserID(c, h.cfg); err != nil {
		return err
	}
	var req updateSubjectLabelRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	name := strings.TrimSpace(req.Name)
	if name == "" {
		return fiber.NewError(fiber.StatusBadRequest, "name required")
	}
	slug := buildSubjectLabelSlug(name)
	active := true
	if req.IsActive != nil {
		active = *req.IsActive
	}
	result, err := h.cfg.Store.DB.Exec(
		`INSERT INTO subject_labels (slug, name, is_active)
		 VALUES (?, ?, ?)`,
		slug,
		name,
		active,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "subject label create failed")
	}
	labelID, err := result.LastInsertId()
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "subject label create failed")
	}
	return c.JSON(fiber.Map{
		"subject_label_id": labelID,
		"slug":             slug,
		"name":             name,
		"is_active":        active,
	})
}

func (h *ModerationHandler) UpdateSubjectLabel(c *fiber.Ctx) error {
	if _, err := requireAdminUserID(c, h.cfg); err != nil {
		return err
	}
	labelID, err := parseInt64Param(c, "id")
	if err != nil {
		return err
	}
	var req updateSubjectLabelRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	name := strings.TrimSpace(req.Name)
	if name == "" {
		return fiber.NewError(fiber.StatusBadRequest, "name required")
	}
	active := true
	if req.IsActive != nil {
		active = *req.IsActive
	}
	result, err := h.cfg.Store.DB.Exec(
		`UPDATE subject_labels
		 SET slug = ?, name = ?, is_active = ?
		 WHERE id = ?`,
		buildSubjectLabelSlug(name),
		name,
		active,
		labelID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "subject label update failed")
	}
	affected, err := result.RowsAffected()
	if err != nil || affected == 0 {
		return fiber.NewError(fiber.StatusNotFound, "subject label not found")
	}
	return c.JSON(fiber.Map{"status": "updated"})
}

func (h *ModerationHandler) AssignSubjectAdmin(c *fiber.Ctx) error {
	if _, err := requireAdminUserID(c, h.cfg); err != nil {
		return err
	}
	labelID, err := parseInt64Param(c, "id")
	if err != nil {
		return err
	}
	var req assignSubjectAdminRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	if req.TeacherUserID <= 0 {
		return fiber.NewError(fiber.StatusBadRequest, "teacher_user_id required")
	}
	if _, err := getTeacherAccountID(h.cfg.Store.DB, req.TeacherUserID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusBadRequest, "teacher account required")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "teacher lookup failed")
	}
	if _, err := h.cfg.Store.DB.Exec(
		`INSERT INTO subject_admin_assignments (subject_label_id, teacher_user_id)
		 VALUES (?, ?)`,
		labelID,
		req.TeacherUserID,
	); err != nil && !isDuplicateEntryError(err) {
		return fiber.NewError(fiber.StatusBadRequest, "subject admin assign failed")
	}
	return c.JSON(fiber.Map{"status": "assigned"})
}

func (h *ModerationHandler) RemoveSubjectAdmin(c *fiber.Ctx) error {
	if _, err := requireAdminUserID(c, h.cfg); err != nil {
		return err
	}
	labelID, err := parseInt64Param(c, "id")
	if err != nil {
		return err
	}
	userID, err := parseInt64Param(c, "userId")
	if err != nil {
		return err
	}
	if _, err := getTeacherAccountID(h.cfg.Store.DB, userID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusBadRequest, "teacher account required")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "teacher lookup failed")
	}
	if _, err := h.cfg.Store.DB.Exec(
		`DELETE FROM subject_admin_assignments
		 WHERE subject_label_id = ? AND teacher_user_id = ?`,
		labelID,
		userID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "subject admin remove failed")
	}
	return c.JSON(fiber.Map{"status": "removed"})
}

func (h *ModerationHandler) ListAdminTeacherRegistrationRequests(c *fiber.Ctx) error {
	if _, err := requireAdminUserID(c, h.cfg); err != nil {
		return err
	}
	results, err := h.listTeacherRegistrationRequests("")
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "teacher requests failed")
	}
	return c.JSON(results)
}

func (h *ModerationHandler) ListSubjectAdminTeacherRegistrationRequests(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	filter := fmt.Sprintf(
		`EXISTS (
			SELECT 1
			FROM teacher_subject_labels tsl
			JOIN subject_admin_assignments saa
			  ON saa.subject_label_id = tsl.subject_label_id
			WHERE tsl.teacher_id = tr.teacher_id
			  AND saa.teacher_user_id = %d
		)`,
		userID,
	)
	results, err := h.listTeacherRegistrationRequests(filter)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "teacher requests failed")
	}
	return c.JSON(results)
}

func (h *ModerationHandler) ApproveTeacherRegistration(c *fiber.Ctx) error {
	userID, requestID, _, admin, err := h.resolveTeacherRegistrationDecisionActor(c)
	if err != nil {
		return err
	}
	tx, err := h.cfg.Store.DB.Begin()
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "transaction failed")
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()
	var applicantUserID int64
	var teacherID int64
	var status string
	row := tx.QueryRow(
		`SELECT user_id, teacher_id, status
		 FROM teacher_registration_requests
		 WHERE id = ?
		 LIMIT 1`,
		requestID,
	)
	if scanErr := row.Scan(&applicantUserID, &teacherID, &status); scanErr != nil {
		if errors.Is(scanErr, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusNotFound, "teacher request not found")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "teacher request lookup failed")
	}
	if status == "approved" {
		return c.JSON(fiber.Map{"status": "approved"})
	}
	if status == "rejected" {
		return fiber.NewError(fiber.StatusConflict, "teacher request already rejected")
	}
	if !admin {
		ok, accessErr := isSubjectAdminForTeacherRequest(h.cfg.Store.DB, requestID, userID)
		if accessErr != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "subject admin lookup failed")
		}
		if !ok {
			return fiber.NewError(fiber.StatusForbidden, "subject admin required")
		}
		if _, err := tx.Exec(
			`INSERT INTO teacher_registration_votes (request_id, subject_admin_user_id, decision)
			 VALUES (?, ?, 'approved')
			 ON DUPLICATE KEY UPDATE decision = VALUES(decision), created_at = CURRENT_TIMESTAMP`,
			requestID,
			userID,
		); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "teacher vote save failed")
		}
	}
	if _, err := tx.Exec(
		"UPDATE teacher_accounts SET status = 'active' WHERE id = ?",
		teacherID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "teacher activate failed")
	}
	if _, err := tx.Exec(
		`UPDATE teacher_registration_requests
		 SET status = 'approved', resolved_at = NOW(), resolved_by_user_id = ?
		 WHERE id = ?`,
		userID,
		requestID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "teacher request update failed")
	}
	if err := notifyUserApprovalDecision(h.cfg, tx, applicantUserID, true); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "commit failed")
	}
	committed = true
	return c.JSON(fiber.Map{"status": "approved"})
}

func (h *ModerationHandler) RejectTeacherRegistration(c *fiber.Ctx) error {
	userID, requestID, _, admin, err := h.resolveTeacherRegistrationDecisionActor(c)
	if err != nil {
		return err
	}
	tx, err := h.cfg.Store.DB.Begin()
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "transaction failed")
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()
	var applicantUserID int64
	var teacherID int64
	var status string
	row := tx.QueryRow(
		`SELECT user_id, teacher_id, status
		 FROM teacher_registration_requests
		 WHERE id = ?
		 LIMIT 1`,
		requestID,
	)
	if scanErr := row.Scan(&applicantUserID, &teacherID, &status); scanErr != nil {
		if errors.Is(scanErr, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusNotFound, "teacher request not found")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "teacher request lookup failed")
	}
	if status == "approved" {
		return fiber.NewError(fiber.StatusConflict, "teacher request already approved")
	}
	if status == "rejected" {
		return c.JSON(fiber.Map{"status": "rejected"})
	}
	if !admin {
		ok, accessErr := isSubjectAdminForTeacherRequest(h.cfg.Store.DB, requestID, userID)
		if accessErr != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "subject admin lookup failed")
		}
		if !ok {
			return fiber.NewError(fiber.StatusForbidden, "subject admin required")
		}
		if _, err := tx.Exec(
			`INSERT INTO teacher_registration_votes (request_id, subject_admin_user_id, decision)
			 VALUES (?, ?, 'rejected')
			 ON DUPLICATE KEY UPDATE decision = VALUES(decision), created_at = CURRENT_TIMESTAMP`,
			requestID,
			userID,
		); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "teacher vote save failed")
		}
	}
	if _, err := tx.Exec(
		"UPDATE teacher_accounts SET status = 'rejected' WHERE id = ?",
		teacherID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "teacher reject failed")
	}
	if _, err := tx.Exec(
		`UPDATE teacher_registration_requests
		 SET status = 'rejected', resolved_at = NOW(), resolved_by_user_id = ?
		 WHERE id = ?`,
		userID,
		requestID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "teacher request update failed")
	}
	if err := notifyUserApprovalDecision(h.cfg, tx, applicantUserID, false); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "commit failed")
	}
	committed = true
	return c.JSON(fiber.Map{"status": "rejected"})
}

func (h *ModerationHandler) ListAdminCourseUploadRequests(c *fiber.Ctx) error {
	if _, err := requireAdminUserID(c, h.cfg); err != nil {
		return err
	}
	results, err := h.listCourseUploadRequests("")
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "course upload requests failed")
	}
	return c.JSON(results)
}

func (h *ModerationHandler) ListSubjectAdminCourseUploadRequests(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	filter := fmt.Sprintf(
		`EXISTS (
			SELECT 1
			FROM course_subject_labels csl
			JOIN subject_admin_assignments saa
			  ON saa.subject_label_id = csl.subject_label_id
			WHERE csl.course_id = cur.course_id
			  AND saa.teacher_user_id = %d
		)`,
		userID,
	)
	results, err := h.listCourseUploadRequests(filter)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "course upload requests failed")
	}
	return c.JSON(results)
}

func (h *ModerationHandler) ApproveCourseUpload(c *fiber.Ctx) error {
	userID, requestID, _, admin, err := h.resolveCourseUploadDecisionActor(c)
	if err != nil {
		return err
	}
	tx, err := h.cfg.Store.DB.Begin()
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "transaction failed")
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()
	var (
		courseID            int64
		status              string
		requestedVisibility string
	)
	row := tx.QueryRow(
		`SELECT course_id, status, requested_visibility
		 FROM course_upload_requests
		 WHERE id = ?
		 LIMIT 1`,
		requestID,
	)
	if scanErr := row.Scan(&courseID, &status, &requestedVisibility); scanErr != nil {
		if errors.Is(scanErr, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusNotFound, "course upload request not found")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "course upload lookup failed")
	}
	if status == "approved" {
		return c.JSON(fiber.Map{"status": "approved"})
	}
	if status == "rejected" {
		return fiber.NewError(fiber.StatusConflict, "course upload request already rejected")
	}
	if !admin {
		ok, accessErr := isSubjectAdminForCourseRequest(h.cfg.Store.DB, requestID, userID)
		if accessErr != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "subject admin lookup failed")
		}
		if !ok {
			return fiber.NewError(fiber.StatusForbidden, "subject admin required")
		}
		if _, err := tx.Exec(
			`INSERT INTO course_upload_votes (request_id, subject_admin_user_id, decision)
			 VALUES (?, ?, 'approved')
			 ON DUPLICATE KEY UPDATE decision = VALUES(decision), created_at = CURRENT_TIMESTAMP`,
			requestID,
			userID,
		); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "course vote save failed")
		}
	}
	if _, err := tx.Exec(
		`UPDATE course_catalog_entries
		 SET approval_status = 'approved',
		     visibility = ?,
		     published_at = CASE
		       WHEN ? IN ('public', 'unlisted') THEN NOW()
		       ELSE NULL
		     END
		 WHERE course_id = ?`,
		requestedVisibility,
		requestedVisibility,
		courseID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "course approval update failed")
	}
	if _, err := tx.Exec(
		`UPDATE course_upload_requests
		 SET status = 'approved', resolved_at = NOW(), resolved_by_user_id = ?
		 WHERE id = ?`,
		userID,
		requestID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "course request update failed")
	}
	if err := notifyCourseOwnerApprovalDecision(h.cfg, tx, courseID, true); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "commit failed")
	}
	committed = true
	return c.JSON(fiber.Map{"status": "approved"})
}

func (h *ModerationHandler) RejectCourseUpload(c *fiber.Ctx) error {
	userID, requestID, _, admin, err := h.resolveCourseUploadDecisionActor(c)
	if err != nil {
		return err
	}
	tx, err := h.cfg.Store.DB.Begin()
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "transaction failed")
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()
	var courseID int64
	var status string
	row := tx.QueryRow(
		`SELECT course_id, status
		 FROM course_upload_requests
		 WHERE id = ?
		 LIMIT 1`,
		requestID,
	)
	if scanErr := row.Scan(&courseID, &status); scanErr != nil {
		if errors.Is(scanErr, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusNotFound, "course upload request not found")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "course upload lookup failed")
	}
	if status == "approved" {
		return fiber.NewError(fiber.StatusConflict, "course upload request already approved")
	}
	if status == "rejected" {
		return c.JSON(fiber.Map{"status": "rejected"})
	}
	if !admin {
		ok, accessErr := isSubjectAdminForCourseRequest(h.cfg.Store.DB, requestID, userID)
		if accessErr != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "subject admin lookup failed")
		}
		if !ok {
			return fiber.NewError(fiber.StatusForbidden, "subject admin required")
		}
		if _, err := tx.Exec(
			`INSERT INTO course_upload_votes (request_id, subject_admin_user_id, decision)
			 VALUES (?, ?, 'rejected')
			 ON DUPLICATE KEY UPDATE decision = VALUES(decision), created_at = CURRENT_TIMESTAMP`,
			requestID,
			userID,
		); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "course vote save failed")
		}
	}
	if _, err := tx.Exec(
		`UPDATE course_upload_requests
		 SET status = 'rejected', resolved_at = NOW(), resolved_by_user_id = ?
		 WHERE id = ?`,
		userID,
		requestID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "course reject failed")
	}
	if err := notifyCourseOwnerApprovalDecision(h.cfg, tx, courseID, false); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "commit failed")
	}
	committed = true
	return c.JSON(fiber.Map{"status": "rejected"})
}

func (h *ModerationHandler) resolveTeacherRegistrationDecisionActor(c *fiber.Ctx) (int64, int64, int64, bool, error) {
	requestID, err := parseInt64Param(c, "id")
	if err != nil {
		return 0, 0, 0, false, err
	}
	userID, authErr := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if authErr != nil {
		return 0, 0, 0, false, fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	admin, err := isAdminUser(h.cfg.Store.DB, userID)
	if err != nil {
		return 0, 0, 0, false, fiber.NewError(fiber.StatusInternalServerError, "admin lookup failed")
	}
	if admin {
		return userID, requestID, 0, true, nil
	}
	subjectAdminTeacherID, err := getTeacherAccountID(h.cfg.Store.DB, userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return 0, 0, 0, false, fiber.NewError(fiber.StatusForbidden, "subject admin required")
		}
		return 0, 0, 0, false, fiber.NewError(fiber.StatusInternalServerError, "teacher lookup failed")
	}
	return userID, requestID, subjectAdminTeacherID, false, nil
}

func (h *ModerationHandler) resolveCourseUploadDecisionActor(c *fiber.Ctx) (int64, int64, int64, bool, error) {
	requestID, err := parseInt64Param(c, "id")
	if err != nil {
		return 0, 0, 0, false, err
	}
	userID, authErr := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if authErr != nil {
		return 0, 0, 0, false, fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	admin, err := isAdminUser(h.cfg.Store.DB, userID)
	if err != nil {
		return 0, 0, 0, false, fiber.NewError(fiber.StatusInternalServerError, "admin lookup failed")
	}
	if admin {
		return userID, requestID, 0, true, nil
	}
	subjectAdminTeacherID, err := getTeacherAccountID(h.cfg.Store.DB, userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return 0, 0, 0, false, fiber.NewError(fiber.StatusForbidden, "subject admin required")
		}
		return 0, 0, 0, false, fiber.NewError(fiber.StatusInternalServerError, "teacher lookup failed")
	}
	return userID, requestID, subjectAdminTeacherID, false, nil
}

func (h *ModerationHandler) listTeacherRegistrationRequests(extraFilter string) ([]teacherRegistrationRequestSummary, error) {
	query := `SELECT tr.id, tr.user_id, tr.teacher_id, u.username, ta.display_name, tr.status, tr.created_at
	          FROM teacher_registration_requests tr
	          JOIN users u ON u.id = tr.user_id
	          JOIN teacher_accounts ta ON ta.id = tr.teacher_id
	          WHERE tr.status = 'pending'`
	if strings.TrimSpace(extraFilter) != "" {
		query += " AND " + extraFilter
	}
	query += " ORDER BY tr.created_at ASC, tr.id ASC"
	rows, err := h.cfg.Store.DB.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	results := []teacherRegistrationRequestSummary{}
	for rows.Next() {
		var item teacherRegistrationRequestSummary
		var createdAt sql.NullTime
		if err := rows.Scan(
			&item.RequestID,
			&item.UserID,
			&item.TeacherID,
			&item.Username,
			&item.DisplayName,
			&item.Status,
			&createdAt,
		); err != nil {
			return nil, err
		}
		if createdAt.Valid {
			item.CreatedAt = createdAt.Time.Format(timeLayout)
		}
		item.SubjectLabels, err = listTeacherSubjectLabels(h.cfg.Store.DB, item.TeacherID)
		if err != nil {
			return nil, err
		}
		results = append(results, item)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return results, nil
}

func (h *ModerationHandler) listCourseUploadRequests(extraFilter string) ([]courseUploadRequestSummary, error) {
	query := `SELECT cur.id, cur.course_id, cur.bundle_id, cur.bundle_version_id,
	                 c.subject, ta.id, ta.display_name, cur.status, cur.requested_visibility, cur.created_at
	          FROM course_upload_requests cur
	          JOIN courses c ON c.id = cur.course_id
	          JOIN teacher_accounts ta ON ta.id = c.teacher_id
	          WHERE cur.status = 'pending'`
	if strings.TrimSpace(extraFilter) != "" {
		query += " AND " + extraFilter
	}
	query += " ORDER BY cur.created_at ASC, cur.id ASC"
	rows, err := h.cfg.Store.DB.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	results := []courseUploadRequestSummary{}
	for rows.Next() {
		var item courseUploadRequestSummary
		var createdAt sql.NullTime
		if err := rows.Scan(
			&item.RequestID,
			&item.CourseID,
			&item.BundleID,
			&item.BundleVersionID,
			&item.CourseSubject,
			&item.TeacherID,
			&item.TeacherName,
			&item.Status,
			&item.RequestedVisibility,
			&createdAt,
		); err != nil {
			return nil, err
		}
		if createdAt.Valid {
			item.CreatedAt = createdAt.Time.Format(timeLayout)
		}
		item.SubjectLabels, err = listCourseSubjectLabels(h.cfg.Store.DB, item.CourseID)
		if err != nil {
			return nil, err
		}
		results = append(results, item)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return results, nil
}

func (h *ModerationHandler) listSubjectAdminAssignments(labelID int64) ([]subjectAdminAssignmentSummary, error) {
	rows, err := h.cfg.Store.DB.Query(
		`SELECT ta.id, u.id, u.username
		 FROM subject_admin_assignments saa
		 JOIN users u ON u.id = saa.teacher_user_id
		 JOIN teacher_accounts ta ON ta.user_id = u.id
		 WHERE saa.subject_label_id = ?
		 ORDER BY u.username ASC, u.id ASC`,
		labelID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	results := []subjectAdminAssignmentSummary{}
	for rows.Next() {
		var item subjectAdminAssignmentSummary
		if err := rows.Scan(&item.TeacherID, &item.UserID, &item.Username); err != nil {
			return nil, err
		}
		results = append(results, item)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return results, nil
}

func buildSubjectLabelSlug(name string) string {
	normalized := strings.TrimSpace(strings.ToLower(name))
	var builder strings.Builder
	lastDash := false
	for _, r := range normalized {
		switch {
		case r >= 'a' && r <= 'z':
			builder.WriteRune(r)
			lastDash = false
		case r >= '0' && r <= '9':
			builder.WriteRune(r)
			lastDash = false
		default:
			if builder.Len() == 0 || lastDash {
				continue
			}
			builder.WriteRune('-')
			lastDash = true
		}
	}
	slug := strings.Trim(builder.String(), "-")
	if slug == "" {
		return "label"
	}
	return slug
}
