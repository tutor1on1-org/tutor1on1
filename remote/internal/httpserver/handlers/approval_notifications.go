package handlers

import (
	"database/sql"
	"strings"

	"github.com/gofiber/fiber/v2"
)

type approvalEmailQueryer interface {
	Query(query string, args ...interface{}) (*sql.Rows, error)
}

func notifyTeacherApprovalRequest(
	deps Dependencies,
	queryer approvalEmailQueryer,
	teacherID int64,
) error {
	if !approvalEmailEnabled(deps) {
		return nil
	}
	emails, err := queryApprovalEmails(
		queryer,
		`SELECT u.email
		 FROM teacher_accounts ta
		 JOIN users u ON u.id = ta.user_id
		 WHERE ta.id = ?
		 LIMIT 1`,
		teacherID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "teacher email lookup failed")
	}
	return sendApprovalRequestEmails(deps, emails)
}

func notifySubjectAdminsForTeacherRegistrationRequest(
	deps Dependencies,
	queryer approvalEmailQueryer,
	teacherID int64,
) error {
	if !approvalEmailEnabled(deps) {
		return nil
	}
	emails, err := queryApprovalEmails(
		queryer,
		`SELECT DISTINCT u.email
		 FROM teacher_subject_labels tsl
		 JOIN subject_admin_assignments saa ON saa.subject_label_id = tsl.subject_label_id
		 JOIN users u ON u.id = saa.teacher_user_id
		 WHERE tsl.teacher_id = ?
		   AND u.status <> 'deleted'
		 ORDER BY u.email ASC`,
		teacherID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "subject admin email lookup failed")
	}
	return sendApprovalRequestEmails(deps, emails)
}

func notifySubjectAdminsForCourseUploadRequest(
	deps Dependencies,
	queryer approvalEmailQueryer,
	courseID int64,
) error {
	if !approvalEmailEnabled(deps) {
		return nil
	}
	emails, err := queryApprovalEmails(
		queryer,
		`SELECT DISTINCT u.email
		 FROM course_subject_labels csl
		 JOIN subject_admin_assignments saa ON saa.subject_label_id = csl.subject_label_id
		 JOIN users u ON u.id = saa.teacher_user_id
		 WHERE csl.course_id = ?
		   AND u.status <> 'deleted'
		 ORDER BY u.email ASC`,
		courseID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "subject admin email lookup failed")
	}
	return sendApprovalRequestEmails(deps, emails)
}

func notifyUserApprovalDecision(
	deps Dependencies,
	queryer approvalEmailQueryer,
	userID int64,
	approved bool,
) error {
	if !approvalEmailEnabled(deps) {
		return nil
	}
	emails, err := queryApprovalEmails(
		queryer,
		`SELECT email
		 FROM users
		 WHERE id = ?
		 LIMIT 1`,
		userID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "user email lookup failed")
	}
	return sendApprovalDecisionEmails(deps, emails, approved)
}

func notifyCourseOwnerApprovalDecision(
	deps Dependencies,
	queryer approvalEmailQueryer,
	courseID int64,
	approved bool,
) error {
	if !approvalEmailEnabled(deps) {
		return nil
	}
	emails, err := queryApprovalEmails(
		queryer,
		`SELECT u.email
		 FROM courses c
		 JOIN teacher_accounts ta ON ta.id = c.teacher_id
		 JOIN users u ON u.id = ta.user_id
		 WHERE c.id = ?
		 LIMIT 1`,
		courseID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "teacher email lookup failed")
	}
	return sendApprovalDecisionEmails(deps, emails, approved)
}

func approvalEmailEnabled(deps Dependencies) bool {
	return deps.Mailer != nil && deps.Mailer.Enabled()
}

func queryApprovalEmails(
	queryer approvalEmailQueryer,
	query string,
	args ...interface{},
) ([]string, error) {
	rows, err := queryer.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	emails := []string{}
	for rows.Next() {
		var email string
		if err := rows.Scan(&email); err != nil {
			return nil, err
		}
		emails = append(emails, email)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return dedupeApprovalEmails(emails), nil
}

func sendApprovalRequestEmails(deps Dependencies, emails []string) error {
	if !approvalEmailEnabled(deps) {
		return nil
	}
	for _, email := range dedupeApprovalEmails(emails) {
		if err := deps.Mailer.SendApprovalRequestEmail(email); err != nil {
			return fiber.NewError(fiber.StatusServiceUnavailable, "approval request email failed")
		}
	}
	return nil
}

func sendApprovalDecisionEmails(
	deps Dependencies,
	emails []string,
	approved bool,
) error {
	if !approvalEmailEnabled(deps) {
		return nil
	}
	for _, email := range dedupeApprovalEmails(emails) {
		if err := deps.Mailer.SendApprovalDecisionEmail(email, approved); err != nil {
			return fiber.NewError(fiber.StatusServiceUnavailable, "approval decision email failed")
		}
	}
	return nil
}

func dedupeApprovalEmails(emails []string) []string {
	results := []string{}
	seen := map[string]struct{}{}
	for _, email := range emails {
		trimmed := strings.TrimSpace(email)
		if trimmed == "" {
			continue
		}
		key := strings.ToLower(trimmed)
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		results = append(results, trimmed)
	}
	return results
}
