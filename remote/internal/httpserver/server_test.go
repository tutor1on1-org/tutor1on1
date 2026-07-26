package httpserver

import (
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestReadReferencedStudentKpArtifactPathsIncludesCanonicalAndState1Paths(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New() error = %v", err)
	}
	defer db.Close()

	mock.ExpectQuery(`(?s)SELECT storage_rel_path\s+FROM student_kp_artifacts\s+UNION\s+SELECT storage_rel_path\s+FROM artifact_state1_items\s+WHERE artifact_class = 'student_kp'`).
		WillReturnRows(
			sqlmock.NewRows([]string{"storage_rel_path"}).
				AddRow("student_kp/17/23/canonical.zip").
				AddRow("student_kp/17/23/state1.zip").
				AddRow("   "),
		)

	got, err := readReferencedStudentKpArtifactPaths(db)
	if err != nil {
		t.Fatalf("readReferencedStudentKpArtifactPaths() error = %v", err)
	}
	for _, relPath := range []string{
		"student_kp/17/23/canonical.zip",
		"student_kp/17/23/state1.zip",
	} {
		if _, ok := got[relPath]; !ok {
			t.Fatalf("referenced path %q missing from %#v", relPath, got)
		}
	}
	if len(got) != 2 {
		t.Fatalf("referenced path count = %d, want 2", len(got))
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("sqlmock expectations: %v", err)
	}
}
