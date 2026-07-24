package artifactsync

import (
	"strings"
	"testing"
)

func TestBackfillCutoverProgressFromSessions(t *testing.T) {
	key := studentKpGroupKey{
		StudentUserID: 11,
		CourseID:      10,
		KpKey:         "2.3.5.1",
	}
	group := &studentKpGroup{
		TeacherUserID: 9,
		Sessions: []StudentSessionPayload{
			{
				SessionSyncID:       "session-1",
				CourseID:            10,
				CourseSubject:       "UK_MATH_7-13",
				KpKey:               "2.3.5.1",
				TeacherRemoteUserID: 9,
				StudentRemoteUserID: 11,
				UpdatedAt:           "2026-03-29T10:47:04Z",
				EvidenceStateJSON:   `{"easy_passed_count":1,"medium_passed_count":1,"hard_passed_count":1}`,
			},
		},
	}

	backfillCutoverProgressFromSessions(
		map[studentKpGroupKey]*studentKpGroup{key: group},
	)

	if group.Progress == nil {
		t.Fatal("cutover progress was not derived from session evidence")
	}
	if !group.Progress.Lit || group.Progress.LitPercent != 100 {
		t.Fatalf(
			"derived lit fields = lit:%v percent:%d, want true/100",
			group.Progress.Lit,
			group.Progress.LitPercent,
		)
	}
	if group.CourseSubject != "UK_MATH_7-13" {
		t.Fatalf("course subject = %q, want UK_MATH_7-13", group.CourseSubject)
	}
}

func TestNormalizeLegacyStudentCredentialsRejectsDuplicateUsername(t *testing.T) {
	_, err := normalizeLegacyStudentCredentials([]LegacyStudentCredential{
		{Username: "Albert", Password: "1234"},
		{Username: "albert", Password: "abcd"},
	})
	if err == nil {
		t.Fatal("expected duplicate credential error")
	}
	if !strings.Contains(err.Error(), "duplicate student credential") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestValidateLegacyStudentCredentialCoverageRejectsMissingCredential(t *testing.T) {
	err := validateLegacyStudentCredentialCoverage(
		[]legacyStudentUser{
			{UserID: 1, Username: "albert"},
			{UserID: 2, Username: "dennis"},
			{UserID: 3, Username: "charlie"},
		},
		map[string]LegacyStudentCredential{
			"albert": {Username: "albert", Password: "1234"},
			"dennis": {Username: "dennis", Password: "1234"},
		},
	)
	if err == nil {
		t.Fatal("expected missing credential error")
	}
	if !strings.Contains(err.Error(), "charlie") {
		t.Fatalf("expected error to mention missing user, got %v", err)
	}
}

func TestValidateLegacyStudentCredentialCoverageRejectsUnexpectedCredential(t *testing.T) {
	err := validateLegacyStudentCredentialCoverage(
		[]legacyStudentUser{
			{UserID: 1, Username: "albert"},
			{UserID: 2, Username: "dennis"},
		},
		map[string]LegacyStudentCredential{
			"albert": {Username: "albert", Password: "1234"},
			"dennis": {Username: "dennis", Password: "1234"},
			"eve":    {Username: "eve", Password: "1234"},
		},
	)
	if err == nil {
		t.Fatal("expected unexpected credential error")
	}
	if !strings.Contains(err.Error(), "eve") {
		t.Fatalf("expected error to mention unexpected credential, got %v", err)
	}
}

func TestCutoverStudentKpStorageRelPathUsesRunIDNamespace(t *testing.T) {
	got := CutoverStudentKpStorageRelPath("cutover-123", 17, 23, "kp/A B")
	want := "student_kp/_cutover/cutover-123/17/23/kp%2FA%20B.zip"
	if got != want {
		t.Fatalf("CutoverStudentKpStorageRelPath() = %q, want %q", got, want)
	}
}
