package artifactsync

import (
	"database/sql"
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"
)

type VisibleArtifact struct {
	ArtifactID      string
	ArtifactClass   string
	CourseID        int64
	TeacherUserID   int64
	StudentUserID   int64
	KpKey           string
	BundleVersionID int64
	StorageRelPath  string
	SHA256          string
	LastModified    time.Time
}

type VisibleArtifactFilter struct {
	ArtifactClass string
	StudentUserID int64
	CourseID      int64
}

func ReadState2(db *sql.DB, userID int64) (string, error) {
	if db == nil {
		return "", errors.New("database required")
	}
	var state2 string
	err := db.QueryRow(
		`SELECT state2
		 FROM artifact_state2
		 WHERE user_id = ?`,
		userID,
	).Scan(&state2)
	if err == nil {
		return strings.TrimSpace(state2), nil
	}
	if errors.Is(err, sql.ErrNoRows) {
		return BuildState2(nil), nil
	}
	return "", err
}

func ListState1(db *sql.DB, userID int64) ([]VisibleArtifact, error) {
	return ListState1Filtered(db, userID, VisibleArtifactFilter{})
}

func ListState1Filtered(db *sql.DB, userID int64, filter VisibleArtifactFilter) ([]VisibleArtifact, error) {
	if db == nil {
		return nil, errors.New("database required")
	}
	queryBuilder := strings.Builder{}
	queryBuilder.WriteString(
		`SELECT artifact_id, artifact_class, course_id, teacher_user_id, COALESCE(student_user_id, 0), COALESCE(kp_key, ''), COALESCE(bundle_version_id, 0), storage_rel_path, sha256, last_modified
		 FROM artifact_state1_items
		 WHERE user_id = ?`,
	)
	args := []interface{}{userID}
	if strings.TrimSpace(filter.ArtifactClass) != "" {
		queryBuilder.WriteString(` AND artifact_class = ?`)
		args = append(args, strings.TrimSpace(filter.ArtifactClass))
	}
	if filter.StudentUserID > 0 {
		queryBuilder.WriteString(` AND COALESCE(student_user_id, 0) = ?`)
		args = append(args, filter.StudentUserID)
	}
	if filter.CourseID > 0 {
		queryBuilder.WriteString(` AND course_id = ?`)
		args = append(args, filter.CourseID)
	}
	queryBuilder.WriteString(` ORDER BY artifact_id ASC`)
	rows, err := db.Query(queryBuilder.String(), args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := []VisibleArtifact{}
	for rows.Next() {
		var item VisibleArtifact
		if err := rows.Scan(
			&item.ArtifactID,
			&item.ArtifactClass,
			&item.CourseID,
			&item.TeacherUserID,
			&item.StudentUserID,
			&item.KpKey,
			&item.BundleVersionID,
			&item.StorageRelPath,
			&item.SHA256,
			&item.LastModified,
		); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return items, nil
}

func ReadVisibleArtifact(db *sql.DB, userID int64, artifactID string) (VisibleArtifact, error) {
	if db == nil {
		return VisibleArtifact{}, errors.New("database required")
	}
	row := db.QueryRow(
		`SELECT artifact_id, artifact_class, course_id, teacher_user_id, COALESCE(student_user_id, 0), COALESCE(kp_key, ''), COALESCE(bundle_version_id, 0), storage_rel_path, sha256, last_modified
		 FROM artifact_state1_items
		 WHERE user_id = ? AND artifact_id = ?
		 LIMIT 1`,
		userID,
		strings.TrimSpace(artifactID),
	)
	var item VisibleArtifact
	if err := row.Scan(
		&item.ArtifactID,
		&item.ArtifactClass,
		&item.CourseID,
		&item.TeacherUserID,
		&item.StudentUserID,
		&item.KpKey,
		&item.BundleVersionID,
		&item.StorageRelPath,
		&item.SHA256,
		&item.LastModified,
	); err != nil {
		return VisibleArtifact{}, err
	}
	return item, nil
}

func ReadVisibleArtifactsByIDs(db *sql.DB, userID int64, artifactIDs []string) ([]VisibleArtifact, error) {
	if db == nil {
		return nil, errors.New("database required")
	}
	normalizedIDs := make([]string, 0, len(artifactIDs))
	seen := make(map[string]struct{}, len(artifactIDs))
	for _, artifactID := range artifactIDs {
		trimmed := strings.TrimSpace(artifactID)
		if trimmed == "" {
			continue
		}
		if _, ok := seen[trimmed]; ok {
			continue
		}
		seen[trimmed] = struct{}{}
		normalizedIDs = append(normalizedIDs, trimmed)
	}
	if len(normalizedIDs) == 0 {
		return nil, nil
	}

	placeholders := strings.TrimRight(strings.Repeat("?,", len(normalizedIDs)), ",")
	query := fmt.Sprintf(
		`SELECT artifact_id, artifact_class, course_id, teacher_user_id, COALESCE(student_user_id, 0), COALESCE(kp_key, ''), COALESCE(bundle_version_id, 0), storage_rel_path, sha256, last_modified
		 FROM artifact_state1_items
		 WHERE user_id = ? AND artifact_id IN (%s)`,
		placeholders,
	)
	args := make([]interface{}, 0, len(normalizedIDs)+1)
	args = append(args, userID)
	for _, artifactID := range normalizedIDs {
		args = append(args, artifactID)
	}
	rows, err := db.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	itemsByID := make(map[string]VisibleArtifact, len(normalizedIDs))
	for rows.Next() {
		var item VisibleArtifact
		if err := rows.Scan(
			&item.ArtifactID,
			&item.ArtifactClass,
			&item.CourseID,
			&item.TeacherUserID,
			&item.StudentUserID,
			&item.KpKey,
			&item.BundleVersionID,
			&item.StorageRelPath,
			&item.SHA256,
			&item.LastModified,
		); err != nil {
			return nil, err
		}
		itemsByID[item.ArtifactID] = item
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	orderedItems := make([]VisibleArtifact, 0, len(normalizedIDs))
	for _, artifactID := range normalizedIDs {
		item, ok := itemsByID[artifactID]
		if !ok {
			return nil, sql.ErrNoRows
		}
		orderedItems = append(orderedItems, item)
	}
	return orderedItems, nil
}

func RefreshUserState(db *sql.DB, userID int64) error {
	if db == nil {
		return errors.New("database required")
	}
	items, err := collectVisibleArtifacts(db, userID)
	if err != nil {
		return err
	}
	state2 := BuildState2(buildState2Items(items))
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()

	if _, err := tx.Exec(
		`DELETE FROM artifact_state1_items WHERE user_id = ?`,
		userID,
	); err != nil {
		return err
	}
	insertStmt, err := tx.Prepare(
		`INSERT INTO artifact_state1_items
		 (user_id, artifact_id, artifact_class, course_id, teacher_user_id, student_user_id, kp_key, bundle_version_id, storage_rel_path, sha256, last_modified)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
	)
	if err != nil {
		return err
	}
	defer insertStmt.Close()
	for _, item := range items {
		var studentUserID interface{}
		if item.StudentUserID > 0 {
			studentUserID = item.StudentUserID
		}
		var kpKey interface{}
		if strings.TrimSpace(item.KpKey) != "" {
			kpKey = strings.TrimSpace(item.KpKey)
		}
		var bundleVersionID interface{}
		if item.BundleVersionID > 0 {
			bundleVersionID = item.BundleVersionID
		}
		if _, err := insertStmt.Exec(
			userID,
			item.ArtifactID,
			item.ArtifactClass,
			item.CourseID,
			item.TeacherUserID,
			studentUserID,
			kpKey,
			bundleVersionID,
			item.StorageRelPath,
			item.SHA256,
			item.LastModified.UTC(),
		); err != nil {
			return err
		}
	}
	if _, err := tx.Exec(
		`INSERT INTO artifact_state2 (user_id, state2, updated_at)
		 VALUES (?, ?, ?)
		 ON DUPLICATE KEY UPDATE
		   state2 = VALUES(state2),
		   updated_at = VALUES(updated_at)`,
		userID,
		state2,
		time.Now().UTC(),
	); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return err
	}
	committed = true
	return nil
}

func RefreshUsersForCourse(db *sql.DB, courseID int64) error {
	if db == nil {
		return errors.New("database required")
	}
	userIDs, err := collectAffectedUserIDsForCourse(db, courseID)
	if err != nil {
		return err
	}
	for _, userID := range userIDs {
		if err := RefreshUserState(db, userID); err != nil {
			return err
		}
	}
	return nil
}

func RefreshAllUsers(db *sql.DB) error {
	if db == nil {
		return errors.New("database required")
	}
	rows, err := db.Query(`SELECT id FROM users ORDER BY id ASC`)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var userID int64
		if err := rows.Scan(&userID); err != nil {
			return err
		}
		if err := RefreshUserState(db, userID); err != nil {
			return err
		}
	}
	return rows.Err()
}

func UpsertStudentKpArtifactTx(
	tx *sql.Tx,
	artifactID string,
	courseID int64,
	teacherUserID int64,
	studentUserID int64,
	kpKey string,
	storageRelPath string,
	shaValue string,
	lastModified time.Time,
) error {
	if tx == nil {
		return errors.New("transaction required")
	}
	if strings.TrimSpace(artifactID) == "" ||
		courseID <= 0 ||
		teacherUserID <= 0 ||
		studentUserID <= 0 ||
		strings.TrimSpace(kpKey) == "" ||
		strings.TrimSpace(storageRelPath) == "" ||
		strings.TrimSpace(shaValue) == "" {
		return errors.New("student artifact fields missing")
	}
	_, err := tx.Exec(
		`INSERT INTO student_kp_artifacts
		 (artifact_id, course_id, teacher_user_id, student_user_id, kp_key, storage_rel_path, sha256, last_modified)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		 ON DUPLICATE KEY UPDATE
		   teacher_user_id = VALUES(teacher_user_id),
		   storage_rel_path = VALUES(storage_rel_path),
		   sha256 = VALUES(sha256),
		   last_modified = VALUES(last_modified)`,
		strings.TrimSpace(artifactID),
		courseID,
		teacherUserID,
		studentUserID,
		strings.TrimSpace(kpKey),
		strings.TrimSpace(storageRelPath),
		strings.TrimSpace(shaValue),
		lastModified.UTC(),
	)
	return err
}

func DeleteLegacyRowLevelTablesTx(tx *sql.Tx) error {
	if tx == nil {
		return errors.New("transaction required")
	}
	statements := []string{
		`DROP TABLE IF EXISTS enrollment_deletion_events`,
		`DROP TABLE IF EXISTS progress_sync_audit`,
		`DROP TABLE IF EXISTS progress_sync_chunks`,
		`DROP TABLE IF EXISTS progress_sync`,
		`DROP TABLE IF EXISTS session_text_sync`,
		`DROP TABLE IF EXISTS sync_download_state_items`,
		`DROP TABLE IF EXISTS sync_download_state2`,
		`DROP TABLE IF EXISTS teacher_course_sync_state1_items`,
		`DROP TABLE IF EXISTS teacher_course_sync_state2`,
		`DROP TABLE IF EXISTS student_enrollment_sync_state1_items`,
		`DROP TABLE IF EXISTS student_enrollment_sync_state2`,
		`DROP TABLE IF EXISTS user_keys`,
	}
	for _, statement := range statements {
		if _, err := tx.Exec(statement); err != nil {
			return err
		}
	}
	return nil
}

func collectVisibleArtifacts(db *sql.DB, userID int64) ([]VisibleArtifact, error) {
	items := []VisibleArtifact{}
	bundles, err := collectVisibleCourseBundles(db, userID)
	if err != nil {
		return nil, err
	}
	items = append(items, bundles...)
	studentArtifacts, err := collectVisibleStudentKpArtifacts(db, userID)
	if err != nil {
		return nil, err
	}
	items = append(items, studentArtifacts...)
	sort.Slice(items, func(i, j int) bool {
		if items[i].ArtifactID == items[j].ArtifactID {
			return items[i].SHA256 < items[j].SHA256
		}
		return items[i].ArtifactID < items[j].ArtifactID
	})
	return dedupeVisibleArtifacts(items), nil
}

func dedupeVisibleArtifacts(items []VisibleArtifact) []VisibleArtifact {
	if len(items) == 0 {
		return nil
	}
	deduped := make([]VisibleArtifact, 0, len(items))
	seen := map[string]struct{}{}
	for _, item := range items {
		if _, ok := seen[item.ArtifactID]; ok {
			continue
		}
		seen[item.ArtifactID] = struct{}{}
		deduped = append(deduped, item)
	}
	return deduped
}

func buildState2Items(items []VisibleArtifact) []State2Item {
	stateItems := make([]State2Item, 0, len(items))
	for _, item := range items {
		stateItems = append(stateItems, State2Item{
			ArtifactID: item.ArtifactID,
			SHA256:     item.SHA256,
		})
	}
	return stateItems
}

func collectVisibleCourseBundles(db *sql.DB, userID int64) ([]VisibleArtifact, error) {
	const latestBundleQuery = `
SELECT c.id, ta.user_id, bv.id, bv.oss_path, bv.hash, bv.created_at
FROM bundles b
JOIN courses c ON c.id = b.course_id
JOIN teacher_accounts ta ON ta.id = c.teacher_id
JOIN (
  SELECT bundle_id, MAX(version) AS max_version
  FROM bundle_versions
  GROUP BY bundle_id
) latest ON latest.bundle_id = b.id
JOIN bundle_versions bv ON bv.bundle_id = latest.bundle_id AND bv.version = latest.max_version
WHERE %s
`
	queries := []string{
		fmt.Sprintf(latestBundleQuery, `ta.user_id = ?`),
		fmt.Sprintf(
			latestBundleQuery,
			`c.id IN (
			  SELECT e.course_id
			  FROM enrollments e
			  WHERE e.student_id = ? AND e.status = 'active'
			)`,
		),
	}
	items := []VisibleArtifact{}
	for _, query := range queries {
		rows, err := db.Query(query, userID)
		if err != nil {
			return nil, err
		}
		for rows.Next() {
			var item VisibleArtifact
			if err := rows.Scan(
				&item.CourseID,
				&item.TeacherUserID,
				&item.BundleVersionID,
				&item.StorageRelPath,
				&item.SHA256,
				&item.LastModified,
			); err != nil {
				_ = rows.Close()
				return nil, err
			}
			if strings.TrimSpace(item.SHA256) == "" {
				_ = rows.Close()
				return nil, fmt.Errorf("latest bundle hash missing for course_id=%d bundle_version_id=%d", item.CourseID, item.BundleVersionID)
			}
			item.ArtifactID = ArtifactIDForCourseBundle(item.CourseID)
			item.ArtifactClass = "course_bundle"
			items = append(items, item)
		}
		if err := rows.Err(); err != nil {
			_ = rows.Close()
			return nil, err
		}
		_ = rows.Close()
	}
	return items, nil
}

func collectVisibleStudentKpArtifacts(db *sql.DB, userID int64) ([]VisibleArtifact, error) {
	rows, err := db.Query(
		`SELECT a.artifact_id, a.course_id, a.teacher_user_id, a.student_user_id, a.kp_key, a.storage_rel_path, a.sha256, a.last_modified
		 FROM student_kp_artifacts a
		 JOIN enrollments e
		   ON e.course_id = a.course_id
		  AND e.student_id = a.student_user_id
		  AND e.status = 'active'
		 WHERE a.teacher_user_id = ? OR a.student_user_id = ?`,
		userID,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []VisibleArtifact{}
	for rows.Next() {
		var item VisibleArtifact
		if err := rows.Scan(
			&item.ArtifactID,
			&item.CourseID,
			&item.TeacherUserID,
			&item.StudentUserID,
			&item.KpKey,
			&item.StorageRelPath,
			&item.SHA256,
			&item.LastModified,
		); err != nil {
			return nil, err
		}
		item.ArtifactClass = "student_kp"
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return items, nil
}

func collectAffectedUserIDsForCourse(db *sql.DB, courseID int64) ([]int64, error) {
	rows, err := db.Query(
		`SELECT DISTINCT user_id
		 FROM (
		   SELECT ta.user_id AS user_id
		   FROM courses c
		   JOIN teacher_accounts ta ON ta.id = c.teacher_id
		   WHERE c.id = ?
		   UNION
		   SELECT e.student_id AS user_id
		   FROM enrollments e
		   WHERE e.course_id = ? AND e.status = 'active'
		 ) users_for_course
		 ORDER BY user_id ASC`,
		courseID,
		courseID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	userIDs := []int64{}
	for rows.Next() {
		var userID int64
		if err := rows.Scan(&userID); err != nil {
			return nil, err
		}
		if userID > 0 {
			userIDs = append(userIDs, userID)
		}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return userIDs, nil
}
