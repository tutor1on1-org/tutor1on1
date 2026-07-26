package storage

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestSaveRelativePathIgnoresStaleLegacyTempFile(t *testing.T) {
	service := newTestService(t)
	relPath := "student_kp/17/23/algebra.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.zip"
	absPath := service.AbsolutePath(relPath)
	if err := os.MkdirAll(filepath.Dir(absPath), 0750); err != nil {
		t.Fatalf("MkdirAll() error = %v", err)
	}
	if err := os.WriteFile(absPath+".tmp", []byte("stale"), 0640); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
	if err := os.WriteFile(
		absPath+studentKpGCMarkerSuffix,
		[]byte("stale marker"),
		0640,
	); err != nil {
		t.Fatalf("WriteFile() marker error = %v", err)
	}

	_, _, err := service.SaveRelativePath(relPath, bytes.NewReader([]byte("artifact")))
	if err != nil {
		t.Fatalf("SaveRelativePath() error = %v", err)
	}
	got, err := os.ReadFile(absPath)
	if err != nil {
		t.Fatalf("ReadFile() error = %v", err)
	}
	if string(got) != "artifact" {
		t.Fatalf("saved artifact = %q, want artifact", string(got))
	}
	assertFileExists(t, absPath+studentKpGCMarkerSuffix, false)
}

func TestRemoveUnreferencedStudentKpArtifactsHonorsGraceAndScope(t *testing.T) {
	service := newTestService(t)
	now := time.Now().UTC()
	old := now.Add(-2 * time.Hour)
	cutoff := now.Add(-time.Hour)
	versionSHA := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

	referenced := writeTestStorageFile(
		t,
		service,
		"student_kp/17/23/referenced."+versionSHA+".zip",
		old,
	)
	orphan := writeTestStorageFile(
		t,
		service,
		"student_kp/17/23/orphan."+versionSHA+".zip",
		old,
	)
	fresh := writeTestStorageFile(
		t,
		service,
		"student_kp/17/23/fresh."+versionSHA+".zip",
		now,
	)
	cutover := writeTestStorageFile(
		t,
		service,
		"student_kp/_cutover/run-1/17/23/cutover.zip",
		old,
	)
	referencedLegacy := writeTestStorageFile(
		t,
		service,
		"student_kp/17/23/referenced-legacy.zip",
		old,
	)
	orphanLegacy := writeTestStorageFile(
		t,
		service,
		"student_kp/17/23/orphan-legacy.zip",
		old,
	)
	legacyTemp := writeTestStorageFile(
		t,
		service,
		"student_kp/17/23/orphan."+versionSHA+".zip.tmp",
		old,
	)
	uniqueTemp := writeTestStorageFile(
		t,
		service,
		"student_kp/17/23/orphan."+versionSHA+".zip.tmp-1234",
		old,
	)
	referencedMarker := writeTestStorageFile(
		t,
		service,
		"student_kp/17/23/referenced."+
			versionSHA+
			".zip"+
			studentKpGCMarkerSuffix,
		old,
	)

	removed, err := service.RemoveUnreferencedStudentKpArtifacts(
		map[string]struct{}{
			`student_kp\17\23\referenced.` + versionSHA + `.zip`: {},
			"student_kp/17/23/referenced-legacy.zip":             {},
		},
		cutoff,
	)
	if err != nil {
		t.Fatalf("RemoveUnreferencedStudentKpArtifacts() error = %v", err)
	}
	if removed != 2 {
		t.Fatalf("first sweep removed = %d, want 2 stale temp files", removed)
	}

	assertFileExists(t, referenced, true)
	assertFileExists(t, orphan, true)
	assertFileExists(t, fresh, true)
	assertFileExists(t, cutover, true)
	assertFileExists(t, referencedLegacy, true)
	assertFileExists(t, orphanLegacy, true)
	assertFileExists(t, legacyTemp, false)
	assertFileExists(t, uniqueTemp, false)
	assertFileExists(t, referencedMarker, false)

	removed, err = service.RemoveUnreferencedStudentKpArtifacts(
		map[string]struct{}{
			`student_kp\17\23\referenced.` + versionSHA + `.zip`: {},
			"student_kp/17/23/referenced-legacy.zip":             {},
		},
		now.Add(time.Hour),
	)
	if err != nil {
		t.Fatalf("second RemoveUnreferencedStudentKpArtifacts() error = %v", err)
	}
	if removed != 3 {
		t.Fatalf("second sweep removed = %d, want 3 orphan artifacts", removed)
	}
	assertFileExists(t, referenced, true)
	assertFileExists(t, orphan, false)
	assertFileExists(t, fresh, false)
	assertFileExists(t, cutover, true)
	assertFileExists(t, referencedLegacy, true)
	assertFileExists(t, orphanLegacy, false)
	assertFileExists(t, orphan+studentKpGCMarkerSuffix, false)
	assertFileExists(t, fresh+studentKpGCMarkerSuffix, false)
	assertFileExists(t, orphanLegacy+studentKpGCMarkerSuffix, false)
}

func newTestService(t *testing.T) *Service {
	t.Helper()
	service, err := New(Config{
		Root:           t.TempDir(),
		BundleMaxBytes: 1 << 20,
	})
	if err != nil {
		t.Fatalf("New() error = %v", err)
	}
	return service
}

func writeTestStorageFile(
	t *testing.T,
	service *Service,
	relPath string,
	modifiedAt time.Time,
) string {
	t.Helper()
	absPath := service.AbsolutePath(relPath)
	if err := os.MkdirAll(filepath.Dir(absPath), 0750); err != nil {
		t.Fatalf("MkdirAll() error = %v", err)
	}
	if err := os.WriteFile(absPath, []byte(relPath), 0640); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}
	if err := os.Chtimes(absPath, modifiedAt, modifiedAt); err != nil {
		t.Fatalf("Chtimes() error = %v", err)
	}
	return absPath
}

func assertFileExists(t *testing.T, absPath string, want bool) {
	t.Helper()
	_, err := os.Stat(absPath)
	got := err == nil
	if err != nil && !os.IsNotExist(err) {
		t.Fatalf("Stat(%q) error = %v", absPath, err)
	}
	if got != want {
		t.Fatalf("file %q exists = %v, want %v", absPath, got, want)
	}
}
