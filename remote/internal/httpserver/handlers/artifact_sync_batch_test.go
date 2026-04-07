package handlers

import (
	"archive/zip"
	"bytes"
	"database/sql"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"family_teacher_remote/internal/config"
	storepkg "family_teacher_remote/internal/db"
	"family_teacher_remote/internal/storage"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gofiber/fiber/v2"
)

func TestDownloadBatchUsesSingleBulkQueryAndPreservesRequestOrder(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	storageRoot := t.TempDir()
	storageSvc, err := storage.New(storage.Config{
		Root:           storageRoot,
		BundleMaxBytes: 1 << 20,
	})
	if err != nil {
		t.Fatalf("storage.New() error = %v", err)
	}

	artifactA := "student_kp:3001:200:1.1"
	artifactB := "student_kp:3001:200:1.2"
	relPathA := "student_kp/3001/200/1.1.zip"
	relPathB := "student_kp/3001/200/1.2.zip"
	bytesA := []byte("artifact-a-zip")
	bytesB := []byte("artifact-b-zip")
	if err := os.MkdirAll(filepath.Dir(storageSvc.AbsolutePath(relPathA)), 0750); err != nil {
		t.Fatalf("MkdirAll A error = %v", err)
	}
	if err := os.MkdirAll(filepath.Dir(storageSvc.AbsolutePath(relPathB)), 0750); err != nil {
		t.Fatalf("MkdirAll B error = %v", err)
	}
	if err := os.WriteFile(storageSvc.AbsolutePath(relPathA), bytesA, 0640); err != nil {
		t.Fatalf("WriteFile A error = %v", err)
	}
	if err := os.WriteFile(storageSvc.AbsolutePath(relPathB), bytesB, 0640); err != nil {
		t.Fatalf("WriteFile B error = %v", err)
	}

	userID := int64(901)
	mock.ExpectQuery(`(?s)SELECT artifact_id, artifact_class, course_id, teacher_user_id, COALESCE\(student_user_id, 0\), COALESCE\(kp_key, ''\), COALESCE\(bundle_version_id, 0\), storage_rel_path, sha256, last_modified\s+FROM artifact_state1_items\s+WHERE user_id = \? AND artifact_id IN \(\?,\?\)`).
		WithArgs(userID, artifactB, artifactA).
		WillReturnRows(
			sqlmock.NewRows([]string{
				"artifact_id",
				"artifact_class",
				"course_id",
				"teacher_user_id",
				"student_user_id",
				"kp_key",
				"bundle_version_id",
				"storage_rel_path",
				"sha256",
				"last_modified",
			}).
				AddRow(artifactA, "student_kp", int64(200), int64(901), int64(3001), "1.1", int64(0), relPathA, "sha-a", time.Date(2026, 4, 1, 10, 0, 0, 0, time.UTC)).
				AddRow(artifactB, "student_kp", int64(200), int64(901), int64(3001), "1.2", int64(0), relPathB, "sha-b", time.Date(2026, 4, 1, 10, 1, 0, 0, time.UTC)),
		)

	app := buildArtifactSyncBatchTestApp(db, storageSvc, []string{"test-secret"})
	token := signTestJWT(t, "test-secret", userID, true)
	request := httptest.NewRequest(
		http.MethodPost,
		"/api/artifacts/download-batch",
		bytes.NewBufferString(`{"artifact_ids":["`+artifactB+`","`+artifactA+`"]}`),
	)
	request.Header.Set("Authorization", "Bearer "+token)
	request.Header.Set("Content-Type", "application/json")
	response, err := app.Test(request)
	if err != nil {
		t.Fatalf("app.Test() error = %v", err)
	}
	defer response.Body.Close()

	if response.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(response.Body)
		t.Fatalf("status = %d, want %d (body=%q)", response.StatusCode, http.StatusOK, string(body))
	}
	if got := response.Header.Get("X-Artifact-Batch-Count"); got != "2" {
		t.Fatalf("X-Artifact-Batch-Count = %q, want %q", got, "2")
	}
	bodyBytes, err := io.ReadAll(response.Body)
	if err != nil {
		t.Fatalf("ReadAll() error = %v", err)
	}

	archiveReader, err := zip.NewReader(bytes.NewReader(bodyBytes), int64(len(bodyBytes)))
	if err != nil {
		t.Fatalf("zip.NewReader() error = %v", err)
	}
	manifestItems := decodeBatchManifestItems(t, archiveReader)
	if got := manifestItems[0].ArtifactID; got != artifactB {
		t.Fatalf("manifest item[0] artifact_id = %q, want %q", got, artifactB)
	}
	if got := manifestItems[1].ArtifactID; got != artifactA {
		t.Fatalf("manifest item[1] artifact_id = %q, want %q", got, artifactA)
	}

	entryBytes := readBatchEntries(t, archiveReader)
	if got := string(entryBytes[batchArtifactEntryName(artifactA)]); got != string(bytesA) {
		t.Fatalf("artifact A bytes = %q, want %q", got, string(bytesA))
	}
	if got := string(entryBytes[batchArtifactEntryName(artifactB)]); got != string(bytesB) {
		t.Fatalf("artifact B bytes = %q, want %q", got, string(bytesB))
	}
	assertSQLMockExpectations(t, mock)
}

func buildArtifactSyncBatchTestApp(
	db *sql.DB,
	storageSvc *storage.Service,
	jwtSecrets []string,
) *fiber.App {
	deps := Dependencies{
		Config: config.Config{
			JWTVerifySecrets: jwtSecrets,
		},
		Store:   &storepkg.Store{DB: db},
		Storage: storageSvc,
	}
	artifactSync := NewArtifactSyncHandler(deps)
	app := fiber.New()
	app.Post("/api/artifacts/download-batch", artifactSync.DownloadBatch)
	return app
}

func decodeBatchManifestItems(
	t *testing.T,
	archiveReader *zip.Reader,
) []artifactBatchManifestItemResponse {
	t.Helper()
	for _, file := range archiveReader.File {
		if file.Name != "manifest.json" {
			continue
		}
		reader, err := file.Open()
		if err != nil {
			t.Fatalf("manifest open error = %v", err)
		}
		defer reader.Close()
		body, err := io.ReadAll(reader)
		if err != nil {
			t.Fatalf("manifest read error = %v", err)
		}
		var payload struct {
			Items []artifactBatchManifestItemResponse `json:"items"`
		}
		if err := json.Unmarshal(body, &payload); err != nil {
			t.Fatalf("manifest json error = %v", err)
		}
		return payload.Items
	}
	t.Fatal("manifest.json missing from batch archive")
	return nil
}

func readBatchEntries(
	t *testing.T,
	archiveReader *zip.Reader,
) map[string][]byte {
	t.Helper()
	entryBytes := make(map[string][]byte)
	for _, file := range archiveReader.File {
		if file.Name == "manifest.json" {
			continue
		}
		reader, err := file.Open()
		if err != nil {
			t.Fatalf("entry %q open error = %v", file.Name, err)
		}
		body, err := io.ReadAll(reader)
		_ = reader.Close()
		if err != nil {
			t.Fatalf("entry %q read error = %v", file.Name, err)
		}
		entryBytes[file.Name] = body
	}
	return entryBytes
}
