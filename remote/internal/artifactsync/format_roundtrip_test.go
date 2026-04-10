package artifactsync

import "testing"

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
