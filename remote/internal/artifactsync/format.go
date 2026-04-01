package artifactsync

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/url"
	"path"
	"sort"
	"strconv"
	"strings"
	"time"
)

const (
	StudentKpArtifactSchema = "student_kp_artifact_v1"
	State2Version           = "artifact_state2_v1"
	PayloadEntryName        = "payload.json"
)

type State2Item struct {
	ArtifactID string
	SHA256     string
}

type SessionMessage struct {
	Role       string `json:"role"`
	Content    string `json:"content"`
	RawContent string `json:"raw_content,omitempty"`
	ParsedJSON string `json:"parsed_json,omitempty"`
	Action     string `json:"action,omitempty"`
	CreatedAt  string `json:"created_at"`
}

type StudentSessionPayload struct {
	SessionSyncID          string           `json:"session_sync_id"`
	CourseID               int64            `json:"course_id"`
	CourseSubject          string           `json:"course_subject,omitempty"`
	KpKey                  string           `json:"kp_key"`
	KpTitle                string           `json:"kp_title,omitempty"`
	SessionTitle           string           `json:"session_title,omitempty"`
	StartedAt              string           `json:"started_at"`
	EndedAt                string           `json:"ended_at,omitempty"`
	SummaryText            string           `json:"summary_text,omitempty"`
	ControlStateJSON       string           `json:"control_state_json,omitempty"`
	ControlStateUpdatedAt  string           `json:"control_state_updated_at,omitempty"`
	EvidenceStateJSON      string           `json:"evidence_state_json,omitempty"`
	EvidenceStateUpdatedAt string           `json:"evidence_state_updated_at,omitempty"`
	StudentRemoteUserID    int64            `json:"student_remote_user_id"`
	StudentUsername        string           `json:"student_username,omitempty"`
	TeacherRemoteUserID    int64            `json:"teacher_remote_user_id"`
	UpdatedAt              string           `json:"updated_at"`
	Messages               []SessionMessage `json:"messages"`
}

type StudentProgressPayload struct {
	CourseID            int64  `json:"course_id"`
	CourseSubject       string `json:"course_subject,omitempty"`
	KpKey               string `json:"kp_key"`
	Lit                 bool   `json:"lit"`
	LitPercent          int    `json:"lit_percent"`
	QuestionLevel       string `json:"question_level,omitempty"`
	EasyPassedCount     int    `json:"easy_passed_count"`
	MediumPassedCount   int    `json:"medium_passed_count"`
	HardPassedCount     int    `json:"hard_passed_count"`
	SummaryText         string `json:"summary_text,omitempty"`
	SummaryRawResponse  string `json:"summary_raw_response,omitempty"`
	SummaryValid        *bool  `json:"summary_valid,omitempty"`
	TeacherRemoteUserID int64  `json:"teacher_remote_user_id"`
	StudentRemoteUserID int64  `json:"student_remote_user_id"`
	UpdatedAt           string `json:"updated_at"`
}

type StudentKpArtifactPayload struct {
	Schema              string                  `json:"schema"`
	CourseID            int64                   `json:"course_id"`
	CourseSubject       string                  `json:"course_subject,omitempty"`
	KpKey               string                  `json:"kp_key"`
	TeacherRemoteUserID int64                   `json:"teacher_remote_user_id"`
	StudentRemoteUserID int64                   `json:"student_remote_user_id"`
	StudentUsername     string                  `json:"student_username,omitempty"`
	UpdatedAt           string                  `json:"updated_at"`
	Progress            *StudentProgressPayload `json:"progress,omitempty"`
	Sessions            []StudentSessionPayload `json:"sessions"`
}

func ArtifactIDForCourseBundle(courseID int64) string {
	return fmt.Sprintf("course_bundle:%d", courseID)
}

func ParseCourseBundleArtifactID(artifactID string) (int64, error) {
	trimmed := strings.TrimSpace(artifactID)
	if !strings.HasPrefix(trimmed, "course_bundle:") {
		return 0, fmt.Errorf("invalid course bundle artifact id: %s", artifactID)
	}
	rawCourseID := strings.TrimPrefix(trimmed, "course_bundle:")
	courseID, err := strconv.ParseInt(strings.TrimSpace(rawCourseID), 10, 64)
	if err != nil || courseID <= 0 {
		return 0, fmt.Errorf("invalid course bundle artifact id: %s", artifactID)
	}
	return courseID, nil
}

func ArtifactIDForStudentKp(studentUserID int64, courseID int64, kpKey string) string {
	return fmt.Sprintf("student_kp:%d:%d:%s", studentUserID, courseID, strings.TrimSpace(kpKey))
}

func ParseStudentKpArtifactID(artifactID string) (int64, int64, string, error) {
	trimmed := strings.TrimSpace(artifactID)
	parts := strings.SplitN(trimmed, ":", 4)
	if len(parts) != 4 || parts[0] != "student_kp" {
		return 0, 0, "", fmt.Errorf("invalid student kp artifact id: %s", artifactID)
	}
	studentUserID, err := strconv.ParseInt(strings.TrimSpace(parts[1]), 10, 64)
	if err != nil || studentUserID <= 0 {
		return 0, 0, "", fmt.Errorf("invalid student kp artifact id: %s", artifactID)
	}
	courseID, err := strconv.ParseInt(strings.TrimSpace(parts[2]), 10, 64)
	if err != nil || courseID <= 0 {
		return 0, 0, "", fmt.Errorf("invalid student kp artifact id: %s", artifactID)
	}
	kpKey := strings.TrimSpace(parts[3])
	if kpKey == "" {
		return 0, 0, "", fmt.Errorf("invalid student kp artifact id: %s", artifactID)
	}
	return studentUserID, courseID, kpKey, nil
}

func StudentKpStorageRelPath(studentUserID int64, courseID int64, kpKey string) string {
	escapedKpKey := url.PathEscape(strings.TrimSpace(kpKey))
	return path.Join(
		"student_kp",
		fmt.Sprintf("%d", studentUserID),
		fmt.Sprintf("%d", courseID),
		escapedKpKey+".zip",
	)
}

func CutoverStudentKpStorageRelPath(
	runID string,
	studentUserID int64,
	courseID int64,
	kpKey string,
) string {
	trimmedRunID := strings.TrimSpace(runID)
	if trimmedRunID == "" {
		return StudentKpStorageRelPath(studentUserID, courseID, kpKey)
	}
	escapedKpKey := url.PathEscape(strings.TrimSpace(kpKey))
	return path.Join(
		"student_kp",
		"_cutover",
		trimmedRunID,
		fmt.Sprintf("%d", studentUserID),
		fmt.Sprintf("%d", courseID),
		escapedKpKey+".zip",
	)
}

func BuildState2(items []State2Item) string {
	normalized := make([]State2Item, 0, len(items))
	for _, item := range items {
		artifactID := strings.TrimSpace(item.ArtifactID)
		shaValue := strings.TrimSpace(item.SHA256)
		if artifactID == "" || shaValue == "" {
			continue
		}
		normalized = append(normalized, State2Item{
			ArtifactID: artifactID,
			SHA256:     shaValue,
		})
	}
	sort.Slice(normalized, func(i, j int) bool {
		if normalized[i].ArtifactID == normalized[j].ArtifactID {
			return normalized[i].SHA256 < normalized[j].SHA256
		}
		return normalized[i].ArtifactID < normalized[j].ArtifactID
	})
	var builder strings.Builder
	for _, item := range normalized {
		builder.WriteString(item.ArtifactID)
		builder.WriteByte('|')
		builder.WriteString(item.SHA256)
		builder.WriteByte('\n')
	}
	sum := sha256.Sum256([]byte(builder.String()))
	return State2Version + ":" + hex.EncodeToString(sum[:])
}

func BuildStudentKpArtifactZip(payload StudentKpArtifactPayload) ([]byte, string, error) {
	normalized, err := normalizeStudentKpArtifactPayload(payload)
	if err != nil {
		return nil, "", err
	}
	canonical, err := marshalCanonicalJSON(normalized)
	if err != nil {
		return nil, "", err
	}
	var buffer bytes.Buffer
	writer := zip.NewWriter(&buffer)
	header := &zip.FileHeader{
		Name:     PayloadEntryName,
		Method:   zip.Store,
		Modified: time.Unix(0, 0).UTC(),
	}
	header.SetMode(0600)
	entry, err := writer.CreateHeader(header)
	if err != nil {
		return nil, "", err
	}
	if _, err := entry.Write(canonical); err != nil {
		_ = writer.Close()
		return nil, "", err
	}
	if err := writer.Close(); err != nil {
		return nil, "", err
	}
	bytesValue := buffer.Bytes()
	sum := sha256.Sum256(bytesValue)
	return bytesValue, hex.EncodeToString(sum[:]), nil
}

func ReadStudentKpArtifactPayload(data []byte) (StudentKpArtifactPayload, string, error) {
	reader, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return StudentKpArtifactPayload{}, "", err
	}
	for _, file := range reader.File {
		if file.FileInfo().IsDir() {
			continue
		}
		if normalizeArchivePath(file.Name) != PayloadEntryName {
			continue
		}
		handle, err := file.Open()
		if err != nil {
			return StudentKpArtifactPayload{}, "", err
		}
		payloadBytes, err := io.ReadAll(handle)
		_ = handle.Close()
		if err != nil {
			return StudentKpArtifactPayload{}, "", err
		}
		var payload StudentKpArtifactPayload
		if err := json.Unmarshal(payloadBytes, &payload); err != nil {
			return StudentKpArtifactPayload{}, "", err
		}
		sum := sha256.Sum256(data)
		return payload, hex.EncodeToString(sum[:]), nil
	}
	return StudentKpArtifactPayload{}, "", errors.New("payload.json missing from student kp artifact")
}

func normalizeStudentKpArtifactPayload(payload StudentKpArtifactPayload) (map[string]interface{}, error) {
	kpKey := strings.TrimSpace(payload.KpKey)
	if payload.CourseID <= 0 || payload.StudentRemoteUserID <= 0 || payload.TeacherRemoteUserID <= 0 || kpKey == "" {
		return nil, errors.New("student kp artifact payload missing required identity fields")
	}
	sessions := make([]map[string]interface{}, 0, len(payload.Sessions))
	for _, session := range payload.Sessions {
		normalized, err := normalizeStudentSessionPayload(session)
		if err != nil {
			return nil, err
		}
		sessions = append(sessions, normalized)
	}
	sort.Slice(sessions, func(i, j int) bool {
		left := sessions[i]["session_sync_id"].(string)
		right := sessions[j]["session_sync_id"].(string)
		if left == right {
			leftUpdated, _ := sessions[i]["updated_at"].(string)
			rightUpdated, _ := sessions[j]["updated_at"].(string)
			return leftUpdated < rightUpdated
		}
		return left < right
	})
	result := map[string]interface{}{
		"schema":                 StudentKpArtifactSchema,
		"course_id":              payload.CourseID,
		"kp_key":                 kpKey,
		"teacher_remote_user_id": payload.TeacherRemoteUserID,
		"student_remote_user_id": payload.StudentRemoteUserID,
		"updated_at":             normalizeRequiredString(payload.UpdatedAt),
		"sessions":               sessions,
	}
	if subject := normalizeOptionalString(payload.CourseSubject); subject != "" {
		result["course_subject"] = subject
	}
	if username := normalizeOptionalString(payload.StudentUsername); username != "" {
		result["student_username"] = username
	}
	if payload.Progress != nil {
		normalized, err := normalizeStudentProgressPayload(*payload.Progress)
		if err != nil {
			return nil, err
		}
		result["progress"] = normalized
	}
	return result, nil
}

func normalizeStudentSessionPayload(payload StudentSessionPayload) (map[string]interface{}, error) {
	sessionSyncID := strings.TrimSpace(payload.SessionSyncID)
	kpKey := strings.TrimSpace(payload.KpKey)
	if sessionSyncID == "" || payload.CourseID <= 0 || payload.StudentRemoteUserID <= 0 || payload.TeacherRemoteUserID <= 0 || kpKey == "" {
		return nil, errors.New("student session payload missing required fields")
	}
	messages := make([]map[string]interface{}, 0, len(payload.Messages))
	for _, message := range payload.Messages {
		normalized := map[string]interface{}{
			"role":       normalizeRequiredString(message.Role),
			"content":    normalizeRequiredString(message.Content),
			"created_at": normalizeRequiredString(message.CreatedAt),
		}
		if raw := normalizeOptionalString(message.RawContent); raw != "" {
			normalized["raw_content"] = raw
		}
		if parsed := normalizeJSONText(message.ParsedJSON); parsed != nil {
			normalized["parsed_json"] = parsed
		}
		if action := normalizeOptionalString(message.Action); action != "" {
			normalized["action"] = action
		}
		messages = append(messages, normalized)
	}
	result := map[string]interface{}{
		"session_sync_id":        sessionSyncID,
		"course_id":              payload.CourseID,
		"kp_key":                 kpKey,
		"started_at":             normalizeRequiredString(payload.StartedAt),
		"student_remote_user_id": payload.StudentRemoteUserID,
		"teacher_remote_user_id": payload.TeacherRemoteUserID,
		"updated_at":             normalizeRequiredString(payload.UpdatedAt),
		"messages":               messages,
	}
	if subject := normalizeOptionalString(payload.CourseSubject); subject != "" {
		result["course_subject"] = subject
	}
	if kpTitle := normalizeOptionalString(payload.KpTitle); kpTitle != "" {
		result["kp_title"] = kpTitle
	}
	if title := normalizeOptionalString(payload.SessionTitle); title != "" {
		result["session_title"] = title
	}
	if endedAt := normalizeOptionalString(payload.EndedAt); endedAt != "" {
		result["ended_at"] = endedAt
	}
	if summary := normalizeOptionalString(payload.SummaryText); summary != "" {
		result["summary_text"] = summary
	}
	if control := normalizeJSONText(payload.ControlStateJSON); control != nil {
		result["control_state_json"] = control
	}
	if controlUpdatedAt := normalizeOptionalString(payload.ControlStateUpdatedAt); controlUpdatedAt != "" {
		result["control_state_updated_at"] = controlUpdatedAt
	}
	if evidence := normalizeJSONText(payload.EvidenceStateJSON); evidence != nil {
		result["evidence_state_json"] = evidence
	}
	if evidenceUpdatedAt := normalizeOptionalString(payload.EvidenceStateUpdatedAt); evidenceUpdatedAt != "" {
		result["evidence_state_updated_at"] = evidenceUpdatedAt
	}
	if username := normalizeOptionalString(payload.StudentUsername); username != "" {
		result["student_username"] = username
	}
	return result, nil
}

func normalizeStudentProgressPayload(payload StudentProgressPayload) (map[string]interface{}, error) {
	kpKey := strings.TrimSpace(payload.KpKey)
	if payload.CourseID <= 0 || payload.StudentRemoteUserID <= 0 || payload.TeacherRemoteUserID <= 0 || kpKey == "" {
		return nil, errors.New("student progress payload missing required fields")
	}
	result := map[string]interface{}{
		"course_id":              payload.CourseID,
		"kp_key":                 kpKey,
		"lit":                    payload.Lit,
		"lit_percent":            clampProgressPercent(payload.LitPercent),
		"easy_passed_count":      maxInt(payload.EasyPassedCount, 0),
		"medium_passed_count":    maxInt(payload.MediumPassedCount, 0),
		"hard_passed_count":      maxInt(payload.HardPassedCount, 0),
		"teacher_remote_user_id": payload.TeacherRemoteUserID,
		"student_remote_user_id": payload.StudentRemoteUserID,
		"updated_at":             normalizeRequiredString(payload.UpdatedAt),
	}
	if subject := normalizeOptionalString(payload.CourseSubject); subject != "" {
		result["course_subject"] = subject
	}
	if level := normalizeOptionalString(payload.QuestionLevel); level != "" {
		result["question_level"] = level
	}
	if summary := normalizeOptionalString(payload.SummaryText); summary != "" {
		result["summary_text"] = summary
	}
	if rawSummary := normalizeOptionalString(payload.SummaryRawResponse); rawSummary != "" {
		result["summary_raw_response"] = rawSummary
	}
	if payload.SummaryValid != nil {
		result["summary_valid"] = *payload.SummaryValid
	}
	return result, nil
}

func normalizeArchivePath(value string) string {
	normalized := path.Clean(strings.ReplaceAll(strings.TrimSpace(value), "\\", "/"))
	normalized = strings.TrimPrefix(normalized, "/")
	if normalized == "." {
		return ""
	}
	return normalized
}

func clampProgressPercent(value int) int {
	if value < 0 {
		return 0
	}
	if value > 100 {
		return 100
	}
	return value
}

func maxInt(value int, minimum int) int {
	if value < minimum {
		return minimum
	}
	return value
}

func normalizeRequiredString(value string) string {
	return strings.TrimSpace(value)
}

func normalizeOptionalString(value string) string {
	return strings.TrimSpace(value)
}

func normalizeJSONText(value string) interface{} {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return nil
	}
	var decoded interface{}
	if err := json.Unmarshal([]byte(trimmed), &decoded); err != nil {
		return trimmed
	}
	return normalizeCanonicalValue(decoded)
}

func normalizeCanonicalValue(value interface{}) interface{} {
	switch typed := value.(type) {
	case nil:
		return nil
	case string:
		trimmed := strings.TrimSpace(typed)
		if trimmed == "" {
			return nil
		}
		return trimmed
	case []interface{}:
		items := make([]interface{}, 0, len(typed))
		for _, inner := range typed {
			normalized := normalizeCanonicalValue(inner)
			if normalized == nil {
				continue
			}
			items = append(items, normalized)
		}
		if len(items) == 0 {
			return nil
		}
		return items
	case map[string]interface{}:
		next := map[string]interface{}{}
		for key, inner := range typed {
			normalized := normalizeCanonicalValue(inner)
			if normalized == nil {
				continue
			}
			next[key] = normalized
		}
		if len(next) == 0 {
			return nil
		}
		return next
	default:
		return value
	}
}

func marshalCanonicalJSON(value interface{}) ([]byte, error) {
	var buffer bytes.Buffer
	if err := writeCanonicalJSON(&buffer, value); err != nil {
		return nil, err
	}
	return buffer.Bytes(), nil
}

func writeCanonicalJSON(buffer *bytes.Buffer, value interface{}) error {
	switch typed := value.(type) {
	case nil:
		buffer.WriteString("null")
		return nil
	case bool:
		if typed {
			buffer.WriteString("true")
		} else {
			buffer.WriteString("false")
		}
		return nil
	case string:
		encoded, err := json.Marshal(typed)
		if err != nil {
			return err
		}
		buffer.Write(encoded)
		return nil
	case int:
		buffer.WriteString(fmt.Sprintf("%d", typed))
		return nil
	case int64:
		buffer.WriteString(fmt.Sprintf("%d", typed))
		return nil
	case float64:
		encoded, err := json.Marshal(typed)
		if err != nil {
			return err
		}
		buffer.Write(encoded)
		return nil
	case map[string]interface{}:
		keys := make([]string, 0, len(typed))
		for key := range typed {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		buffer.WriteByte('{')
		for index, key := range keys {
			if index > 0 {
				buffer.WriteByte(',')
			}
			encodedKey, err := json.Marshal(key)
			if err != nil {
				return err
			}
			buffer.Write(encodedKey)
			buffer.WriteByte(':')
			if err := writeCanonicalJSON(buffer, typed[key]); err != nil {
				return err
			}
		}
		buffer.WriteByte('}')
		return nil
	case []interface{}:
		buffer.WriteByte('[')
		for index, inner := range typed {
			if index > 0 {
				buffer.WriteByte(',')
			}
			if err := writeCanonicalJSON(buffer, inner); err != nil {
				return err
			}
		}
		buffer.WriteByte(']')
		return nil
	default:
		encoded, err := json.Marshal(typed)
		if err != nil {
			return err
		}
		buffer.Write(encoded)
		return nil
	}
}
