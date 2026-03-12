package handlers

import (
	"database/sql"
	"errors"
	"strings"

	"github.com/gofiber/fiber/v2"
)

func requireAdminUserID(c *fiber.Ctx, deps Dependencies) (int64, error) {
	userID, err := requireUserID(c, deps.Config.JWTVerifySecrets)
	if err != nil {
		return 0, fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	var adminID int64
	row := deps.Store.DB.QueryRow(
		`SELECT id
		 FROM admin_accounts
		 WHERE user_id = ?
		 LIMIT 1`,
		userID,
	)
	if err := row.Scan(&adminID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return 0, fiber.NewError(fiber.StatusForbidden, "admin required")
		}
		return 0, fiber.NewError(fiber.StatusInternalServerError, "admin lookup failed")
	}
	return userID, nil
}

func isAdminUser(db *sql.DB, userID int64) (bool, error) {
	var adminID int64
	row := db.QueryRow("SELECT id FROM admin_accounts WHERE user_id = ? LIMIT 1", userID)
	if err := row.Scan(&adminID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return false, nil
		}
		return false, err
	}
	return true, nil
}

func getTeacherAccountByUserID(db *sql.DB, userID int64) (int64, error) {
	row := db.QueryRow("SELECT id FROM teacher_accounts WHERE user_id = ? LIMIT 1", userID)
	var teacherID int64
	if err := row.Scan(&teacherID); err != nil {
		return 0, err
	}
	return teacherID, nil
}

func listSubjectAdminLabelIDs(db *sql.DB, userID int64) ([]int64, error) {
	rows, err := db.Query(
		`SELECT saa.subject_label_id
		 FROM subject_admin_assignments saa
		 WHERE saa.teacher_user_id = ?
		 ORDER BY saa.subject_label_id ASC`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	results := []int64{}
	for rows.Next() {
		var labelID int64
		if err := rows.Scan(&labelID); err != nil {
			return nil, err
		}
		results = append(results, labelID)
	}
	return results, rows.Err()
}

func isSubjectAdminForTeacherRequest(db *sql.DB, requestID int64, userID int64) (bool, error) {
	var found int
	row := db.QueryRow(
		`SELECT 1
		 FROM teacher_registration_requests trr
		 JOIN teacher_subject_labels tsl ON tsl.teacher_id = trr.teacher_id
		 JOIN subject_admin_assignments saa ON saa.subject_label_id = tsl.subject_label_id
		 WHERE trr.id = ? AND saa.teacher_user_id = ?
		 LIMIT 1`,
		requestID,
		userID,
	)
	if err := row.Scan(&found); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return false, nil
		}
		return false, err
	}
	return true, nil
}

func isSubjectAdminForCourseRequest(db *sql.DB, requestID int64, userID int64) (bool, error) {
	var found int
	row := db.QueryRow(
		`SELECT 1
		 FROM course_upload_requests cur
		 JOIN course_subject_labels csl ON csl.course_id = cur.course_id
		 JOIN subject_admin_assignments saa ON saa.subject_label_id = csl.subject_label_id
		 WHERE cur.id = ? AND saa.teacher_user_id = ?
		 LIMIT 1`,
		requestID,
		userID,
	)
	if err := row.Scan(&found); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return false, nil
		}
		return false, err
	}
	return true, nil
}

func nullableStringPtr(value string) interface{} {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return nil
	}
	return trimmed
}
