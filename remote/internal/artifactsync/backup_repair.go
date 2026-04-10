package artifactsync

import (
	"bufio"
	"bytes"
	"compress/gzip"
	"crypto/ecdh"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"

	"family_teacher_remote/internal/storage"
)

type BackupStudentCourseRepairSummary struct {
	StudentUsername           string
	StudentUserID             int64
	CourseID                  int64
	TeacherUserID             int64
	SessionRowsFromBackup     int
	ProgressRowsFromBackup    int
	ArtifactsRebuilt          int
	ArtifactsWithProgress     int
	ExplicitProgressArtifacts int
	DerivedProgressArtifacts  int
	CurrentArtifactRows       int
	State2BeforeTeacher       string
	State2AfterTeacher        string
	State2BeforeStudent       string
	State2AfterStudent        string
}

type BackupStudentCourseRepairOptions struct {
	BackupGzipPath   string
	StudentUsername  string
	StudentPassword  string
	CourseID         int64
	Apply            bool
	DeriveMissing    bool
	APIBaseURL       string
	DeviceKey        string
	DeviceName       string
	EmitDir          string
}

type backupRepairArtifactWrite struct {
	artifactID      string
	teacherUserID   int64
	kpKey           string
	storageRelPath  string
	sha             string
	lastModifiedUTC time.Time
	zipBytes        []byte
}

type backupUserRecord struct {
	UserID   int64
	Username string
}

type backupUserKeyRecord struct {
	UserID        int64
	PublicKey     string
	EncPrivateKey string
}

type backupRepairGroupKey struct {
	StudentUserID int64
	CourseID      int64
	KpKey         string
}

type backupRepairGroup struct {
	TeacherUserID int64
	StudentName   string
	CourseSubject string
	Progress      *StudentProgressPayload
	Sessions      []StudentSessionPayload
	UpdatedAt     time.Time
}

type backupRepairScanTarget struct {
	StudentUserID   int64
	StudentUsername string
	CourseID        int64
	PrivateKey      UserKeyRecord
}

type backupRepairPassRule struct {
	easyWeight    float64
	mediumWeight  float64
	hardWeight    float64
	passThreshold float64
}

func RepairStudentCourseArtifactsFromBackup(
	db *sql.DB,
	storageSvc *storage.Service,
	options BackupStudentCourseRepairOptions,
) (BackupStudentCourseRepairSummary, error) {
	if db == nil {
		return BackupStudentCourseRepairSummary{}, errors.New("database required")
	}
	if storageSvc == nil {
		return BackupStudentCourseRepairSummary{}, errors.New("storage service required")
	}
	if strings.TrimSpace(options.BackupGzipPath) == "" {
		return BackupStudentCourseRepairSummary{}, errors.New("backup gzip path required")
	}
	username := strings.TrimSpace(strings.ToLower(options.StudentUsername))
	if username == "" {
		return BackupStudentCourseRepairSummary{}, errors.New("student username required")
	}
	if options.StudentPassword == "" {
		return BackupStudentCourseRepairSummary{}, errors.New("student password required")
	}
	if options.CourseID <= 0 {
		return BackupStudentCourseRepairSummary{}, errors.New("course id required")
	}

	target, err := scanBackupRepairTarget(
		options.BackupGzipPath,
		username,
		options.CourseID,
	)
	if err != nil {
		return BackupStudentCourseRepairSummary{}, err
	}

	privateKey, err := DecryptPrivateKey(
		UserKeyRecord{
			UserID:        target.StudentUserID,
			PublicKey:     target.PrivateKey.PublicKey,
			EncPrivateKey: target.PrivateKey.EncPrivateKey,
		},
		options.StudentPassword,
	)
	if err != nil {
		return BackupStudentCourseRepairSummary{}, fmt.Errorf(
			"decrypt backup private key for %s: %w",
			target.StudentUsername,
			err,
		)
	}

	sessionRows, progressRows, err := scanBackupRepairRows(
		options.BackupGzipPath,
		target.StudentUserID,
		options.CourseID,
		target.StudentUsername,
	)
	if err != nil {
		return BackupStudentCourseRepairSummary{}, err
	}

	groups, explicitProgressCount, derivedProgressCount, teacherUserID, err :=
		buildBackupRepairGroups(
			sessionRows,
			progressRows,
			target.StudentUserID,
			target.StudentUsername,
			privateKey,
			options.DeriveMissing,
		)
	if err != nil {
		return BackupStudentCourseRepairSummary{}, err
	}
	if len(groups) == 0 {
		return BackupStudentCourseRepairSummary{}, errors.New("backup produced no repairable artifacts")
	}
	if strings.TrimSpace(options.EmitDir) != "" {
		if err := emitBackupRepairArtifacts(options.EmitDir, groups); err != nil {
			return BackupStudentCourseRepairSummary{}, err
		}
	}

	state2BeforeTeacher := ""
	state2AfterTeacher := ""
	state2BeforeStudent := ""
	state2AfterStudent := ""
	currentArtifactRows, err := countCurrentStudentCourseArtifacts(
		db,
		target.StudentUserID,
		options.CourseID,
	)
	if err != nil {
		return BackupStudentCourseRepairSummary{}, err
	}
	if teacherUserID > 0 {
		state2BeforeTeacher, err = ReadState2(db, teacherUserID)
		if err != nil {
			return BackupStudentCourseRepairSummary{}, err
		}
		state2AfterTeacher = state2BeforeTeacher
	}
	state2BeforeStudent, err = ReadState2(db, target.StudentUserID)
	if err != nil {
		return BackupStudentCourseRepairSummary{}, err
	}
	state2AfterStudent = state2BeforeStudent

	summary := BackupStudentCourseRepairSummary{
		StudentUsername:           target.StudentUsername,
		StudentUserID:             target.StudentUserID,
		CourseID:                  options.CourseID,
		TeacherUserID:             teacherUserID,
		SessionRowsFromBackup:     len(sessionRows),
		ProgressRowsFromBackup:    len(progressRows),
		ArtifactsRebuilt:          len(groups),
		ArtifactsWithProgress:     explicitProgressCount + derivedProgressCount,
		ExplicitProgressArtifacts: explicitProgressCount,
		DerivedProgressArtifacts:  derivedProgressCount,
		CurrentArtifactRows:       currentArtifactRows,
		State2BeforeTeacher:       state2BeforeTeacher,
		State2AfterTeacher:        state2AfterTeacher,
		State2BeforeStudent:       state2BeforeStudent,
		State2AfterStudent:        state2AfterStudent,
	}
	if !options.Apply {
		return summary, nil
	}

	if strings.TrimSpace(options.APIBaseURL) != "" {
		if err := uploadBackupRepairGroupsViaAPI(options, groups); err != nil {
			return BackupStudentCourseRepairSummary{}, err
		}
		if err := RefreshUsersForCourse(db, options.CourseID); err != nil {
			return BackupStudentCourseRepairSummary{}, err
		}
	} else {
		if err := applyBackupRepairGroups(
			db,
			storageSvc,
			target.StudentUserID,
			options.CourseID,
			groups,
		); err != nil {
			return BackupStudentCourseRepairSummary{}, err
		}
	}

	if teacherUserID > 0 {
		state2AfterTeacher, err = ReadState2(db, teacherUserID)
		if err != nil {
			return BackupStudentCourseRepairSummary{}, err
		}
	}
	state2AfterStudent, err = ReadState2(db, target.StudentUserID)
	if err != nil {
		return BackupStudentCourseRepairSummary{}, err
	}
	summary.State2AfterTeacher = state2AfterTeacher
	summary.State2AfterStudent = state2AfterStudent
	return summary, nil
}

func scanBackupRepairTarget(
	backupGzipPath string,
	studentUsername string,
	courseID int64,
) (backupRepairScanTarget, error) {
	file, err := os.Open(strings.TrimSpace(backupGzipPath))
	if err != nil {
		return backupRepairScanTarget{}, err
	}
	defer file.Close()
	reader, err := gzip.NewReader(file)
	if err != nil {
		return backupRepairScanTarget{}, err
	}
	defer reader.Close()

	scanner := bufio.NewScanner(reader)
	scanner.Buffer(make([]byte, 0, 1024*1024), 16*1024*1024)
	var user backupUserRecord
	userKeysByUserID := map[int64]backupUserKeyRecord{}
	for scanner.Scan() {
		line := scanner.Text()
		switch {
		case strings.HasPrefix(line, "INSERT INTO `users` VALUES "):
			tuples, err := parseMySQLInsertTuples(line)
			if err != nil {
				return backupRepairScanTarget{}, err
			}
			for _, tuple := range tuples {
				if len(tuple) < 2 {
					continue
				}
				usernameValue, _ := tuple[1].String()
				if strings.TrimSpace(strings.ToLower(usernameValue)) != studentUsername {
					continue
				}
				userID, err := tuple[0].Int64()
				if err != nil {
					return backupRepairScanTarget{}, err
				}
				user = backupUserRecord{
					UserID:   userID,
					Username: strings.TrimSpace(usernameValue),
				}
				break
			}
		case strings.HasPrefix(line, "INSERT INTO `user_keys` VALUES "):
			tuples, err := parseMySQLInsertTuples(line)
			if err != nil {
				return backupRepairScanTarget{}, err
			}
			for _, tuple := range tuples {
				if len(tuple) < 4 {
					continue
				}
				userID, err := tuple[1].Int64()
				if err != nil {
					return backupRepairScanTarget{}, err
				}
				publicKey, _ := tuple[2].String()
				encPrivateKey, _ := tuple[3].String()
				userKeysByUserID[userID] = backupUserKeyRecord{
					UserID:        userID,
					PublicKey:     publicKey,
					EncPrivateKey: encPrivateKey,
				}
			}
		}
	}
	if err := scanner.Err(); err != nil {
		return backupRepairScanTarget{}, err
	}
	if user.UserID <= 0 {
		return backupRepairScanTarget{}, fmt.Errorf(
			"backup user %q not found for course %d",
			studentUsername,
			courseID,
		)
	}
	userKey, ok := userKeysByUserID[user.UserID]
	if !ok {
		return backupRepairScanTarget{}, fmt.Errorf(
			"backup user key missing for %s",
			user.Username,
		)
	}
	return backupRepairScanTarget{
		StudentUserID:   user.UserID,
		StudentUsername: user.Username,
		CourseID:        courseID,
		PrivateKey: UserKeyRecord{
			UserID:        userKey.UserID,
			PublicKey:     userKey.PublicKey,
			EncPrivateKey: userKey.EncPrivateKey,
		},
	}, nil
}

func scanBackupRepairRows(
	backupGzipPath string,
	studentUserID int64,
	courseID int64,
	studentUsername string,
) ([]legacySessionRow, []legacyProgressRow, error) {
	file, err := os.Open(strings.TrimSpace(backupGzipPath))
	if err != nil {
		return nil, nil, err
	}
	defer file.Close()
	reader, err := gzip.NewReader(file)
	if err != nil {
		return nil, nil, err
	}
	defer reader.Close()

	scanner := bufio.NewScanner(reader)
	scanner.Buffer(make([]byte, 0, 1024*1024), 16*1024*1024)
	sessions := make([]legacySessionRow, 0, 64)
	progressRows := make([]legacyProgressRow, 0, 64)
	for scanner.Scan() {
		line := scanner.Text()
		switch {
		case strings.HasPrefix(line, "INSERT INTO `session_text_sync` VALUES "):
			tuples, err := parseMySQLInsertTuples(line)
			if err != nil {
				return nil, nil, err
			}
			for _, tuple := range tuples {
				if len(tuple) < 10 {
					continue
				}
				rowCourseID, err := tuple[2].Int64()
				if err != nil || rowCourseID != courseID {
					continue
				}
				rowStudentID, err := tuple[4].Int64()
				if err != nil || rowStudentID != studentUserID {
					continue
				}
				updatedAt, err := tuple[7].Time()
				if err != nil {
					return nil, nil, err
				}
				sessionSyncID, _ := tuple[1].String()
				envelope, err := tuple[9].Bytes()
				if err != nil {
					return nil, nil, err
				}
				teacherUserID, err := tuple[3].Int64()
				if err != nil {
					return nil, nil, err
				}
				sessions = append(sessions, legacySessionRow{
					SessionSyncID: sessionSyncID,
					CourseID:      rowCourseID,
					TeacherUserID: teacherUserID,
					StudentUserID: rowStudentID,
					StudentName:   studentUsername,
					UpdatedAt:     updatedAt,
					Envelope:      envelope,
				})
			}
		case strings.HasPrefix(line, "INSERT INTO `progress_sync` VALUES "):
			tuples, err := parseMySQLInsertTuples(line)
			if err != nil {
				return nil, nil, err
			}
			for _, tuple := range tuples {
				if len(tuple) < 13 {
					continue
				}
				rowCourseID, err := tuple[1].Int64()
				if err != nil || rowCourseID != courseID {
					continue
				}
				rowStudentID, err := tuple[3].Int64()
				if err != nil || rowStudentID != studentUserID {
					continue
				}
				updatedAt, err := tuple[11].Time()
				if err != nil {
					return nil, nil, err
				}
				kpKey, _ := tuple[4].String()
				questionLevel, _ := tuple[7].String()
				summaryText, _ := tuple[8].String()
				summaryRawResponse, _ := tuple[9].String()
				summaryValid, err := tuple[10].BoolPointer()
				if err != nil {
					return nil, nil, err
				}
				envelope, err := tuple[12].Bytes()
				if err != nil {
					return nil, nil, err
				}
				teacherUserID, err := tuple[2].Int64()
				if err != nil {
					return nil, nil, err
				}
				lit, err := tuple[5].Bool()
				if err != nil {
					return nil, nil, err
				}
				litPercent, err := tuple[6].Int()
				if err != nil {
					return nil, nil, err
				}
				progressRows = append(progressRows, legacyProgressRow{
					CourseID:           rowCourseID,
					TeacherUserID:      teacherUserID,
					StudentUserID:      rowStudentID,
					StudentName:        studentUsername,
					KpKey:              kpKey,
					Lit:                lit,
					LitPercent:         litPercent,
					QuestionLevel:      questionLevel,
					SummaryText:        summaryText,
					SummaryRawResponse: summaryRawResponse,
					SummaryValid:       summaryValid,
					UpdatedAt:          updatedAt,
					Envelope:           envelope,
				})
			}
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, nil, err
	}
	return sessions, progressRows, nil
}

func buildBackupRepairGroups(
	sessionRows []legacySessionRow,
	progressRows []legacyProgressRow,
	studentUserID int64,
	studentUsername string,
	privateKey *ecdh.PrivateKey,
	deriveMissing bool,
) (map[backupRepairGroupKey]*backupRepairGroup, int, int, int64, error) {
	groups := map[backupRepairGroupKey]*backupRepairGroup{}
	for _, row := range sessionRows {
		envelopeJSON, err := decodeStoredEnvelopeJSON(row.Envelope)
		if err != nil {
			return nil, 0, 0, 0, err
		}
		payload, err := DecryptEnvelopeJSON(envelopeJSON, studentUserID, privateKey)
		if err != nil {
			return nil, 0, 0, 0, err
		}
		sessionPayload, kpKey, updatedAt, err := buildStudentSessionPayload(payload, row)
		if err != nil {
			return nil, 0, 0, 0, err
		}
		key := backupRepairGroupKey{
			StudentUserID: studentUserID,
			CourseID:      row.CourseID,
			KpKey:         kpKey,
		}
		group := groups[key]
		if group == nil {
			group = &backupRepairGroup{
				TeacherUserID: row.TeacherUserID,
				StudentName:   firstNonEmpty(strings.TrimSpace(row.StudentName), studentUsername),
				UpdatedAt:     updatedAt,
			}
			groups[key] = group
		}
		if updatedAt.After(group.UpdatedAt) {
			group.UpdatedAt = updatedAt
		}
		if group.CourseSubject == "" {
			group.CourseSubject = strings.TrimSpace(sessionPayload.CourseSubject)
		}
		group.Sessions = append(group.Sessions, sessionPayload)
	}

	explicitProgressCount := 0
	for _, row := range progressRows {
		envelopeJSON, err := decodeStoredEnvelopeJSON(row.Envelope)
		if err != nil {
			return nil, 0, 0, 0, err
		}
		payload, err := DecryptEnvelopeJSON(envelopeJSON, studentUserID, privateKey)
		if err != nil {
			return nil, 0, 0, 0, err
		}
		progressPayload, kpKey, updatedAt, err := buildStudentProgressPayload(payload, row)
		if err != nil {
			return nil, 0, 0, 0, err
		}
		key := backupRepairGroupKey{
			StudentUserID: studentUserID,
			CourseID:      row.CourseID,
			KpKey:         kpKey,
		}
		group := groups[key]
		if group == nil {
			group = &backupRepairGroup{
				TeacherUserID: row.TeacherUserID,
				StudentName:   firstNonEmpty(strings.TrimSpace(row.StudentName), studentUsername),
				UpdatedAt:     updatedAt,
			}
			groups[key] = group
		}
		group.Progress = &progressPayload
		if updatedAt.After(group.UpdatedAt) {
			group.UpdatedAt = updatedAt
		}
		if group.CourseSubject == "" {
			group.CourseSubject = strings.TrimSpace(progressPayload.CourseSubject)
		}
		explicitProgressCount++
	}

	derivedProgressCount := 0
	var teacherUserID int64
	for _, group := range groups {
		sort.Slice(group.Sessions, func(i, j int) bool {
			if group.Sessions[i].SessionSyncID != group.Sessions[j].SessionSyncID {
				return group.Sessions[i].SessionSyncID < group.Sessions[j].SessionSyncID
			}
			return group.Sessions[i].UpdatedAt < group.Sessions[j].UpdatedAt
		})
		if teacherUserID <= 0 && group.TeacherUserID > 0 {
			teacherUserID = group.TeacherUserID
		}
		if group.Progress != nil || !deriveMissing {
			continue
		}
		derived := deriveProgressFromSessionEvidence(
			group.Sessions,
			studentUserID,
			group.TeacherUserID,
		)
		if derived == nil {
			continue
		}
		group.Progress = derived
		if group.CourseSubject == "" {
			group.CourseSubject = strings.TrimSpace(derived.CourseSubject)
		}
		updatedAt, err := time.Parse(time.RFC3339, derived.UpdatedAt)
		if err == nil && updatedAt.After(group.UpdatedAt) {
			group.UpdatedAt = updatedAt
		}
		derivedProgressCount++
	}
	return groups, explicitProgressCount, derivedProgressCount, teacherUserID, nil
}

func deriveProgressFromSessionEvidence(
	sessions []StudentSessionPayload,
	studentUserID int64,
	teacherUserID int64,
) *StudentProgressPayload {
	if len(sessions) == 0 {
		return nil
	}
	best := derivedEvidenceProgress{}
	latestUpdatedAt := ""
	courseID := sessions[0].CourseID
	courseSubject := strings.TrimSpace(sessions[0].CourseSubject)
	kpKey := strings.TrimSpace(sessions[0].KpKey)
	for _, session := range sessions {
		if courseSubject == "" {
			courseSubject = strings.TrimSpace(session.CourseSubject)
		}
		if kpKey == "" {
			kpKey = strings.TrimSpace(session.KpKey)
		}
		if strings.TrimSpace(session.UpdatedAt) > latestUpdatedAt {
			latestUpdatedAt = strings.TrimSpace(session.UpdatedAt)
		}
		evidenceText := strings.TrimSpace(session.EvidenceStateJSON)
		if evidenceText == "" {
			continue
		}
		var evidence derivedEvidenceProgress
		if err := json.Unmarshal([]byte(evidenceText), &evidence); err != nil {
			continue
		}
		best.EasyPassedCount = maxRepairInt(best.EasyPassedCount, evidence.EasyPassedCount)
		best.MediumPassedCount = maxRepairInt(best.MediumPassedCount, evidence.MediumPassedCount)
		best.HardPassedCount = maxRepairInt(best.HardPassedCount, evidence.HardPassedCount)
		if evidence.LastAssessedAction != "" {
			best.LastAssessedAction = evidence.LastAssessedAction
		}
		if len(evidence.LastEvidence) > 0 {
			best.LastEvidence = evidence.LastEvidence
		}
	}
	if best.EasyPassedCount == 0 &&
		best.MediumPassedCount == 0 &&
		best.HardPassedCount == 0 {
		return nil
	}
	passRule := backupRepairPassRule{
		easyWeight:    0.25,
		mediumWeight:  0.5,
		hardWeight:    1.0,
		passThreshold: 1.0,
	}
	questionLevel := ""
	if value, ok := best.LastEvidence["difficulty"].(string); ok {
		questionLevel = strings.TrimSpace(value)
	}
	if latestUpdatedAt == "" {
		latestUpdatedAt = time.Now().UTC().Format(time.RFC3339)
	}
	return &StudentProgressPayload{
		CourseID:            courseID,
		CourseSubject:       courseSubject,
		KpKey:               kpKey,
		Lit:                 passRule.litForCounts(best.EasyPassedCount, best.MediumPassedCount, best.HardPassedCount),
		LitPercent:          passRule.litPercentForCounts(best.EasyPassedCount, best.MediumPassedCount, best.HardPassedCount),
		QuestionLevel:       questionLevel,
		EasyPassedCount:     best.EasyPassedCount,
		MediumPassedCount:   best.MediumPassedCount,
		HardPassedCount:     best.HardPassedCount,
		TeacherRemoteUserID: teacherUserID,
		StudentRemoteUserID: studentUserID,
		UpdatedAt:           latestUpdatedAt,
	}
}

func applyBackupRepairGroups(
	db *sql.DB,
	storageSvc *storage.Service,
	studentUserID int64,
	courseID int64,
	groups map[backupRepairGroupKey]*backupRepairGroup,
) error {
	existingRows, err := listStudentCourseArtifacts(db, studentUserID, courseID)
	if err != nil {
		return err
	}
	keepRelPaths := make(map[string]struct{}, len(groups))
	writes, err := buildBackupRepairArtifactWrites(groups)
	if err != nil {
		return err
	}
	for _, write := range writes {
		keepRelPaths[write.storageRelPath] = struct{}{}
		if _, _, err := storageSvc.SaveRelativePath(
			write.storageRelPath,
			bytes.NewReader(write.zipBytes),
		); err != nil {
			return err
		}
	}

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
		`DELETE FROM student_kp_artifacts WHERE student_user_id = ? AND course_id = ?`,
		studentUserID,
		courseID,
	); err != nil {
		return err
	}
	for _, write := range writes {
		if err := UpsertStudentKpArtifactTx(
			tx,
			write.artifactID,
			courseID,
			write.teacherUserID,
			studentUserID,
			write.kpKey,
			write.storageRelPath,
			write.sha,
			write.lastModifiedUTC,
		); err != nil {
			return err
		}
	}
	if err := tx.Commit(); err != nil {
		return err
	}
	committed = true

	for _, existing := range existingRows {
		if _, ok := keepRelPaths[existing.StorageRelPath]; ok {
			continue
		}
		if err := storageSvc.RemoveRelativePath(existing.StorageRelPath); err != nil {
			return err
		}
	}
	return RefreshUsersForCourse(db, courseID)
}

func buildBackupRepairArtifactWrites(
	groups map[backupRepairGroupKey]*backupRepairGroup,
) ([]backupRepairArtifactWrite, error) {
	writes := make([]backupRepairArtifactWrite, 0, len(groups))
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
			return nil, err
		}
		writes = append(writes, backupRepairArtifactWrite{
			artifactID: ArtifactIDForStudentKp(
				key.StudentUserID,
				key.CourseID,
				key.KpKey,
			),
			teacherUserID: group.TeacherUserID,
			kpKey:         key.KpKey,
			storageRelPath: StudentKpStorageRelPath(
				key.StudentUserID,
				key.CourseID,
				key.KpKey,
			),
			sha:             zipSHA,
			lastModifiedUTC: group.UpdatedAt.UTC(),
			zipBytes:        zipBytes,
		})
	}
	return writes, nil
}

type existingArtifactRow struct {
	ArtifactID      string
	StorageRelPath  string
}

func listStudentCourseArtifacts(
	db *sql.DB,
	studentUserID int64,
	courseID int64,
) ([]existingArtifactRow, error) {
	rows, err := db.Query(
		`SELECT artifact_id, storage_rel_path
		 FROM student_kp_artifacts
		 WHERE student_user_id = ? AND course_id = ?`,
		studentUserID,
		courseID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := []existingArtifactRow{}
	for rows.Next() {
		var row existingArtifactRow
		if err := rows.Scan(&row.ArtifactID, &row.StorageRelPath); err != nil {
			return nil, err
		}
		result = append(result, row)
	}
	return result, rows.Err()
}

func countCurrentStudentCourseArtifacts(
	db *sql.DB,
	studentUserID int64,
	courseID int64,
) (int, error) {
	row := db.QueryRow(
		`SELECT COUNT(*)
		 FROM student_kp_artifacts
		 WHERE student_user_id = ? AND course_id = ?`,
		studentUserID,
		courseID,
	)
	var count int
	if err := row.Scan(&count); err != nil {
		return 0, err
	}
	return count, nil
}

type derivedEvidenceProgress struct {
	EasyPassedCount   int                    `json:"easy_passed_count"`
	MediumPassedCount int                    `json:"medium_passed_count"`
	HardPassedCount   int                    `json:"hard_passed_count"`
	LastAssessedAction string                `json:"last_assessed_action"`
	LastEvidence      map[string]interface{} `json:"last_evidence"`
}

func (r backupRepairPassRule) litForCounts(
	easyCount int,
	mediumCount int,
	hardCount int,
) bool {
	return r.scoreForCounts(easyCount, mediumCount, hardCount) >= r.passThreshold
}

func (r backupRepairPassRule) litPercentForCounts(
	easyCount int,
	mediumCount int,
	hardCount int,
) int {
	if r.passThreshold <= 0 {
		return 100
	}
	percent := int((r.scoreForCounts(easyCount, mediumCount, hardCount) / r.passThreshold * 100) + 0.5)
	if percent < 0 {
		return 0
	}
	if percent > 100 {
		return 100
	}
	return percent
}

func (r backupRepairPassRule) scoreForCounts(
	easyCount int,
	mediumCount int,
	hardCount int,
) float64 {
	return float64(easyCount)*r.easyWeight +
		float64(mediumCount)*r.mediumWeight +
		float64(hardCount)*r.hardWeight
}

type mySQLDumpValue struct {
	isNull bool
	text   string
}

func (v mySQLDumpValue) String() (string, bool) {
	if v.isNull {
		return "", false
	}
	return v.text, true
}

func (v mySQLDumpValue) Bytes() ([]byte, error) {
	if v.isNull {
		return nil, errors.New("null bytes value")
	}
	return []byte(v.text), nil
}

func (v mySQLDumpValue) Int64() (int64, error) {
	if v.isNull {
		return 0, errors.New("null int64 value")
	}
	return strconv.ParseInt(strings.TrimSpace(v.text), 10, 64)
}

func (v mySQLDumpValue) Int() (int, error) {
	value, err := v.Int64()
	return int(value), err
}

func (v mySQLDumpValue) Bool() (bool, error) {
	if v.isNull {
		return false, errors.New("null bool value")
	}
	switch strings.TrimSpace(v.text) {
	case "0":
		return false, nil
	case "1":
		return true, nil
	default:
		return false, fmt.Errorf("invalid bool value %q", v.text)
	}
}

func (v mySQLDumpValue) BoolPointer() (*bool, error) {
	if v.isNull {
		return nil, nil
	}
	value, err := v.Bool()
	if err != nil {
		return nil, err
	}
	return &value, nil
}

func (v mySQLDumpValue) Time() (time.Time, error) {
	if v.isNull {
		return time.Time{}, errors.New("null time value")
	}
	return time.ParseInLocation("2006-01-02 15:04:05", v.text, time.UTC)
}

func parseMySQLInsertTuples(line string) ([][]mySQLDumpValue, error) {
	valuesIndex := strings.Index(line, " VALUES ")
	if valuesIndex < 0 {
		return nil, errors.New("insert line missing VALUES")
	}
	input := line[valuesIndex+8:]
	result := make([][]mySQLDumpValue, 0, 16)
	index := 0
	for index < len(input) {
		for index < len(input) && (input[index] == ' ' || input[index] == '\t' || input[index] == '\r' || input[index] == '\n' || input[index] == ',') {
			index++
		}
		if index >= len(input) || input[index] == ';' {
			break
		}
		if input[index] != '(' {
			return nil, fmt.Errorf("expected tuple start at %d", index)
		}
		index++
		tuple := make([]mySQLDumpValue, 0, 8)
		for {
			value, nextIndex, err := parseMySQLDumpValue(input, index)
			if err != nil {
				return nil, err
			}
			tuple = append(tuple, value)
			index = nextIndex
			if index >= len(input) {
				return nil, errors.New("unterminated tuple")
			}
			switch input[index] {
			case ',':
				index++
				continue
			case ')':
				index++
				result = append(result, tuple)
			default:
				return nil, fmt.Errorf("unexpected tuple delimiter %q", input[index])
			}
			break
		}
	}
	return result, nil
}

func parseMySQLDumpValue(
	input string,
	start int,
) (mySQLDumpValue, int, error) {
	index := start
	for index < len(input) && (input[index] == ' ' || input[index] == '\t' || input[index] == '\r' || input[index] == '\n') {
		index++
	}
	if index >= len(input) {
		return mySQLDumpValue{}, index, io.EOF
	}
	if strings.HasPrefix(input[index:], "NULL") {
		next := index + 4
		if next >= len(input) || input[next] == ',' || input[next] == ')' {
			return mySQLDumpValue{isNull: true}, next, nil
		}
	}
	if strings.HasPrefix(input[index:], "_binary ") {
		index += len("_binary ")
	}
	if input[index] == '\'' {
		value, nextIndex, err := parseMySQLQuotedString(input, index)
		if err != nil {
			return mySQLDumpValue{}, nextIndex, err
		}
		return mySQLDumpValue{text: value}, nextIndex, nil
	}
	next := index
	for next < len(input) && input[next] != ',' && input[next] != ')' {
		next++
	}
	return mySQLDumpValue{text: strings.TrimSpace(input[index:next])}, next, nil
}

func parseMySQLQuotedString(input string, start int) (string, int, error) {
	if start >= len(input) || input[start] != '\'' {
		return "", start, errors.New("quoted string must start with quote")
	}
	index := start + 1
	var builder strings.Builder
	for index < len(input) {
		ch := input[index]
		if ch == '\\' {
			if index+1 >= len(input) {
				return "", index, errors.New("unfinished escape sequence")
			}
			next := input[index+1]
			switch next {
			case '0':
				builder.WriteByte(0)
			case 'b':
				builder.WriteByte('\b')
			case 'n':
				builder.WriteByte('\n')
			case 'r':
				builder.WriteByte('\r')
			case 't':
				builder.WriteByte('\t')
			case 'Z':
				builder.WriteByte(26)
			default:
				builder.WriteByte(next)
			}
			index += 2
			continue
		}
		if ch == '\'' {
			return builder.String(), index + 1, nil
		}
		builder.WriteByte(ch)
		index++
	}
	return "", index, errors.New("unterminated quoted string")
}

func maxRepairInt(left int, right int) int {
	if right > left {
		return right
	}
	return left
}

func backupRepairArtifactFilename(artifactID string) string {
	replacer := strings.NewReplacer(
		"/", "_",
		"\\", "_",
		":", "_",
		"?", "_",
		"*", "_",
		"\"", "_",
		"<", "_",
		">", "_",
		"|", "_",
	)
	trimmed := strings.TrimSpace(replacer.Replace(artifactID))
	if trimmed == "" {
		return "artifact"
	}
	return trimmed
}

func uploadBackupRepairGroupsViaAPI(
	options BackupStudentCourseRepairOptions,
	groups map[backupRepairGroupKey]*backupRepairGroup,
) error {
	baseURL := strings.TrimRight(strings.TrimSpace(options.APIBaseURL), "/")
	if baseURL == "" {
		return errors.New("api base url required for api upload")
	}
	deviceKey := strings.TrimSpace(options.DeviceKey)
	if deviceKey == "" {
		deviceKey = "backup-repair-codex"
	}
	deviceName := strings.TrimSpace(options.DeviceName)
	if deviceName == "" {
		deviceName = "Backup Repair Codex"
	}
	accessToken, err := loginBackupRepairAPI(
		baseURL,
		options.StudentUsername,
		options.StudentPassword,
		deviceKey,
		deviceName,
	)
	if err != nil {
		return err
	}
	writes, err := buildBackupRepairArtifactWrites(groups)
	if err != nil {
		return err
	}
	client := &http.Client{Timeout: 60 * time.Second}
	for _, write := range writes {
		if _, _, err := ReadStudentKpArtifactPayload(write.zipBytes); err != nil {
			return fmt.Errorf("local artifact self-check failed for %s: %w", write.artifactID, err)
		}
		if err := uploadBackupRepairArtifact(
			client,
			baseURL,
			accessToken,
			deviceKey,
			write,
		); err != nil {
			return err
		}
	}
	return nil
}

func emitBackupRepairArtifacts(
	dirPath string,
	groups map[backupRepairGroupKey]*backupRepairGroup,
) error {
	writes, err := buildBackupRepairArtifactWrites(groups)
	if err != nil {
		return err
	}
	dirPath = strings.TrimSpace(dirPath)
	if dirPath == "" {
		return errors.New("emit dir required")
	}
	if err := os.MkdirAll(dirPath, 0750); err != nil {
		return err
	}
	manifestItems := make([]map[string]interface{}, 0, len(writes))
	for _, write := range writes {
		fileName := backupRepairArtifactFilename(write.artifactID) + ".zip"
		absPath := dirPath + string(os.PathSeparator) + fileName
		if err := os.WriteFile(absPath, write.zipBytes, 0640); err != nil {
			return err
		}
		manifestItems = append(manifestItems, map[string]interface{}{
			"artifact_id": write.artifactID,
			"sha256":      write.sha,
			"file_name":   fileName,
		})
	}
	manifestBytes, err := json.MarshalIndent(map[string]interface{}{
		"items": manifestItems,
	}, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(dirPath+string(os.PathSeparator)+"manifest.json", manifestBytes, 0640)
}

func loginBackupRepairAPI(
	baseURL string,
	username string,
	password string,
	deviceKey string,
	deviceName string,
) (string, error) {
	requestBody, err := json.Marshal(map[string]interface{}{
		"username":    strings.TrimSpace(username),
		"password":    password,
		"device_key":  deviceKey,
		"device_name": deviceName,
	})
	if err != nil {
		return "", err
	}
	response, err := http.Post(
		baseURL+"/api/auth/login",
		"application/json",
		bytes.NewReader(requestBody),
	)
	if err != nil {
		return "", err
	}
	defer response.Body.Close()
	body, err := io.ReadAll(response.Body)
	if err != nil {
		return "", err
	}
	if response.StatusCode != http.StatusOK {
		return "", fmt.Errorf(
			"api login failed: status=%d body=%s",
			response.StatusCode,
			strings.TrimSpace(string(body)),
		)
	}
	var decoded map[string]interface{}
	if err := json.Unmarshal(body, &decoded); err != nil {
		return "", err
	}
	token, _ := decoded["access_token"].(string)
	token = strings.TrimSpace(token)
	if token == "" {
		return "", errors.New("api login returned empty access token")
	}
	return token, nil
}

func uploadBackupRepairArtifact(
	client *http.Client,
	baseURL string,
	accessToken string,
	deviceKey string,
	write backupRepairArtifactWrite,
) error {
	body := &bytes.Buffer{}
	form := multipart.NewWriter(body)
	fields := map[string]string{
		"artifact_id":      write.artifactID,
		"sha256":           write.sha,
		"base_sha256":      "",
		"overwrite_server": "true",
	}
	for key, value := range fields {
		if err := form.WriteField(key, value); err != nil {
			return err
		}
	}
	fileWriter, err := form.CreateFormFile(
		"artifact",
		backupRepairArtifactFilename(write.artifactID)+".zip",
	)
	if err != nil {
		return err
	}
	if _, err := fileWriter.Write(write.zipBytes); err != nil {
		return err
	}
	if err := form.Close(); err != nil {
		return err
	}
	request, err := http.NewRequest(
		http.MethodPost,
		baseURL+"/api/artifacts/upload",
		body,
	)
	if err != nil {
		return err
	}
	request.Header.Set("Authorization", "Bearer "+accessToken)
	request.Header.Set("X-Device-Id", deviceKey)
	request.Header.Set("Content-Type", form.FormDataContentType())
	response, err := client.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	responseBody, err := io.ReadAll(response.Body)
	if err != nil {
		return err
	}
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf(
			"artifact upload failed for %s: status=%d body=%s",
			write.artifactID,
			response.StatusCode,
			strings.TrimSpace(string(responseBody)),
		)
	}
	return nil
}
