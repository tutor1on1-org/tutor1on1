package handlers

import (
	"archive/zip"
	"bytes"
	"database/sql"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"family_teacher_remote/internal/config"
	storepkg "family_teacher_remote/internal/db"
	"family_teacher_remote/internal/mailer"
	"family_teacher_remote/internal/storage"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gofiber/fiber/v2"
)

func TestUploadDraftCourseCreatesPendingRequestAndNotifiesSubjectAdmin(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	smtpServer, mailService := newApprovalNotificationTestMailer(t)
	defer smtpServer.Close()

	userID := int64(1901)
	courseID := int64(2901)
	bundleID := int64(3901)
	bundleVersionID := int64(4901)
	adminEmail := "course-admin@example.com"
	storageSvc, err := storage.New(storage.Config{
		Root:           t.TempDir(),
		BundleMaxBytes: 1 << 20,
	})
	if err != nil {
		t.Fatalf("storage.New() error = %v", err)
	}

	mock.ExpectQuery(`SELECT ta.user_id, c.id, c.subject\s+FROM bundles b`).
		WithArgs(bundleID).
		WillReturnRows(
			sqlmock.NewRows([]string{"user_id", "course_id", "subject"}).
				AddRow(userID, courseID, "Draft Math"),
		)
	mock.ExpectQuery(`SELECT id, version, hash, oss_path\s+FROM bundle_versions`).
		WithArgs(bundleID).
		WillReturnError(sql.ErrNoRows)
	mock.ExpectBegin()
	mock.ExpectExec(`INSERT INTO bundle_versions`).
		WithArgs(bundleID, 1, sqlmock.AnyArg(), "bundles/3901/1.zip").
		WillReturnResult(sqlmock.NewResult(bundleVersionID, 1))
	mock.ExpectQuery(`SELECT id, oss_path\s+FROM bundle_versions\s+WHERE bundle_id = \?`).
		WithArgs(bundleID).
		WillReturnRows(
			sqlmock.NewRows([]string{"id", "oss_path"}).
				AddRow(bundleVersionID, "bundles/3901/1.zip"),
		)
	mock.ExpectQuery(`SELECT approval_status\s+FROM course_catalog_entries`).
		WithArgs(courseID).
		WillReturnRows(sqlmock.NewRows([]string{"approval_status"}).AddRow("draft"))
	mock.ExpectExec(`(?s)INSERT INTO course_upload_requests.*ON DUPLICATE KEY UPDATE`).
		WithArgs(courseID, bundleID, bundleVersionID).
		WillReturnResult(sqlmock.NewResult(5901, 1))
	mock.ExpectExec(`UPDATE course_catalog_entries\s+SET approval_status = 'pending'\s+WHERE course_id = \?`).
		WithArgs(courseID).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectQuery(`SELECT DISTINCT u.email\s+FROM course_subject_labels csl`).
		WithArgs(courseID).
		WillReturnRows(sqlmock.NewRows([]string{"email"}).AddRow(adminEmail))
	mock.ExpectCommit()

	app := buildBundleUploadApprovalTestApp(
		db,
		storageSvc,
		[]string{"test-secret"},
		mailService,
	)
	token := signTestJWT(t, "test-secret", userID, true)
	status, body := callBundleUploadAPI(
		t,
		app,
		"/api/bundles/upload?bundle_id=3901&course_name=Draft%20Math",
		token,
		buildMinimalCourseBundle(t),
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d (body=%q)", status, http.StatusOK, body)
	}
	if !strings.Contains(body, `"status":"uploaded"`) {
		t.Fatalf("body = %q, want uploaded status", body)
	}
	message := smtpServer.WaitForMessage(t)
	if !strings.Contains(message, "To: "+adminEmail) {
		t.Fatalf("smtp message missing recipient: %q", message)
	}
	assertSQLMockExpectations(t, mock)
}

func buildBundleUploadApprovalTestApp(
	db *sql.DB,
	storageSvc *storage.Service,
	jwtSecrets []string,
	mailService *mailer.Service,
) *fiber.App {
	deps := Dependencies{
		Config: config.Config{
			JWTVerifySecrets: jwtSecrets,
			BundleMaxBytes:   1 << 20,
		},
		Store:   &storepkg.Store{DB: db},
		Storage: storageSvc,
		Mailer:  mailService,
	}
	bundles := NewBundlesHandler(deps)
	bundles.cfg.Storage = nil

	app := fiber.New()
	app.Post("/api/bundles/upload", bundles.Upload)
	return app
}

func buildMinimalCourseBundle(t *testing.T) []byte {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	writeZipEntry(t, zw, "contents.txt", "1 Intro\n")
	writeZipEntry(t, zw, "1_lecture.txt", "Lecture body")
	if err := zw.Close(); err != nil {
		t.Fatalf("zip.Close() error = %v", err)
	}
	return buf.Bytes()
}

func writeZipEntry(t *testing.T, zw *zip.Writer, name string, content string) {
	t.Helper()
	w, err := zw.Create(name)
	if err != nil {
		t.Fatalf("zip.Create(%q) error = %v", name, err)
	}
	if _, err := io.WriteString(w, content); err != nil {
		t.Fatalf("zip write %q error = %v", name, err)
	}
}

func callBundleUploadAPI(
	t *testing.T,
	app *fiber.App,
	url string,
	token string,
	bundle []byte,
) (int, string) {
	t.Helper()
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	part, err := writer.CreateFormFile("bundle", "course.zip")
	if err != nil {
		t.Fatalf("CreateFormFile() error = %v", err)
	}
	if _, err := part.Write(bundle); err != nil {
		t.Fatalf("multipart write error = %v", err)
	}
	if err := writer.Close(); err != nil {
		t.Fatalf("multipart close error = %v", err)
	}
	req := httptest.NewRequest(http.MethodPost, url, &body)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	if strings.TrimSpace(token) != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := app.Test(req)
	if err != nil {
		t.Fatalf("app.Test() error = %v", err)
	}
	defer resp.Body.Close()
	responseBody, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("ReadAll() error = %v", err)
	}
	return resp.StatusCode, strings.TrimSpace(string(responseBody))
}
