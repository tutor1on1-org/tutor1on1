package artifactsync

import (
	"strings"
	"testing"
)

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
