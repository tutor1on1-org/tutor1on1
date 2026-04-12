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

func deleteCourseBundleReferencesTx(tx *sql.Tx, courseID int64) error {
	if tx == nil || courseID <= 0 {
		return nil
	}
	if _, err := tx.Exec(
		`DELETE cuv FROM course_upload_votes cuv
		 JOIN course_upload_requests cur ON cur.id = cuv.request_id
		 WHERE cur.course_id = ?`,
		courseID,
	); err != nil {
		return err
	}
	if _, err := tx.Exec(
		`DELETE FROM course_upload_requests WHERE course_id = ?`,
		courseID,
	); err != nil {
		return err
	}
	_, err := tx.Exec(
		`DELETE FROM artifact_state1_items WHERE course_id = ?`,
		courseID,
	)
	return err
}

func deleteBundleVersionReferencesTx(tx *sql.Tx, bundleVersionID int64) error {
	if tx == nil || bundleVersionID <= 0 {
		return nil
	}
	if _, err := tx.Exec(
		`DELETE cuv FROM course_upload_votes cuv
		 JOIN course_upload_requests cur ON cur.id = cuv.request_id
		 WHERE cur.bundle_version_id = ?`,
		bundleVersionID,
	); err != nil {
		return err
	}
	if _, err := tx.Exec(
		`DELETE FROM course_upload_requests WHERE bundle_version_id = ?`,
		bundleVersionID,
	); err != nil {
		return err
	}
	_, err := tx.Exec(
		`DELETE FROM artifact_state1_items WHERE bundle_version_id = ?`,
		bundleVersionID,
	)
	return err
}

func deleteCourseRecordReferencesTx(tx *sql.Tx, courseID int64) error {
	if tx == nil || courseID <= 0 {
		return nil
	}
	if _, err := tx.Exec(
		`DELETE FROM course_quit_requests WHERE course_id = ?`,
		courseID,
	); err != nil {
		return err
	}
	_, err := tx.Exec(
		`DELETE FROM course_subject_labels WHERE course_id = ?`,
		courseID,
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
