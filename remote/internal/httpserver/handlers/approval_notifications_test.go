package handlers

import (
	"database/sql"
	"net"
	"net/http"
	"strconv"
	"strings"
	"testing"

	"family_teacher_remote/internal/config"
	storepkg "family_teacher_remote/internal/db"
	"family_teacher_remote/internal/mailer"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gofiber/fiber/v2"
)

func TestCreateEnrollmentRequestSendsTeacherApprovalEmail(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	smtpServer, mailService := newApprovalNotificationTestMailer(t)
	defer smtpServer.Close()

	userID := int64(901)
	courseID := int64(88)
	teacherID := int64(778)
	teacherEmail := "teacher@example.com"
	mock.ExpectQuery(`SELECT id FROM teacher_accounts WHERE user_id = \? AND status = 'active' LIMIT 1`).
		WithArgs(userID).
		WillReturnError(sql.ErrNoRows)
	mock.ExpectQuery(`SELECT c.teacher_id, ce.visibility`).
		WithArgs(courseID).
		WillReturnRows(
			sqlmock.NewRows([]string{"teacher_id", "visibility"}).
				AddRow(teacherID, "public"),
		)
	mock.ExpectQuery(`SELECT 1 FROM enrollments`).
		WithArgs(userID, courseID, teacherID).
		WillReturnError(sql.ErrNoRows)
	mock.ExpectQuery(`SELECT id FROM enrollment_requests`).
		WithArgs(userID, courseID).
		WillReturnError(sql.ErrNoRows)
	mock.ExpectBegin()
	mock.ExpectExec(`INSERT INTO enrollment_requests`).
		WithArgs(userID, teacherID, courseID, "please approve").
		WillReturnResult(sqlmock.NewResult(9001, 1))
	mock.ExpectQuery(`SELECT u.email\s+FROM teacher_accounts ta`).
		WithArgs(teacherID).
		WillReturnRows(sqlmock.NewRows([]string{"email"}).AddRow(teacherEmail))
	mock.ExpectCommit()

	app := buildEnrollmentNotificationTestApp(
		db,
		[]string{"test-secret"},
		mailService,
	)
	token := signTestJWT(t, "test-secret", userID, true)
	status, body, _ := callAPI(
		t,
		app,
		http.MethodPost,
		"/api/enrollment-requests",
		token,
		`{"course_id":88,"message":"please approve"}`,
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d, body=%s", status, http.StatusOK, body)
	}
	if !strings.Contains(body, `"request_id":9001`) {
		t.Fatalf("body missing request id: %s", body)
	}
	message := smtpServer.WaitForMessage(t)
	if !strings.Contains(message, "To: "+teacherEmail) {
		t.Fatalf("smtp message missing recipient: %q", message)
	}
	if !strings.Contains(message, "You have a Tutor1on1 approval request waiting for review.") {
		t.Fatalf("smtp message missing approval request body: %q", message)
	}
	assertSQLMockExpectations(t, mock)
}

func TestRejectEnrollmentRequestSendsStudentDecisionEmail(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	smtpServer, mailService := newApprovalNotificationTestMailer(t)
	defer smtpServer.Close()

	teacherUserID := int64(1701)
	teacherID := int64(778)
	requestID := int64(42)
	studentID := int64(901)
	studentEmail := "student@example.com"
	mock.ExpectQuery(`SELECT id FROM teacher_accounts WHERE user_id = \? AND status = 'active' LIMIT 1`).
		WithArgs(teacherUserID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(teacherID))
	mock.ExpectBegin()
	mock.ExpectQuery(`SELECT student_id\s+FROM enrollment_requests`).
		WithArgs(requestID, teacherID).
		WillReturnRows(sqlmock.NewRows([]string{"student_id"}).AddRow(studentID))
	mock.ExpectExec(`UPDATE enrollment_requests`).
		WithArgs(requestID, teacherID).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectQuery(`SELECT email\s+FROM users`).
		WithArgs(studentID).
		WillReturnRows(sqlmock.NewRows([]string{"email"}).AddRow(studentEmail))
	mock.ExpectCommit()

	app := buildEnrollmentNotificationTestApp(
		db,
		[]string{"test-secret"},
		mailService,
	)
	token := signTestJWT(t, "test-secret", teacherUserID, true)
	status, body, _ := callAPI(
		t,
		app,
		http.MethodPost,
		"/api/teacher/enrollment-requests/42/reject",
		token,
		`{}`,
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d, body=%s", status, http.StatusOK, body)
	}
	message := smtpServer.WaitForMessage(t)
	if !strings.Contains(message, "To: "+studentEmail) {
		t.Fatalf("smtp message missing recipient: %q", message)
	}
	if !strings.Contains(message, "Your Tutor1on1 request was rejected.") {
		t.Fatalf("smtp message missing decision body: %q", message)
	}
	assertSQLMockExpectations(t, mock)
}

func TestRejectEnrollmentRequestCommitsWhenDecisionEmailFails(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	mailService := newUnreachableApprovalNotificationTestMailer(t)

	teacherUserID := int64(1701)
	teacherID := int64(778)
	requestID := int64(42)
	studentID := int64(901)
	studentEmail := "bad-recipient@example.com"
	mock.ExpectQuery(`SELECT id FROM teacher_accounts WHERE user_id = \? AND status = 'active' LIMIT 1`).
		WithArgs(teacherUserID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(teacherID))
	mock.ExpectBegin()
	mock.ExpectQuery(`SELECT student_id\s+FROM enrollment_requests`).
		WithArgs(requestID, teacherID).
		WillReturnRows(sqlmock.NewRows([]string{"student_id"}).AddRow(studentID))
	mock.ExpectExec(`UPDATE enrollment_requests`).
		WithArgs(requestID, teacherID).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectQuery(`SELECT email\s+FROM users`).
		WithArgs(studentID).
		WillReturnRows(sqlmock.NewRows([]string{"email"}).AddRow(studentEmail))
	mock.ExpectCommit()

	app := buildEnrollmentNotificationTestApp(
		db,
		[]string{"test-secret"},
		mailService,
	)
	token := signTestJWT(t, "test-secret", teacherUserID, true)
	status, body, _ := callAPI(
		t,
		app,
		http.MethodPost,
		"/api/teacher/enrollment-requests/42/reject",
		token,
		`{}`,
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d, body=%s", status, http.StatusOK, body)
	}
	assertSQLMockExpectations(t, mock)
}

func TestNotifySubjectAdminsForTeacherApprovalRequestSendsEmail(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	smtpServer, mailService := newApprovalNotificationTestMailer(t)
	defer smtpServer.Close()

	teacherID := int64(7001)
	adminEmail := "subject-admin@example.com"
	mock.ExpectQuery(`SELECT DISTINCT u.email\s+FROM teacher_subject_labels tsl`).
		WithArgs(teacherID).
		WillReturnRows(sqlmock.NewRows([]string{"email"}).AddRow(adminEmail))

	if err := notifySubjectAdminsForTeacherRegistrationRequest(
		Dependencies{Mailer: mailService},
		db,
		teacherID,
	); err != nil {
		t.Fatalf("notifySubjectAdminsForTeacherRegistrationRequest() error = %v", err)
	}
	message := smtpServer.WaitForMessage(t)
	if !strings.Contains(message, "To: "+adminEmail) {
		t.Fatalf("smtp message missing recipient: %q", message)
	}
	if !strings.Contains(message, "You have a Tutor1on1 approval request waiting for review.") {
		t.Fatalf("smtp message missing approval request body: %q", message)
	}
	assertSQLMockExpectations(t, mock)
}

func TestNotifySubjectAdminsForCourseApprovalRequestSendsEmail(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	smtpServer, mailService := newApprovalNotificationTestMailer(t)
	defer smtpServer.Close()

	courseID := int64(8801)
	adminEmail := "course-admin@example.com"
	mock.ExpectQuery(`SELECT DISTINCT u.email\s+FROM course_subject_labels csl`).
		WithArgs(courseID).
		WillReturnRows(sqlmock.NewRows([]string{"email"}).AddRow(adminEmail))

	if err := notifySubjectAdminsForCourseUploadRequest(
		Dependencies{Mailer: mailService},
		db,
		courseID,
	); err != nil {
		t.Fatalf("notifySubjectAdminsForCourseUploadRequest() error = %v", err)
	}
	message := smtpServer.WaitForMessage(t)
	if !strings.Contains(message, "To: "+adminEmail) {
		t.Fatalf("smtp message missing recipient: %q", message)
	}
	if !strings.Contains(message, "You have a Tutor1on1 approval request waiting for review.") {
		t.Fatalf("smtp message missing approval request body: %q", message)
	}
	assertSQLMockExpectations(t, mock)
}

func buildEnrollmentNotificationTestApp(
	db *sql.DB,
	jwtSecrets []string,
	mailService *mailer.Service,
) *fiber.App {
	deps := Dependencies{
		Config: config.Config{
			JWTVerifySecrets: jwtSecrets,
		},
		Store:  &storepkg.Store{DB: db},
		Mailer: mailService,
	}
	enrollments := NewEnrollmentHandler(deps)
	app := fiber.New()
	app.Post("/api/enrollment-requests", enrollments.CreateRequest)
	app.Post("/api/teacher/enrollment-requests/:id/reject", enrollments.RejectRequest)
	return app
}

func newApprovalNotificationTestMailer(
	t *testing.T,
) (*fakeSMTPServer, *mailer.Service) {
	t.Helper()
	smtpServer := startFakeSMTPServer(t)
	host, port := smtpServer.HostPort(t)
	cfg := config.Config{
		SMTPEnabled: true,
		SMTPHost:    host,
		SMTPPort:    port,
		SMTPFrom:    "noreply@example.com",
	}
	return smtpServer, mailer.New(cfg)
}

func newUnreachableApprovalNotificationTestMailer(t *testing.T) *mailer.Service {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("net.Listen() error = %v", err)
	}
	host, port := func() (string, int) {
		host, port, err := net.SplitHostPort(ln.Addr().String())
		if err != nil {
			t.Fatalf("SplitHostPort() error = %v", err)
		}
		parsedPort, err := strconv.Atoi(port)
		if err != nil {
			t.Fatalf("Atoi(%q) error = %v", port, err)
		}
		return host, parsedPort
	}()
	if err := ln.Close(); err != nil {
		t.Fatalf("listener.Close() error = %v", err)
	}
	cfg := config.Config{
		SMTPEnabled: true,
		SMTPHost:    host,
		SMTPPort:    port,
		SMTPFrom:    "noreply@example.com",
	}
	return mailer.New(cfg)
}
