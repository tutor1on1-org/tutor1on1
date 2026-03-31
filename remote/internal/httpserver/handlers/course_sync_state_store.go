package handlers

import (
	"database/sql"
	"errors"
	"strings"

	"github.com/gofiber/fiber/v2"
)

const emptyCourseSyncState2 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

func queryTeacherCourseSourceItems(db *sql.DB, userID int64) ([]teacherCourseSummary, error) {
	teacherID, err := getTeacherAccountID(db, userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, fiber.NewError(fiber.StatusForbidden, "teacher account required")
		}
		return nil, fiber.NewError(fiber.StatusInternalServerError, "teacher lookup failed")
	}
	rows, err := db.Query(
		`SELECT c.id, c.subject,
		        (
		          SELECT bv.id FROM bundles b
		          JOIN bundle_versions bv ON bv.bundle_id = b.id
		          WHERE b.course_id = c.id
		          ORDER BY bv.version DESC, bv.id DESC
		          LIMIT 1
		        ) AS latest_bundle_version_id,
		        (
		          SELECT bv.hash FROM bundles b
		          JOIN bundle_versions bv ON bv.bundle_id = b.id
		          WHERE b.course_id = c.id
		          ORDER BY bv.version DESC, bv.id DESC
		          LIMIT 1
		        ) AS latest_bundle_hash
		 FROM courses c
		 JOIN (
		   SELECT teacher_id, course_name_key, MAX(id) AS latest_course_id
		   FROM courses
		   WHERE teacher_id = ?
		   GROUP BY teacher_id, course_name_key
		 ) latest ON latest.latest_course_id = c.id
		 WHERE c.teacher_id = ?
		 ORDER BY c.created_at DESC`,
		teacherID,
		teacherID,
	)
	if err != nil {
		return nil, fiber.NewError(fiber.StatusInternalServerError, "course sync-state write failed")
	}
	defer rows.Close()

	results := []teacherCourseSummary{}
	for rows.Next() {
		var (
			courseID     int64
			subject      string
			latestBundle sql.NullInt64
			latestHash   sql.NullString
		)
		if err := rows.Scan(
			&courseID,
			&subject,
			&latestBundle,
			&latestHash,
		); err != nil {
			return nil, fiber.NewError(fiber.StatusInternalServerError, "course sync-state write failed")
		}
		results = append(results, teacherCourseSummary{
			CourseID:              courseID,
			Subject:               subject,
			LatestBundleVersionID: latestBundle.Int64,
			LatestBundleHash:      latestHash.String,
		})
	}
	if err := rows.Err(); err != nil {
		return nil, fiber.NewError(fiber.StatusInternalServerError, "course sync-state write failed")
	}
	return results, nil
}

func queryStudentEnrollmentSourceItems(db *sql.DB, userID int64) ([]enrollmentSummary, error) {
	rows, err := db.Query(
		`SELECT e.course_id, t.user_id, c.subject, t.display_name,
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
		        ) AS latest_bundle_hash
		 FROM enrollments e
		 JOIN courses c ON e.course_id = c.id
		 JOIN teacher_accounts t ON e.teacher_id = t.id
		 WHERE e.student_id = ? AND e.status = 'active'
		 ORDER BY e.assigned_at DESC`,
		userID,
	)
	if err != nil {
		return nil, fiber.NewError(fiber.StatusInternalServerError, "enrollment sync-state write failed")
	}
	defer rows.Close()

	results := []enrollmentSummary{}
	for rows.Next() {
		var (
			courseID      int64
			teacherUserID int64
			subject       string
			teacherName   string
			latestBundle  sql.NullInt64
			latestHash    sql.NullString
		)
		if err := rows.Scan(
			&courseID,
			&teacherUserID,
			&subject,
			&teacherName,
			&latestBundle,
			&latestHash,
		); err != nil {
			return nil, fiber.NewError(fiber.StatusInternalServerError, "enrollment sync-state write failed")
		}
		results = append(results, enrollmentSummary{
			CourseID:              courseID,
			TeacherID:             teacherUserID,
			CourseName:            subject,
			TeacherName:           teacherName,
			LatestBundleVersionID: latestBundle.Int64,
			LatestBundleHash:      latestHash.String,
		})
	}
	if err := rows.Err(); err != nil {
		return nil, fiber.NewError(fiber.StatusInternalServerError, "enrollment sync-state write failed")
	}
	return results, nil
}

func listTeacherCourseStateItems(db *sql.DB, userID int64) ([]teacherCourseSummary, error) {
	if _, err := getTeacherAccountID(db, userID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, fiber.NewError(fiber.StatusForbidden, "teacher account required")
		}
		return nil, fiber.NewError(fiber.StatusInternalServerError, "teacher lookup failed")
	}
	rows, err := db.Query(
		`SELECT course_id, subject, latest_bundle_version_id, latest_bundle_hash
		 FROM teacher_course_sync_state1_items
		 WHERE user_id = ?
		 ORDER BY course_id ASC`,
		userID,
	)
	if err != nil {
		return nil, fiber.NewError(fiber.StatusInternalServerError, "course sync-state1 failed")
	}
	defer rows.Close()

	results := []teacherCourseSummary{}
	for rows.Next() {
		var item teacherCourseSummary
		if err := rows.Scan(
			&item.CourseID,
			&item.Subject,
			&item.LatestBundleVersionID,
			&item.LatestBundleHash,
		); err != nil {
			return nil, fiber.NewError(fiber.StatusInternalServerError, "course sync-state1 failed")
		}
		results = append(results, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fiber.NewError(fiber.StatusInternalServerError, "course sync-state1 failed")
	}
	if len(results) == 0 {
		sourceItems, sourceErr := queryTeacherCourseSourceItems(db, userID)
		if sourceErr != nil {
			return nil, sourceErr
		}
		if persistErr := persistTeacherCourseSyncState(db, userID, sourceItems); persistErr != nil {
			return nil, persistErr
		}
		return sourceItems, nil
	}
	return results, nil
}

func listStudentEnrollmentStateItems(db *sql.DB, userID int64) ([]enrollmentSummary, error) {
	rows, err := db.Query(
		`SELECT course_id, teacher_user_id, teacher_name, course_subject,
		        latest_bundle_version_id, latest_bundle_hash
		 FROM student_enrollment_sync_state1_items
		 WHERE user_id = ?
		 ORDER BY course_id ASC`,
		userID,
	)
	if err != nil {
		return nil, fiber.NewError(fiber.StatusInternalServerError, "enrollment sync-state1 failed")
	}
	defer rows.Close()

	results := []enrollmentSummary{}
	for rows.Next() {
		var item enrollmentSummary
		if err := rows.Scan(
			&item.CourseID,
			&item.TeacherID,
			&item.TeacherName,
			&item.CourseName,
			&item.LatestBundleVersionID,
			&item.LatestBundleHash,
		); err != nil {
			return nil, fiber.NewError(fiber.StatusInternalServerError, "enrollment sync-state1 failed")
		}
		results = append(results, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fiber.NewError(fiber.StatusInternalServerError, "enrollment sync-state1 failed")
	}
	if len(results) == 0 {
		sourceItems, sourceErr := queryStudentEnrollmentSourceItems(db, userID)
		if sourceErr != nil {
			return nil, sourceErr
		}
		if persistErr := persistStudentEnrollmentSyncState(db, userID, sourceItems); persistErr != nil {
			return nil, persistErr
		}
		return sourceItems, nil
	}
	return results, nil
}

func buildTeacherCourseState2(items []teacherCourseSummary) string {
	fingerprints := make([]string, 0, len(items))
	for _, item := range items {
		fingerprints = append(fingerprints, buildTeacherCourseStateFingerprint(item))
	}
	return buildState2(fingerprints)
}

func buildStudentEnrollmentState2(items []enrollmentSummary) string {
	fingerprints := make([]string, 0, len(items))
	for _, item := range items {
		fingerprints = append(fingerprints, buildStudentEnrollmentStateFingerprint(item))
	}
	return buildState2(fingerprints)
}

func persistTeacherCourseSyncStateForUser(db *sql.DB, userID int64) error {
	items, err := queryTeacherCourseSourceItems(db, userID)
	if err != nil {
		return err
	}
	return persistTeacherCourseSyncState(db, userID, items)
}

func persistTeacherCourseSyncState(
	db *sql.DB,
	userID int64,
	items []teacherCourseSummary,
) error {
	tx, err := db.Begin()
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "course sync-state write failed")
	}
	defer tx.Rollback()

	if _, err := tx.Exec(
		`DELETE FROM teacher_course_sync_state1_items WHERE user_id = ?`,
		userID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "course sync-state write failed")
	}
	for _, item := range items {
		if _, err := tx.Exec(
			`INSERT INTO teacher_course_sync_state1_items
			 (user_id, course_id, subject, latest_bundle_version_id, latest_bundle_hash, updated_at)
			 VALUES (?, ?, ?, ?, ?, UTC_TIMESTAMP())`,
			userID,
			item.CourseID,
			item.Subject,
			item.LatestBundleVersionID,
			item.LatestBundleHash,
		); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "course sync-state write failed")
		}
	}
	if _, err := tx.Exec(
		`INSERT INTO teacher_course_sync_state2 (user_id, state2, updated_at)
		 VALUES (?, ?, UTC_TIMESTAMP())
		 ON DUPLICATE KEY UPDATE state2 = VALUES(state2), updated_at = VALUES(updated_at)`,
		userID,
		buildTeacherCourseState2(items),
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "course sync-state write failed")
	}
	if err := tx.Commit(); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "course sync-state write failed")
	}
	return nil
}

func persistStudentEnrollmentSyncStateForUser(db *sql.DB, userID int64) error {
	items, err := queryStudentEnrollmentSourceItems(db, userID)
	if err != nil {
		return err
	}
	return persistStudentEnrollmentSyncState(db, userID, items)
}

func persistStudentEnrollmentSyncState(
	db *sql.DB,
	userID int64,
	items []enrollmentSummary,
) error {
	tx, err := db.Begin()
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "enrollment sync-state write failed")
	}
	defer tx.Rollback()

	if _, err := tx.Exec(
		`DELETE FROM student_enrollment_sync_state1_items WHERE user_id = ?`,
		userID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "enrollment sync-state write failed")
	}
	for _, item := range items {
		if _, err := tx.Exec(
			`INSERT INTO student_enrollment_sync_state1_items
			 (user_id, course_id, teacher_user_id, teacher_name, course_subject, latest_bundle_version_id, latest_bundle_hash, updated_at)
			 VALUES (?, ?, ?, ?, ?, ?, ?, UTC_TIMESTAMP())`,
			userID,
			item.CourseID,
			item.TeacherID,
			item.TeacherName,
			item.CourseName,
			item.LatestBundleVersionID,
			item.LatestBundleHash,
		); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "enrollment sync-state write failed")
		}
	}
	if _, err := tx.Exec(
		`INSERT INTO student_enrollment_sync_state2 (user_id, state2, updated_at)
		 VALUES (?, ?, UTC_TIMESTAMP())
		 ON DUPLICATE KEY UPDATE state2 = VALUES(state2), updated_at = VALUES(updated_at)`,
		userID,
		buildStudentEnrollmentState2(items),
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "enrollment sync-state write failed")
	}
	if err := tx.Commit(); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "enrollment sync-state write failed")
	}
	return nil
}

func readTeacherCourseSyncState2(db *sql.DB, userID int64) (string, error) {
	if _, err := getTeacherAccountID(db, userID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", fiber.NewError(fiber.StatusForbidden, "teacher account required")
		}
		return "", fiber.NewError(fiber.StatusInternalServerError, "teacher lookup failed")
	}
	var state2 string
	err := db.QueryRow(
		`SELECT state2 FROM teacher_course_sync_state2 WHERE user_id = ?`,
		userID,
	).Scan(&state2)
	switch {
	case err == nil:
		trimmed := strings.TrimSpace(state2)
		if trimmed == "" {
			return emptyCourseSyncState2, nil
		}
		return trimmed, nil
	case errors.Is(err, sql.ErrNoRows):
		sourceItems, sourceErr := queryTeacherCourseSourceItems(db, userID)
		if sourceErr != nil {
			return "", sourceErr
		}
		if persistErr := persistTeacherCourseSyncState(db, userID, sourceItems); persistErr != nil {
			return "", persistErr
		}
		return buildTeacherCourseState2(sourceItems), nil
	default:
		return "", fiber.NewError(fiber.StatusInternalServerError, "course sync-state2 failed")
	}
}

func readStudentEnrollmentSyncState2(db *sql.DB, userID int64) (string, error) {
	var state2 string
	err := db.QueryRow(
		`SELECT state2 FROM student_enrollment_sync_state2 WHERE user_id = ?`,
		userID,
	).Scan(&state2)
	switch {
	case err == nil:
		trimmed := strings.TrimSpace(state2)
		if trimmed == "" {
			return emptyCourseSyncState2, nil
		}
		return trimmed, nil
	case errors.Is(err, sql.ErrNoRows):
		sourceItems, sourceErr := queryStudentEnrollmentSourceItems(db, userID)
		if sourceErr != nil {
			return "", sourceErr
		}
		if persistErr := persistStudentEnrollmentSyncState(db, userID, sourceItems); persistErr != nil {
			return "", persistErr
		}
		return buildStudentEnrollmentState2(sourceItems), nil
	default:
		return "", fiber.NewError(fiber.StatusInternalServerError, "enrollment sync-state2 failed")
	}
}

func refreshTeacherCourseSyncStateForUser(db *sql.DB, userID int64) error {
	return persistTeacherCourseSyncStateForUser(db, userID)
}

func refreshStudentEnrollmentSyncStateForUser(db *sql.DB, userID int64) error {
	return persistStudentEnrollmentSyncStateForUser(db, userID)
}

func refreshStudentEnrollmentSyncStateForCourse(db *sql.DB, courseID int64) error {
	rows, err := db.Query(
		`SELECT DISTINCT student_id
		 FROM enrollments
		 WHERE course_id = ? AND status = 'active'`,
		courseID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "enrollment sync-state write failed")
	}
	defer rows.Close()
	for rows.Next() {
		var userID int64
		if err := rows.Scan(&userID); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "enrollment sync-state write failed")
		}
		if rebuildErr := refreshStudentEnrollmentSyncStateForUser(db, userID); rebuildErr != nil {
			return rebuildErr
		}
	}
	if err := rows.Err(); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "enrollment sync-state write failed")
	}
	return nil
}

func refreshStudentEnrollmentSyncStateForUsers(db *sql.DB, userIDs []int64) error {
	seen := map[int64]struct{}{}
	for _, userID := range userIDs {
		if userID <= 0 {
			continue
		}
		if _, exists := seen[userID]; exists {
			continue
		}
		seen[userID] = struct{}{}
		if err := refreshStudentEnrollmentSyncStateForUser(db, userID); err != nil {
			return err
		}
	}
	return nil
}
