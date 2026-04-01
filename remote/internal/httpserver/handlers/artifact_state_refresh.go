package handlers

import (
	"database/sql"
	"sort"

	"family_teacher_remote/internal/artifactsync"
)

func deleteStudentArtifactsForCourseTx(tx *sql.Tx, courseID int64) error {
	if tx == nil || courseID <= 0 {
		return nil
	}
	_, err := tx.Exec(
		`DELETE FROM student_kp_artifacts WHERE course_id = ?`,
		courseID,
	)
	return err
}

func deleteStudentArtifactsForCourseAndStudentTx(
	tx *sql.Tx,
	courseID int64,
	studentUserID int64,
) error {
	if tx == nil || courseID <= 0 || studentUserID <= 0 {
		return nil
	}
	_, err := tx.Exec(
		`DELETE FROM student_kp_artifacts
		 WHERE course_id = ? AND student_user_id = ?`,
		courseID,
		studentUserID,
	)
	return err
}

func refreshArtifactStatesForUsers(db *sql.DB, userIDs []int64) error {
	if db == nil {
		return nil
	}
	seen := map[int64]struct{}{}
	normalized := make([]int64, 0, len(userIDs))
	for _, userID := range userIDs {
		if userID <= 0 {
			continue
		}
		if _, ok := seen[userID]; ok {
			continue
		}
		seen[userID] = struct{}{}
		normalized = append(normalized, userID)
	}
	sort.Slice(normalized, func(i, j int) bool {
		return normalized[i] < normalized[j]
	})
	for _, userID := range normalized {
		if err := artifactsync.RefreshUserState(db, userID); err != nil {
			return err
		}
	}
	return nil
}
