package artifactsync

import (
	"bytes"
	"crypto/ecdh"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"

	"family_teacher_remote/internal/storage"
)

type LegacyStudentCredential struct {
	Username string
	Password string
}

type LegacyCutoverSummary struct {
	StudentsResolved int
	LegacySessions   int
	LegacyProgress   int
	ArtifactsBuilt   int
	UsersRefreshed   int
	DroppedLegacy    bool
}

type legacyStudentIdentity struct {
	UserID      int64
	Username    string
	PrivateKey  *ecdh.PrivateKey
	PublicKey   string
	PasswordSet bool
}

type legacyStudentUser struct {
	UserID   int64
	Username string
}

type legacySessionRow struct {
	SessionSyncID string
	CourseID      int64
	CourseSubject string
	TeacherUserID int64
	StudentUserID int64
	StudentName   string
	UpdatedAt     time.Time
	Envelope      []byte
}

type legacyProgressRow struct {
	CourseID           int64
	CourseSubject      string
	TeacherUserID      int64
	StudentUserID      int64
	StudentName        string
	KpKey              string
	Lit                bool
	LitPercent         int
	QuestionLevel      string
	EasyPassedCount    int
	MediumPassedCount  int
	HardPassedCount    int
	SummaryText        string
	SummaryRawResponse string
	SummaryValid       *bool
	UpdatedAt          time.Time
	Envelope           []byte
}

type studentKpGroupKey struct {
	StudentUserID int64
	CourseID      int64
	KpKey         string
}

type studentKpGroup struct {
	TeacherUserID int64
	StudentName   string
	CourseSubject string
	Progress      *StudentProgressPayload
	Sessions      []StudentSessionPayload
	UpdatedAt     time.Time
}

func RunLegacyStudentCutover(
	db *sql.DB,
	storageSvc *storage.Service,
	credentials []LegacyStudentCredential,
	dropLegacy bool,
) (LegacyCutoverSummary, error) {
	if db == nil {
		return LegacyCutoverSummary{}, errors.New("database required")
	}
	if storageSvc == nil {
		return LegacyCutoverSummary{}, errors.New("storage service required")
	}
	if err := ensureCutoverTables(db); err != nil {
		return LegacyCutoverSummary{}, err
	}
	identities, err := loadLegacyStudentIdentities(db, credentials)
	if err != nil {
		return LegacyCutoverSummary{}, err
	}
	if len(identities) == 0 {
		return LegacyCutoverSummary{}, errors.New("at least one student credential required")
	}
	studentIDs := make([]int64, 0, len(identities))
	identitiesByUserID := make(map[int64]legacyStudentIdentity, len(identities))
	for _, identity := range identities {
		studentIDs = append(studentIDs, identity.UserID)
		identitiesByUserID[identity.UserID] = identity
	}
	sessions, err := loadLegacySessions(db, studentIDs)
	if err != nil {
		return LegacyCutoverSummary{}, err
	}
	progressRows, err := loadLegacyProgressRows(db, studentIDs)
	if err != nil {
		return LegacyCutoverSummary{}, err
	}
	groups, err := buildStudentKpGroups(sessions, progressRows, identitiesByUserID)
	if err != nil {
		return LegacyCutoverSummary{}, err
	}
	if err := backfillBundleVersionHashes(db, storageSvc); err != nil {
		return LegacyCutoverSummary{}, err
	}

	tx, err := db.Begin()
	if err != nil {
		return LegacyCutoverSummary{}, err
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()
	if _, err := tx.Exec(`DELETE FROM student_kp_artifacts`); err != nil {
		return LegacyCutoverSummary{}, err
	}
	cutoverRunID := fmt.Sprintf("cutover-%d", time.Now().UTC().UnixNano())

	for key, group := range groups {
		payload := StudentKpArtifactPayload{
			Schema:              StudentKpArtifactSchema,
			CourseID:            key.CourseID,
			CourseSubject:       strings.TrimSpace(group.CourseSubject),
			KpKey:               strings.TrimSpace(key.KpKey),
			TeacherRemoteUserID: group.TeacherUserID,
			StudentRemoteUserID: key.StudentUserID,
			StudentUsername:     strings.TrimSpace(group.StudentName),
			UpdatedAt:           group.UpdatedAt.UTC().Format(time.RFC3339),
			Progress:            group.Progress,
			Sessions:            group.Sessions,
		}
		zipBytes, zipSHA, err := BuildStudentKpArtifactZip(payload)
		if err != nil {
			return LegacyCutoverSummary{}, err
		}
		artifactID := ArtifactIDForStudentKp(key.StudentUserID, key.CourseID, key.KpKey)
		storageRelPath := CutoverStudentKpStorageRelPath(
			cutoverRunID,
			key.StudentUserID,
			key.CourseID,
			key.KpKey,
		)
		_, storedSHA, err := storageSvc.SaveRelativePath(storageRelPath, bytes.NewReader(zipBytes))
		if err != nil {
			return LegacyCutoverSummary{}, err
		}
		if storedSHA != zipSHA {
			return LegacyCutoverSummary{}, fmt.Errorf("stored student artifact sha mismatch for %s", artifactID)
		}
		if err := UpsertStudentKpArtifactTx(
			tx,
			artifactID,
			key.CourseID,
			group.TeacherUserID,
			key.StudentUserID,
			key.KpKey,
			storageRelPath,
			zipSHA,
			group.UpdatedAt,
		); err != nil {
			return LegacyCutoverSummary{}, err
		}
	}
	if err := tx.Commit(); err != nil {
		return LegacyCutoverSummary{}, err
	}
	committed = true

	if err := RefreshAllUsers(db); err != nil {
		return LegacyCutoverSummary{}, err
	}
	if dropLegacy {
		legacyDropTx, err := db.Begin()
		if err != nil {
			return LegacyCutoverSummary{}, err
		}
		legacyDropped := false
		defer func() {
			if !legacyDropped {
				_ = legacyDropTx.Rollback()
			}
		}()
		if err := DeleteLegacyRowLevelTablesTx(legacyDropTx); err != nil {
			return LegacyCutoverSummary{}, err
		}
		if err := legacyDropTx.Commit(); err != nil {
			return LegacyCutoverSummary{}, err
		}
		legacyDropped = true
	}
	return LegacyCutoverSummary{
		StudentsResolved: len(identities),
		LegacySessions:   len(sessions),
		LegacyProgress:   len(progressRows),
		ArtifactsBuilt:   len(groups),
		UsersRefreshed:   countUsers(db),
		DroppedLegacy:    dropLegacy,
	}, nil
}

func ensureCutoverTables(db *sql.DB) error {
	statements := []string{
		`CREATE TABLE IF NOT EXISTS student_kp_artifacts (
		  id BIGINT PRIMARY KEY AUTO_INCREMENT,
		  artifact_id VARCHAR(255) NOT NULL UNIQUE,
		  course_id BIGINT NOT NULL,
		  teacher_user_id BIGINT NOT NULL,
		  student_user_id BIGINT NOT NULL,
		  kp_key VARCHAR(128) NOT NULL,
		  storage_rel_path VARCHAR(512) NOT NULL,
		  sha256 VARCHAR(64) NOT NULL,
		  last_modified DATETIME NOT NULL,
		  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
		  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
		  UNIQUE KEY uq_student_kp_artifacts_scope (course_id, student_user_id, kp_key),
		  INDEX idx_student_kp_artifacts_teacher (teacher_user_id, course_id, student_user_id),
		  INDEX idx_student_kp_artifacts_student (student_user_id, course_id, kp_key),
		  CONSTRAINT fk_student_kp_artifacts_course
		    FOREIGN KEY (course_id) REFERENCES courses(id),
		  CONSTRAINT fk_student_kp_artifacts_teacher_user
		    FOREIGN KEY (teacher_user_id) REFERENCES users(id),
		  CONSTRAINT fk_student_kp_artifacts_student_user
		    FOREIGN KEY (student_user_id) REFERENCES users(id)
		)`,
		`CREATE TABLE IF NOT EXISTS artifact_state1_items (
		  user_id BIGINT NOT NULL,
		  artifact_id VARCHAR(255) NOT NULL,
		  artifact_class VARCHAR(32) NOT NULL,
		  course_id BIGINT NOT NULL,
		  teacher_user_id BIGINT NOT NULL,
		  student_user_id BIGINT NULL,
		  kp_key VARCHAR(128) NULL,
		  bundle_version_id BIGINT NULL,
		  storage_rel_path VARCHAR(512) NOT NULL,
		  sha256 VARCHAR(64) NOT NULL,
		  last_modified DATETIME NOT NULL,
		  PRIMARY KEY (user_id, artifact_id),
		  INDEX idx_artifact_state1_user (user_id, artifact_class, artifact_id)
		)`,
		`CREATE TABLE IF NOT EXISTS artifact_state2 (
		  user_id BIGINT PRIMARY KEY,
		  state2 VARCHAR(191) NOT NULL,
		  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
		)`,
	}
	for _, statement := range statements {
		if _, err := db.Exec(statement); err != nil {
			return err
		}
	}
	return nil
}

func loadLegacyStudentIdentities(
	db *sql.DB,
	credentials []LegacyStudentCredential,
) ([]legacyStudentIdentity, error) {
	normalizedCredentials, err := normalizeLegacyStudentCredentials(credentials)
	if err != nil {
		return nil, err
	}
	legacyUsers, err := loadLegacyStudentUsers(db)
	if err != nil {
		return nil, err
	}
	if err := validateLegacyStudentCredentialCoverage(
		legacyUsers,
		normalizedCredentials,
	); err != nil {
		return nil, err
	}
	normalized := make([]legacyStudentIdentity, 0, len(legacyUsers))
	for _, legacyUser := range legacyUsers {
		credential := normalizedCredentials[strings.ToLower(legacyUser.Username)]
		row := db.QueryRow(
			`SELECT public_key, enc_private_key
			 FROM user_keys
			 WHERE user_id = ?
			 LIMIT 1`,
			legacyUser.UserID,
		)
		record := UserKeyRecord{UserID: legacyUser.UserID}
		if err := row.Scan(&record.PublicKey, &record.EncPrivateKey); err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return nil, fmt.Errorf("student user key not found for %s", strings.TrimSpace(legacyUser.Username))
			}
			return nil, err
		}
		privateKey, err := DecryptPrivateKey(record, credential.Password)
		if err != nil {
			return nil, fmt.Errorf(
				"failed to decrypt private key for %s: %w",
				strings.TrimSpace(legacyUser.Username),
				err,
			)
		}
		normalized = append(normalized, legacyStudentIdentity{
			UserID:      legacyUser.UserID,
			Username:    strings.TrimSpace(legacyUser.Username),
			PrivateKey:  privateKey,
			PublicKey:   record.PublicKey,
			PasswordSet: true,
		})
	}
	return normalized, nil
}

func normalizeLegacyStudentCredentials(
	credentials []LegacyStudentCredential,
) (map[string]LegacyStudentCredential, error) {
	normalized := make(map[string]LegacyStudentCredential, len(credentials))
	for _, credential := range credentials {
		username := strings.TrimSpace(strings.ToLower(credential.Username))
		password := credential.Password
		if username == "" || password == "" {
			return nil, fmt.Errorf("student credentials must include username and password")
		}
		if _, exists := normalized[username]; exists {
			return nil, fmt.Errorf("duplicate student credential provided for %s", username)
		}
		normalized[username] = LegacyStudentCredential{
			Username: username,
			Password: password,
		}
	}
	return normalized, nil
}

func loadLegacyStudentUsers(db *sql.DB) ([]legacyStudentUser, error) {
	rows, err := db.Query(
		`SELECT u.id, u.username
		 FROM users u
		 JOIN (
		   SELECT student_user_id AS user_id FROM session_text_sync
		   UNION
		   SELECT student_user_id AS user_id FROM progress_sync
		 ) legacy_students
		   ON legacy_students.user_id = u.id
		 ORDER BY u.id ASC`,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	users := []legacyStudentUser{}
	for rows.Next() {
		var user legacyStudentUser
		if err := rows.Scan(&user.UserID, &user.Username); err != nil {
			return nil, err
		}
		users = append(users, legacyStudentUser{
			UserID:   user.UserID,
			Username: strings.TrimSpace(user.Username),
		})
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return users, nil
}

func validateLegacyStudentCredentialCoverage(
	legacyUsers []legacyStudentUser,
	credentials map[string]LegacyStudentCredential,
) error {
	if len(credentials) == 0 {
		return fmt.Errorf("at least one student credential required")
	}
	if len(legacyUsers) == 0 {
		return fmt.Errorf("legacy student sync data not found")
	}
	legacyUsernames := make(map[string]struct{}, len(legacyUsers))
	missingCredentials := make([]string, 0)
	for _, legacyUser := range legacyUsers {
		username := strings.TrimSpace(strings.ToLower(legacyUser.Username))
		legacyUsernames[username] = struct{}{}
		if _, ok := credentials[username]; !ok {
			missingCredentials = append(missingCredentials, username)
		}
	}
	unexpectedCredentials := make([]string, 0)
	for username := range credentials {
		if _, ok := legacyUsernames[username]; !ok {
			unexpectedCredentials = append(unexpectedCredentials, username)
		}
	}
	if len(missingCredentials) == 0 && len(unexpectedCredentials) == 0 {
		return nil
	}
	sort.Strings(missingCredentials)
	sort.Strings(unexpectedCredentials)
	parts := make([]string, 0, 2)
	if len(missingCredentials) > 0 {
		parts = append(
			parts,
			"missing credentials for legacy students: "+strings.Join(missingCredentials, ", "),
		)
	}
	if len(unexpectedCredentials) > 0 {
		parts = append(
			parts,
			"unexpected student credentials without legacy data: "+strings.Join(unexpectedCredentials, ", "),
		)
	}
	return fmt.Errorf(
		"student credentials must exactly match legacy student sync users (%s)",
		strings.Join(parts, "; "),
	)
}

func loadLegacySessions(db *sql.DB, studentIDs []int64) ([]legacySessionRow, error) {
	if len(studentIDs) == 0 {
		return nil, nil
	}
	placeholders := make([]string, 0, len(studentIDs))
	args := make([]any, 0, len(studentIDs))
	for _, studentID := range studentIDs {
		placeholders = append(placeholders, "?")
		args = append(args, studentID)
	}
	rows, err := db.Query(
		`SELECT s.session_sync_id, s.course_id, c.subject, s.teacher_user_id, s.student_user_id, u.username, s.updated_at, s.envelope
		 FROM session_text_sync s
		 JOIN courses c ON c.id = s.course_id
		 JOIN users u ON u.id = s.student_user_id
		 WHERE s.student_user_id IN (`+strings.Join(placeholders, ",")+`)
		 ORDER BY s.student_user_id ASC, s.course_id ASC, s.updated_at ASC, s.id ASC`,
		args...,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := []legacySessionRow{}
	for rows.Next() {
		var row legacySessionRow
		if err := rows.Scan(
			&row.SessionSyncID,
			&row.CourseID,
			&row.CourseSubject,
			&row.TeacherUserID,
			&row.StudentUserID,
			&row.StudentName,
			&row.UpdatedAt,
			&row.Envelope,
		); err != nil {
			return nil, err
		}
		result = append(result, row)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return result, nil
}

func loadLegacyProgressRows(db *sql.DB, studentIDs []int64) ([]legacyProgressRow, error) {
	if len(studentIDs) == 0 {
		return nil, nil
	}
	placeholders := make([]string, 0, len(studentIDs))
	args := make([]any, 0, len(studentIDs))
	for _, studentID := range studentIDs {
		placeholders = append(placeholders, "?")
		args = append(args, studentID)
	}
	rows, err := db.Query(
		`SELECT p.course_id, c.subject, p.teacher_user_id, p.student_user_id, u.username, p.kp_key, p.lit, p.lit_percent,
		        COALESCE(p.question_level, ''), COALESCE(p.summary_text, ''), COALESCE(p.summary_raw_response, ''),
		        p.summary_valid, p.updated_at, p.envelope
		 FROM progress_sync p
		 JOIN courses c ON c.id = p.course_id
		 JOIN users u ON u.id = p.student_user_id
		 WHERE p.student_user_id IN (`+strings.Join(placeholders, ",")+`)
		 ORDER BY p.student_user_id ASC, p.course_id ASC, p.kp_key ASC`,
		args...,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := []legacyProgressRow{}
	for rows.Next() {
		var row legacyProgressRow
		var summaryValid sql.NullBool
		if err := rows.Scan(
			&row.CourseID,
			&row.CourseSubject,
			&row.TeacherUserID,
			&row.StudentUserID,
			&row.StudentName,
			&row.KpKey,
			&row.Lit,
			&row.LitPercent,
			&row.QuestionLevel,
			&row.SummaryText,
			&row.SummaryRawResponse,
			&summaryValid,
			&row.UpdatedAt,
			&row.Envelope,
		); err != nil {
			return nil, err
		}
		if summaryValid.Valid {
			value := summaryValid.Bool
			row.SummaryValid = &value
		}
		result = append(result, row)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return result, nil
}

func buildStudentKpGroups(
	sessions []legacySessionRow,
	progressRows []legacyProgressRow,
	identities map[int64]legacyStudentIdentity,
) (map[studentKpGroupKey]*studentKpGroup, error) {
	groups := map[studentKpGroupKey]*studentKpGroup{}
	for _, row := range sessions {
		identity, ok := identities[row.StudentUserID]
		if !ok || identity.PrivateKey == nil {
			return nil, fmt.Errorf("student identity missing for session %s", row.SessionSyncID)
		}
		envelopeJSON, err := decodeStoredEnvelopeJSON(row.Envelope)
		if err != nil {
			return nil, fmt.Errorf("decode envelope for session %s: %w", row.SessionSyncID, err)
		}
		payload, err := DecryptEnvelopeJSON(envelopeJSON, row.StudentUserID, identity.PrivateKey)
		if err != nil {
			return nil, fmt.Errorf("decrypt session %s: %w", row.SessionSyncID, err)
		}
		sessionPayload, kpKey, updatedAt, err := buildStudentSessionPayload(payload, row)
		if err != nil {
			return nil, err
		}
		groupKey := studentKpGroupKey{
			StudentUserID: row.StudentUserID,
			CourseID:      row.CourseID,
			KpKey:         kpKey,
		}
		group := groups[groupKey]
		if group == nil {
			group = &studentKpGroup{
				TeacherUserID: row.TeacherUserID,
				StudentName:   firstNonEmpty(strings.TrimSpace(row.StudentName), identity.Username),
				CourseSubject: strings.TrimSpace(row.CourseSubject),
				UpdatedAt:     updatedAt,
			}
			groups[groupKey] = group
		}
		if updatedAt.After(group.UpdatedAt) {
			group.UpdatedAt = updatedAt
		}
		group.Sessions = append(group.Sessions, sessionPayload)
	}
	for _, row := range progressRows {
		identity, ok := identities[row.StudentUserID]
		if !ok || identity.PrivateKey == nil {
			return nil, fmt.Errorf("student identity missing for progress course_id=%d student_user_id=%d kp_key=%q", row.CourseID, row.StudentUserID, row.KpKey)
		}
		envelopeJSON, err := decodeStoredEnvelopeJSON(row.Envelope)
		if err != nil {
			return nil, fmt.Errorf("decode progress envelope for course_id=%d student_user_id=%d kp_key=%q: %w", row.CourseID, row.StudentUserID, row.KpKey, err)
		}
		payload, err := DecryptEnvelopeJSON(envelopeJSON, row.StudentUserID, identity.PrivateKey)
		if err != nil {
			return nil, fmt.Errorf("decrypt progress for course_id=%d student_user_id=%d kp_key=%q: %w", row.CourseID, row.StudentUserID, row.KpKey, err)
		}
		progressPayload, kpKey, updatedAt, err := buildStudentProgressPayload(payload, row)
		if err != nil {
			return nil, err
		}
		groupKey := studentKpGroupKey{
			StudentUserID: row.StudentUserID,
			CourseID:      row.CourseID,
			KpKey:         kpKey,
		}
		group := groups[groupKey]
		if group == nil {
			group = &studentKpGroup{
				TeacherUserID: row.TeacherUserID,
				StudentName:   firstNonEmpty(strings.TrimSpace(row.StudentName), identity.Username),
				CourseSubject: strings.TrimSpace(row.CourseSubject),
				UpdatedAt:     updatedAt,
			}
			groups[groupKey] = group
		}
		group.Progress = &progressPayload
		if updatedAt.After(group.UpdatedAt) {
			group.UpdatedAt = updatedAt
		}
	}
	return groups, nil
}

func buildStudentSessionPayload(
	payload map[string]interface{},
	row legacySessionRow,
) (StudentSessionPayload, string, time.Time, error) {
	kpKey := requiredString(payload["kp_key"])
	if kpKey == "" {
		return StudentSessionPayload{}, "", time.Time{}, fmt.Errorf("legacy session %s missing kp_key after decrypt", row.SessionSyncID)
	}
	courseID := int64Value(payload["course_id"], row.CourseID)
	if courseID != row.CourseID {
		return StudentSessionPayload{}, "", time.Time{}, fmt.Errorf("legacy session %s course_id mismatch", row.SessionSyncID)
	}
	studentUserID := int64Value(payload["student_remote_user_id"], row.StudentUserID)
	if studentUserID != row.StudentUserID {
		return StudentSessionPayload{}, "", time.Time{}, fmt.Errorf("legacy session %s student id mismatch", row.SessionSyncID)
	}
	teacherUserID := int64Value(payload["teacher_remote_user_id"], row.TeacherUserID)
	if teacherUserID != row.TeacherUserID {
		return StudentSessionPayload{}, "", time.Time{}, fmt.Errorf("legacy session %s teacher id mismatch", row.SessionSyncID)
	}
	updatedAt := parseTimestampValue(payload["updated_at"], row.UpdatedAt)
	rawMessages, err := messagesValue(payload["messages"])
	if err != nil {
		return StudentSessionPayload{}, "", time.Time{}, fmt.Errorf("legacy session %s messages invalid: %w", row.SessionSyncID, err)
	}
	return StudentSessionPayload{
		SessionSyncID:          firstNonEmpty(requiredString(payload["session_sync_id"]), row.SessionSyncID),
		CourseID:               row.CourseID,
		CourseSubject:          firstNonEmpty(optionalString(payload["course_subject"]), row.CourseSubject),
		KpKey:                  kpKey,
		KpTitle:                optionalString(payload["kp_title"]),
		SessionTitle:           optionalString(payload["session_title"]),
		StartedAt:              parseTimestampValue(payload["started_at"], row.UpdatedAt).Format(time.RFC3339),
		EndedAt:                optionalTimestamp(payload["ended_at"]),
		SummaryText:            optionalString(payload["summary_text"]),
		ControlStateJSON:       optionalString(payload["control_state_json"]),
		ControlStateUpdatedAt:  optionalTimestamp(payload["control_state_updated_at"]),
		EvidenceStateJSON:      optionalString(payload["evidence_state_json"]),
		EvidenceStateUpdatedAt: optionalTimestamp(payload["evidence_state_updated_at"]),
		StudentRemoteUserID:    row.StudentUserID,
		StudentUsername:        firstNonEmpty(optionalString(payload["student_username"]), row.StudentName),
		TeacherRemoteUserID:    row.TeacherUserID,
		UpdatedAt:              updatedAt.Format(time.RFC3339),
		Messages:               rawMessages,
	}, kpKey, updatedAt, nil
}

func buildStudentProgressPayload(
	payload map[string]interface{},
	row legacyProgressRow,
) (StudentProgressPayload, string, time.Time, error) {
	kpKey := requiredString(payload["kp_key"])
	if kpKey == "" {
		return StudentProgressPayload{}, "", time.Time{}, fmt.Errorf("legacy progress course_id=%d student_user_id=%d missing kp_key after decrypt", row.CourseID, row.StudentUserID)
	}
	courseID := int64Value(payload["course_id"], row.CourseID)
	if courseID != row.CourseID {
		return StudentProgressPayload{}, "", time.Time{}, fmt.Errorf("legacy progress course_id=%d student_user_id=%d course_id mismatch", row.CourseID, row.StudentUserID)
	}
	studentUserID := int64Value(payload["student_remote_user_id"], row.StudentUserID)
	if studentUserID != row.StudentUserID {
		return StudentProgressPayload{}, "", time.Time{}, fmt.Errorf("legacy progress course_id=%d student_user_id=%d student id mismatch", row.CourseID, row.StudentUserID)
	}
	teacherUserID := int64Value(payload["teacher_remote_user_id"], row.TeacherUserID)
	if teacherUserID != row.TeacherUserID {
		return StudentProgressPayload{}, "", time.Time{}, fmt.Errorf("legacy progress course_id=%d student_user_id=%d teacher id mismatch", row.CourseID, row.StudentUserID)
	}
	updatedAt := parseTimestampValue(payload["updated_at"], row.UpdatedAt)
	payloadCourseSubject := firstNonEmpty(optionalString(payload["course_subject"]), row.CourseSubject)
	litPercent := int(int64Value(payload["lit_percent"], int64(row.LitPercent)))
	if litPercent < 0 {
		litPercent = 0
	}
	if litPercent > 100 {
		litPercent = 100
	}
	easyPassedCount := int(int64Value(payload["easy_passed_count"], int64(row.EasyPassedCount)))
	mediumPassedCount := int(int64Value(payload["medium_passed_count"], int64(row.MediumPassedCount)))
	hardPassedCount := int(int64Value(payload["hard_passed_count"], int64(row.HardPassedCount)))
	if easyPassedCount < 0 || mediumPassedCount < 0 || hardPassedCount < 0 {
		return StudentProgressPayload{}, "", time.Time{}, fmt.Errorf("legacy progress course_id=%d student_user_id=%d kp_key=%q contains negative passed counts", row.CourseID, row.StudentUserID, kpKey)
	}
	return StudentProgressPayload{
		CourseID:            row.CourseID,
		CourseSubject:       payloadCourseSubject,
		KpKey:               kpKey,
		Lit:                 boolValue(payload["lit"], row.Lit),
		LitPercent:          litPercent,
		QuestionLevel:       firstNonEmpty(optionalString(payload["question_level"]), row.QuestionLevel),
		EasyPassedCount:     easyPassedCount,
		MediumPassedCount:   mediumPassedCount,
		HardPassedCount:     hardPassedCount,
		SummaryText:         firstNonEmpty(optionalString(payload["summary_text"]), row.SummaryText),
		SummaryRawResponse:  firstNonEmpty(optionalString(payload["summary_raw_response"]), row.SummaryRawResponse),
		SummaryValid:        nullableBoolValue(payload["summary_valid"], row.SummaryValid),
		TeacherRemoteUserID: row.TeacherUserID,
		StudentRemoteUserID: row.StudentUserID,
		UpdatedAt:           updatedAt.Format(time.RFC3339),
	}, kpKey, updatedAt, nil
}

func decodeStoredEnvelopeJSON(envelopeBytes []byte) (string, error) {
	trimmed := strings.TrimSpace(string(envelopeBytes))
	if trimmed == "" {
		return "", errors.New("envelope missing")
	}
	if decoded, err := base64.StdEncoding.DecodeString(trimmed); err == nil {
		decodedText := strings.TrimSpace(string(decoded))
		if decodedText != "" {
			return decodedText, nil
		}
	}
	return trimmed, nil
}

func messagesValue(raw interface{}) ([]SessionMessage, error) {
	values, ok := raw.([]interface{})
	if !ok {
		return nil, errors.New("messages must be a list")
	}
	result := make([]SessionMessage, 0, len(values))
	for _, value := range values {
		item, ok := value.(map[string]interface{})
		if !ok {
			continue
		}
		role := requiredString(item["role"])
		content := requiredString(item["content"])
		if role == "" || content == "" {
			continue
		}
		result = append(result, SessionMessage{
			Role:       role,
			Content:    content,
			RawContent: optionalString(item["raw_content"]),
			ParsedJSON: optionalString(item["parsed_json"]),
			Action:     optionalString(item["action"]),
			CreatedAt:  parseTimestampValue(item["created_at"], time.Now().UTC()).Format(time.RFC3339),
		})
	}
	return result, nil
}

func requiredString(value interface{}) string {
	if value == nil {
		return ""
	}
	switch typed := value.(type) {
	case string:
		return strings.TrimSpace(typed)
	default:
		return strings.TrimSpace(fmt.Sprintf("%v", typed))
	}
}

func optionalString(value interface{}) string {
	if value == nil {
		return ""
	}
	if typed, ok := value.(string); ok {
		return strings.TrimSpace(typed)
	}
	return strings.TrimSpace(fmt.Sprintf("%v", value))
}

func int64Value(value interface{}, fallback int64) int64 {
	switch typed := value.(type) {
	case nil:
		return fallback
	case float64:
		return int64(typed)
	case int64:
		return typed
	case int:
		return int64(typed)
	case json.Number:
		parsed, err := strconv.ParseInt(string(typed), 10, 64)
		if err == nil {
			return parsed
		}
	case string:
		parsed, err := strconv.ParseInt(strings.TrimSpace(typed), 10, 64)
		if err == nil {
			return parsed
		}
	}
	return fallback
}

func boolValue(value interface{}, fallback bool) bool {
	switch typed := value.(type) {
	case nil:
		return fallback
	case bool:
		return typed
	case float64:
		return typed != 0
	case int:
		return typed != 0
	case int64:
		return typed != 0
	case json.Number:
		parsed, err := strconv.ParseInt(string(typed), 10, 64)
		if err == nil {
			return parsed != 0
		}
	case string:
		trimmed := strings.TrimSpace(strings.ToLower(typed))
		switch trimmed {
		case "1", "true", "t", "yes", "y":
			return true
		case "0", "false", "f", "no", "n":
			return false
		}
	}
	return fallback
}

func nullableBoolValue(value interface{}, fallback *bool) *bool {
	if value == nil {
		return fallback
	}
	resolved := boolValue(value, fallback != nil && *fallback)
	return &resolved
}

func parseTimestampValue(value interface{}, fallback time.Time) time.Time {
	if timestamp := optionalTimestamp(value); timestamp != "" {
		parsed, err := time.Parse(time.RFC3339, timestamp)
		if err == nil {
			return parsed.UTC()
		}
	}
	return fallback.UTC()
}

func optionalTimestamp(value interface{}) string {
	text := optionalString(value)
	if text == "" {
		return ""
	}
	if parsed, err := time.Parse(time.RFC3339, text); err == nil {
		return parsed.UTC().Format(time.RFC3339)
	}
	if parsed, err := time.Parse("2006-01-02 15:04:05", text); err == nil {
		return parsed.UTC().Format(time.RFC3339)
	}
	return text
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		trimmed := strings.TrimSpace(value)
		if trimmed != "" {
			return trimmed
		}
	}
	return ""
}

func countUsers(db *sql.DB) int {
	if db == nil {
		return 0
	}
	var count int
	if err := db.QueryRow(`SELECT COUNT(*) FROM users`).Scan(&count); err != nil {
		return 0
	}
	return count
}

func backfillBundleVersionHashes(db *sql.DB, storageSvc *storage.Service) error {
	if db == nil || storageSvc == nil {
		return errors.New("database and storage service required")
	}
	rows, err := db.Query(
		`SELECT id, oss_path
		 FROM bundle_versions
		 ORDER BY id ASC`,
	)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var bundleVersionID int64
		var relPath string
		if err := rows.Scan(&bundleVersionID, &relPath); err != nil {
			return err
		}
		shaValue, err := hashFileSHA256(storageSvc.AbsolutePath(relPath))
		if err != nil {
			return fmt.Errorf("bundle version %d hash backfill failed: %w", bundleVersionID, err)
		}
		if _, err := db.Exec(
			`UPDATE bundle_versions
			 SET hash = ?
			 WHERE id = ?`,
			shaValue,
			bundleVersionID,
		); err != nil {
			return err
		}
	}
	return rows.Err()
}

func hashFileSHA256(absPath string) (string, error) {
	file, err := os.Open(absPath)
	if err != nil {
		return "", err
	}
	defer file.Close()
	hasher := sha256.New()
	if _, err := io.Copy(hasher, file); err != nil {
		return "", err
	}
	return fmt.Sprintf("%x", hasher.Sum(nil)), nil
}
