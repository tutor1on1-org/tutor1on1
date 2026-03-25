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

func TestSubjectAdminRejectTeacherRegistrationUpdatesStatus(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(801)
	requestID := int64(21)
	teacherID := int64(91)

	mock.ExpectQuery(`SELECT id FROM admin_accounts WHERE user_id = \? LIMIT 1`).
		WithArgs(userID).
		WillReturnError(sql.ErrNoRows)
	mock.ExpectQuery(`SELECT id FROM teacher_accounts WHERE user_id = \? AND status = 'active' LIMIT 1`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(44))
	mock.ExpectBegin()
	mock.ExpectQuery(`SELECT teacher_id, status
		 FROM teacher_registration_requests
		 WHERE id = \?
		 LIMIT 1`).
		WithArgs(requestID).
		WillReturnRows(sqlmock.NewRows([]string{"teacher_id", "status"}).AddRow(teacherID, "pending"))
	mock.ExpectQuery(`SELECT 1
		 FROM teacher_registration_requests trr
		 JOIN teacher_subject_labels tsl ON tsl.teacher_id = trr.teacher_id
		 JOIN subject_admin_assignments saa ON saa.subject_label_id = tsl.subject_label_id
		 WHERE trr.id = \? AND saa.teacher_user_id = \?
		 LIMIT 1`).
		WithArgs(requestID, userID).
		WillReturnRows(sqlmock.NewRows([]string{"1"}).AddRow(1))
	mock.ExpectExec(`INSERT INTO teacher_registration_votes \(request_id, subject_admin_user_id, decision\)
			 VALUES \(\?, \?, 'rejected'\)
			 ON DUPLICATE KEY UPDATE decision = VALUES\(decision\), created_at = CURRENT_TIMESTAMP`).
		WithArgs(requestID, userID).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(`UPDATE teacher_accounts SET status = 'rejected' WHERE id = \?`).
		WithArgs(teacherID).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec(`UPDATE teacher_registration_requests
		 SET status = 'rejected', resolved_at = NOW\(\), resolved_by_user_id = \?
		 WHERE id = \?`).
		WithArgs(userID, requestID).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	app := buildModerationRejectTestApp(db)
	token := signTestJWTWithDevice(t, "secret", userID, "device-a", "nonce-a")
	status, body, _ := callAPI(
		t,
		app,
		http.MethodPost,
		"/api/subject-admin/teacher-registration-requests/21/reject",
		token,
		`{}`,
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d (body=%q)", status, http.StatusOK, body)
	}
	assertSQLMockExpectations(t, mock)
}

func TestSubjectAdminRejectTeacherRegistrationRequiresMatchingLabel(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(802)
	requestID := int64(22)

	mock.ExpectQuery(`SELECT id FROM admin_accounts WHERE user_id = \? LIMIT 1`).
		WithArgs(userID).
		WillReturnError(sql.ErrNoRows)
	mock.ExpectQuery(`SELECT id FROM teacher_accounts WHERE user_id = \? AND status = 'active' LIMIT 1`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(45))
	mock.ExpectBegin()
	mock.ExpectQuery(`SELECT teacher_id, status
		 FROM teacher_registration_requests
		 WHERE id = \?
		 LIMIT 1`).
		WithArgs(requestID).
		WillReturnRows(sqlmock.NewRows([]string{"teacher_id", "status"}).AddRow(92, "pending"))
	mock.ExpectQuery(`SELECT 1
		 FROM teacher_registration_requests trr
		 JOIN teacher_subject_labels tsl ON tsl.teacher_id = trr.teacher_id
		 JOIN subject_admin_assignments saa ON saa.subject_label_id = tsl.subject_label_id
		 WHERE trr.id = \? AND saa.teacher_user_id = \?
		 LIMIT 1`).
		WithArgs(requestID, userID).
		WillReturnError(sql.ErrNoRows)
	mock.ExpectRollback()

	app := buildModerationRejectTestApp(db)
	token := signTestJWTWithDevice(t, "secret", userID, "device-a", "nonce-a")
	status, body, _ := callAPI(
		t,
		app,
		http.MethodPost,
		"/api/subject-admin/teacher-registration-requests/22/reject",
		token,
		`{}`,
	)
	if status != http.StatusForbidden {
		t.Fatalf("status = %d, want %d (body=%q)", status, http.StatusForbidden, body)
	}
	assertSQLMockExpectations(t, mock)
}

func TestSubjectAdminRejectCourseUploadUpdatesStatus(t *testing.T) {
	db, mock := newHandlerSQLMock(t)
	defer db.Close()

	userID := int64(803)
	requestID := int64(31)

	mock.ExpectQuery(`SELECT id FROM admin_accounts WHERE user_id = \? LIMIT 1`).
		WithArgs(userID).
		WillReturnError(sql.ErrNoRows)
	mock.ExpectQuery(`SELECT id FROM teacher_accounts WHERE user_id = \? AND status = 'active' LIMIT 1`).
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(46))
	mock.ExpectBegin()
	mock.ExpectQuery(`SELECT status
		 FROM course_upload_requests
		 WHERE id = \?
		 LIMIT 1`).
		WithArgs(requestID).
		WillReturnRows(sqlmock.NewRows([]string{"status"}).AddRow("pending"))
	mock.ExpectQuery(`SELECT 1
		 FROM course_upload_requests cur
		 JOIN course_subject_labels csl ON csl.course_id = cur.course_id
		 JOIN subject_admin_assignments saa ON saa.subject_label_id = csl.subject_label_id
		 WHERE cur.id = \? AND saa.teacher_user_id = \?
		 LIMIT 1`).
		WithArgs(requestID, userID).
		WillReturnRows(sqlmock.NewRows([]string{"1"}).AddRow(1))
	mock.ExpectExec(`INSERT INTO course_upload_votes \(request_id, subject_admin_user_id, decision\)
			 VALUES \(\?, \?, 'rejected'\)
			 ON DUPLICATE KEY UPDATE decision = VALUES\(decision\), created_at = CURRENT_TIMESTAMP`).
		WithArgs(requestID, userID).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(`UPDATE course_upload_requests
		 SET status = 'rejected', resolved_at = NOW\(\), resolved_by_user_id = \?
		 WHERE id = \?`).
		WithArgs(userID, requestID).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	app := buildModerationRejectTestApp(db)
	token := signTestJWTWithDevice(t, "secret", userID, "device-a", "nonce-a")
	status, body, _ := callAPI(
		t,
		app,
		http.MethodPost,
		"/api/subject-admin/course-upload-requests/31/reject",
		token,
		`{}`,
	)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want %d (body=%q)", status, http.StatusOK, body)
	}
	assertSQLMockExpectations(t, mock)
}

func buildModerationRejectTestApp(db *sql.DB) *fiber.App {
	deps := Dependencies{
		Config: config.Config{
			JWTVerifySecrets: []string{"secret"},
		},
		Store: &storepkg.Store{DB: db},
	}
	handler := NewModerationHandler(deps)
	app := fiber.New()
	app.Use(func(c *fiber.Ctx) error {
		ctx, err := ParseAuthContextFromBearerHeader(
			c.Get("Authorization"),
			[]string{"secret"},
		)
		if err != nil {
			return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
		}
		c.Locals(AuthLocalValidatedKey, true)
		c.Locals(AuthLocalUserIDKey, ctx.UserID)
		c.Locals(AuthLocalDeviceKeyKey, ctx.DeviceKey)
		c.Locals(AuthLocalDeviceSessionNonceKey, ctx.DeviceSessionNonce)
		return c.Next()
	})
	app.Post("/api/subject-admin/teacher-registration-requests/:id/reject", handler.RejectTeacherRegistration)
	app.Post("/api/subject-admin/course-upload-requests/:id/reject", handler.RejectCourseUpload)
	return app
}
