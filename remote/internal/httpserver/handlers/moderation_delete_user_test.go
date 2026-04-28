package handlers

import (
	"database/sql"
	"net/http"
	"testing"

	"family_teacher_remote/internal/config"
	storepkg "family_teacher_remote/internal/db"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gofiber/fiber/v2"
)

func TestAdminDeleteUserSoftDeletesNonAdminUser(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	adminUserID := int64(901)
	targetUserID := int64(902)
	mock.ExpectQuery(`SELECT id
		 FROM admin_accounts
		 WHERE user_id = \?
		 LIMIT 1`).
		WithArgs(adminUserID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(1))
	mock.ExpectBegin()
	mock.ExpectQuery(`SELECT status FROM users WHERE id = \? LIMIT 1 FOR UPDATE`).
		WithArgs(targetUserID).
		WillReturnRows(sqlmock.NewRows([]string{"status"}).AddRow("active"))
	mock.ExpectQuery(`SELECT id FROM admin_accounts WHERE user_id = \? LIMIT 1`).
		WithArgs(targetUserID).
		WillReturnError(sql.ErrNoRows)
	expectAdminUserDeleteCleanup(mock, adminUserID, targetUserID)
	mock.ExpectExec(`UPDATE users SET status = 'deleted' WHERE id = \? AND status <> 'deleted'`).
		WithArgs(targetUserID).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	app := buildModerationDeleteUserTestApp(db)
	token := signTestJWTWithDevice(t, "secret", adminUserID, "device-a", "nonce-a")
	status, body, _ := callAPI(
		t,
		app,
		http.MethodPost,
		"/api/admin/users/902/delete",
		token,
		`{}`,
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d (body=%q)", status, http.StatusOK, body)
	}
	assertSQLMockExpectations(t, mock)
}

func TestAdminDeleteUserRefusesAdminTarget(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	adminUserID := int64(911)
	targetUserID := int64(912)
	mock.ExpectQuery(`SELECT id
		 FROM admin_accounts
		 WHERE user_id = \?
		 LIMIT 1`).
		WithArgs(adminUserID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(1))
	mock.ExpectBegin()
	mock.ExpectQuery(`SELECT status FROM users WHERE id = \? LIMIT 1 FOR UPDATE`).
		WithArgs(targetUserID).
		WillReturnRows(sqlmock.NewRows([]string{"status"}).AddRow("active"))
	mock.ExpectQuery(`SELECT id FROM admin_accounts WHERE user_id = \? LIMIT 1`).
		WithArgs(targetUserID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(2))
	mock.ExpectRollback()

	app := buildModerationDeleteUserTestApp(db)
	token := signTestJWTWithDevice(t, "secret", adminUserID, "device-a", "nonce-a")
	status, body, _ := callAPI(
		t,
		app,
		http.MethodPost,
		"/api/admin/users/912/delete",
		token,
		`{}`,
	)
	if status != http.StatusForbidden {
		t.Fatalf("status = %d, want %d (body=%q)", status, http.StatusForbidden, body)
	}
	assertSQLMockExpectations(t, mock)
}

func TestAdminDeleteUserRefusesCurrentAdmin(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	adminUserID := int64(921)
	mock.ExpectQuery(`SELECT id
		 FROM admin_accounts
		 WHERE user_id = \?
		 LIMIT 1`).
		WithArgs(adminUserID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(1))

	app := buildModerationDeleteUserTestApp(db)
	token := signTestJWTWithDevice(t, "secret", adminUserID, "device-a", "nonce-a")
	status, body, _ := callAPI(
		t,
		app,
		http.MethodPost,
		"/api/admin/users/921/delete",
		token,
		`{}`,
	)
	if status != http.StatusForbidden {
		t.Fatalf("status = %d, want %d (body=%q)", status, http.StatusForbidden, body)
	}
	assertSQLMockExpectations(t, mock)
}

func expectAdminUserDeleteCleanup(
	mock sqlmock.Sqlmock,
	adminUserID int64,
	targetUserID int64,
) {
	result := sqlmock.NewResult(0, 1)
	mock.ExpectExec(`UPDATE teacher_accounts SET status = 'rejected' WHERE user_id = \?`).
		WithArgs(targetUserID).
		WillReturnResult(result)
	mock.ExpectExec(`DELETE FROM subject_admin_assignments WHERE teacher_user_id = \?`).
		WithArgs(targetUserID).
		WillReturnResult(result)
	mock.ExpectExec(`UPDATE teacher_registration_requests
			 SET status = 'rejected', resolved_at = NOW\(\), resolved_by_user_id = \?
			 WHERE user_id = \? AND status = 'pending'`).
		WithArgs(adminUserID, targetUserID).
		WillReturnResult(result)
	mock.ExpectExec(`(?s)UPDATE course_upload_requests cur.*cur\.resolved_by_user_id = \?.*WHERE ta\.user_id = \? AND cur\.status = 'pending'`).
		WithArgs(adminUserID, targetUserID).
		WillReturnResult(result)
	mock.ExpectExec(`(?s)UPDATE enrollment_requests.*student_id = \?.*SELECT id FROM teacher_accounts WHERE user_id = \?.*`).
		WithArgs(targetUserID, targetUserID).
		WillReturnResult(result)
	mock.ExpectExec(`(?s)UPDATE course_quit_requests.*student_id = \?.*SELECT id FROM teacher_accounts WHERE user_id = \?.*`).
		WithArgs(targetUserID, targetUserID).
		WillReturnResult(result)
	mock.ExpectExec(`(?s)UPDATE enrollments.*student_id = \?.*SELECT id FROM teacher_accounts WHERE user_id = \?.*`).
		WithArgs(targetUserID, targetUserID).
		WillReturnResult(result)
	mock.ExpectExec(`DELETE FROM teacher_study_mode_overrides
			 WHERE teacher_user_id = \? OR student_user_id = \?`).
		WithArgs(targetUserID, targetUserID).
		WillReturnResult(result)
	mock.ExpectExec(`UPDATE teacher_study_mode_schedules
			 SET status = 'deleted'
			 WHERE status <> 'deleted'
			   AND \(teacher_user_id = \? OR student_user_id = \?\)`).
		WithArgs(targetUserID, targetUserID).
		WillReturnResult(result)
	mock.ExpectExec(`UPDATE devices SET status = 'deleted' WHERE user_id = \?`).
		WithArgs(targetUserID).
		WillReturnResult(result)
	mock.ExpectExec(`UPDATE refresh_tokens SET revoked_at = NOW\(\) WHERE user_id = \? AND revoked_at IS NULL`).
		WithArgs(targetUserID).
		WillReturnResult(result)
	mock.ExpectExec(`UPDATE app_user_devices SET auth_session_nonce = NULL WHERE user_id = \?`).
		WithArgs(targetUserID).
		WillReturnResult(result)
}

func buildModerationDeleteUserTestApp(db *sql.DB) *fiber.App {
	deps := Dependencies{
		Config: config.Config{
			JWTVerifySecrets: []string{"secret"},
		},
		Store: &storepkg.Store{DB: db},
	}
	handler := NewModerationHandler(deps)
	app := fiber.New()
	app.Post("/api/admin/users/:userId/delete", handler.DeleteUser)
	return app
}
