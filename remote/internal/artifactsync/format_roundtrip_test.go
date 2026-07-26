package artifactsync

import (
	"encoding/json"
	"reflect"
	"testing"
)

func TestBuildStudentKpArtifactZipRoundTripsJSONStringFields(t *testing.T) {
	payload := StudentKpArtifactPayload{
		Schema:              StudentKpArtifactSchema,
		CourseID:            10,
		CourseSubject:       "UK_MATH_7-13",
		KpKey:               "2.3",
		TeacherRemoteUserID: 9,
		StudentRemoteUserID: 11,
		StudentUsername:     "albert",
		UpdatedAt:           "2026-03-29T10:47:04Z",
		Sessions: []StudentSessionPayload{
			{
				SessionSyncID:          "session-1",
				CourseID:               10,
				CourseSubject:          "UK_MATH_7-13",
				KpKey:                  "2.3",
				StartedAt:              "2026-03-29T10:00:00Z",
				StudentRemoteUserID:    11,
				StudentUsername:        "albert",
				TeacherRemoteUserID:    9,
				UpdatedAt:              "2026-03-29T10:47:04Z",
				ControlStateJSON:       `{"mode":"REVIEW"}`,
				EvidenceStateJSON:      `{"easy_passed_count":1}`,
				ControlStateUpdatedAt:  "2026-03-29T10:47:04Z",
				EvidenceStateUpdatedAt: "2026-03-29T10:47:04Z",
				Messages: []SessionMessage{
					{
						Role:       "assistant",
						Content:    "ok",
						ParsedJSON: `{"finished":true}`,
						CreatedAt:  "2026-03-29T10:47:04Z",
					},
				},
			},
		},
	}

	bytesValue, _, err := BuildStudentKpArtifactZip(payload)
	if err != nil {
		t.Fatalf("BuildStudentKpArtifactZip error = %v", err)
	}
	decoded, _, err := ReadStudentKpArtifactPayload(bytesValue)
	if err != nil {
		t.Fatalf("ReadStudentKpArtifactPayload error = %v", err)
	}
	if got := decoded.Sessions[0].ControlStateJSON; got != `{"mode":"REVIEW"}` {
		t.Fatalf("ControlStateJSON = %q", got)
	}
	if got := decoded.Sessions[0].EvidenceStateJSON; got != `{"easy_passed_count":1}` {
		t.Fatalf("EvidenceStateJSON = %q", got)
	}
	if got := decoded.Sessions[0].Messages[0].ParsedJSON; got != `{"finished":true}` {
		t.Fatalf("ParsedJSON = %q", got)
	}
}

func TestStudentKpArtifactPayloadMapRoundTripPreservesUnknownFields(t *testing.T) {
	payload := map[string]interface{}{
		"schema":                 StudentKpArtifactSchema,
		"course_id":              json.Number("10"),
		"course_subject":         "UK_MATH_7-13",
		"kp_key":                 "2.3",
		"teacher_remote_user_id": json.Number("9"),
		"student_remote_user_id": json.Number("11"),
		"student_username":       "albert",
		"updated_at":             "2026-07-26T10:47:04Z",
		"future_top_level_payload": map[string]interface{}{
			"mode":            "keep-me",
			"large_integer":   json.Number("9007199254740993"),
			"precise_decimal": json.Number("0.12345678901234567890"),
		},
		"progress": map[string]interface{}{
			"course_id":              json.Number("10"),
			"kp_key":                 "2.3",
			"lit":                    true,
			"lit_percent":            json.Number("120"),
			"mastery_level":          json.Number("4"),
			"teacher_remote_user_id": json.Number("9"),
			"student_remote_user_id": json.Number("11"),
			"updated_at":             "2026-07-26T10:45:00Z",
		},
		"mistakes": []interface{}{
			map[string]interface{}{
				"mistake_tag":     "sign error",
				"mistake_tag_key": "sign error",
				"evidence_json":   `{"source":"review"}`,
				"occurrences":     json.Number("3"),
				"future_field":    "preserve-me",
			},
		},
		"sessions": []interface{}{
			map[string]interface{}{
				"session_sync_id":        "session-1",
				"course_id":              json.Number("10"),
				"kp_key":                 "2.3",
				"started_at":             "2026-07-26T10:00:00Z",
				"student_remote_user_id": json.Number("11"),
				"teacher_remote_user_id": json.Number("9"),
				"updated_at":             "2026-07-26T10:47:04Z",
				"control_state_json":     `{"mode":"REVIEW"}`,
				"evidence_state_json":    `{"easy_passed_count":1}`,
				"future_session_field":   "preserve-session",
				"messages": []interface{}{
					map[string]interface{}{
						"role":         "assistant",
						"content":      "  preserve surrounding whitespace  ",
						"parsed_json":  `{"finished":true}`,
						"created_at":   "2026-07-26T10:47:04Z",
						"future_field": "preserve-message",
					},
				},
			},
		},
	}

	bytesValue, builtSHA, err := BuildStudentKpArtifactZipFromMap(payload)
	if err != nil {
		t.Fatalf("BuildStudentKpArtifactZipFromMap error = %v", err)
	}
	decoded, readSHA, err := ReadStudentKpArtifactPayloadMap(bytesValue)
	if err != nil {
		t.Fatalf("ReadStudentKpArtifactPayloadMap error = %v", err)
	}
	if builtSHA != readSHA {
		t.Fatalf("read sha256 = %q, want %q", readSHA, builtSHA)
	}
	if !reflect.DeepEqual(decoded, payload) {
		t.Fatalf("round-trip payload mismatch:\ngot:  %#v\nwant: %#v", decoded, payload)
	}
}
