package handlers

import (
	"database/sql"
	"os"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
)

type TeacherCoursesHandler struct {
	cfg Dependencies
}

func NewTeacherCoursesHandler(deps Dependencies) *TeacherCoursesHandler {
	return &TeacherCoursesHandler{cfg: deps}
}

type createCourseRequest struct {
	Subject     string `json:"subject"`
	Grade       string `json:"grade"`
	Description string `json:"description"`
}

type publishCourseRequest struct {
	Visibility string `json:"visibility"`
}

func (h *TeacherCoursesHandler) ListCourses(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTSecret)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	teacherID, err := getTeacherAccountID(h.cfg.Store.DB, userID)
	if err != nil {
		if err == sql.ErrNoRows {
			return fiber.NewError(fiber.StatusForbidden, "teacher account required")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "teacher lookup failed")
	}

	rows, err := h.cfg.Store.DB.Query(
		`SELECT c.id, c.subject, c.grade, c.description,
		        ce.visibility, ce.published_at,
		        (
		          SELECT bv.id FROM bundles b
		          JOIN bundle_versions bv ON bv.bundle_id = b.id
		          WHERE b.course_id = c.id
		          ORDER BY bv.version DESC
		          LIMIT 1
		        ) AS latest_bundle_version_id
		 FROM courses c
		 JOIN course_catalog_entries ce ON ce.course_id = c.id
		 WHERE c.teacher_id = ?
		 ORDER BY c.created_at DESC`,
		teacherID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "course list failed")
	}
	defer rows.Close()

	type courseSummary struct {
		CourseID              int64  `json:"course_id"`
		Subject               string `json:"subject"`
		Grade                 string `json:"grade"`
		Description           string `json:"description"`
		Visibility            string `json:"visibility"`
		PublishedAt           string `json:"published_at"`
		LatestBundleVersionID int64  `json:"latest_bundle_version_id"`
	}

	results := []courseSummary{}
	for rows.Next() {
		var (
			courseID   int64
			subjectVal string
			gradeVal   sql.NullString
			descVal    sql.NullString
			visibility string
			published  sql.NullTime
			latest     sql.NullInt64
		)
		if err := rows.Scan(
			&courseID,
			&subjectVal,
			&gradeVal,
			&descVal,
			&visibility,
			&published,
			&latest,
		); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "course list failed")
		}
		publishedAt := ""
		if published.Valid {
			publishedAt = published.Time.Format(timeLayout)
		}
		results = append(results, courseSummary{
			CourseID:              courseID,
			Subject:               subjectVal,
			Grade:                 gradeVal.String,
			Description:           descVal.String,
			Visibility:            visibility,
			PublishedAt:           publishedAt,
			LatestBundleVersionID: latest.Int64,
		})
	}
	return c.JSON(results)
}

func (h *TeacherCoursesHandler) CreateCourse(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTSecret)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	teacherID, err := getTeacherAccountID(h.cfg.Store.DB, userID)
	if err != nil {
		if err == sql.ErrNoRows {
			return fiber.NewError(fiber.StatusForbidden, "teacher account required")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "teacher lookup failed")
	}
	var req createCourseRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	subject := strings.TrimSpace(req.Subject)
	if subject == "" {
		return fiber.NewError(fiber.StatusBadRequest, "subject required")
	}
	grade := strings.TrimSpace(req.Grade)
	description := strings.TrimSpace(req.Description)

	tx, err := h.cfg.Store.DB.Begin()
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "transaction failed")
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	result, err := tx.Exec(
		"INSERT INTO courses (teacher_id, subject, grade, description) VALUES (?, ?, ?, ?)",
		teacherID,
		subject,
		nullableString(grade),
		nullableString(description),
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "course insert failed")
	}
	courseID, err := result.LastInsertId()
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "course insert failed")
	}
	if _, err := tx.Exec(
		"INSERT INTO course_catalog_entries (course_id, teacher_id, visibility) VALUES (?, ?, 'private')",
		courseID,
		teacherID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "catalog insert failed")
	}
	if err := tx.Commit(); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "commit failed")
	}
	return c.JSON(fiber.Map{
		"course_id": courseID,
		"visibility": "private",
	})
}

func (h *TeacherCoursesHandler) PublishCourse(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTSecret)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	teacherID, err := getTeacherAccountID(h.cfg.Store.DB, userID)
	if err != nil {
		if err == sql.ErrNoRows {
			return fiber.NewError(fiber.StatusForbidden, "teacher account required")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "teacher lookup failed")
	}
	courseID, err := parseInt64Param(c, "id")
	if err != nil {
		return err
	}
	var req publishCourseRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	visibility := strings.TrimSpace(strings.ToLower(req.Visibility))
	if visibility == "" {
		return fiber.NewError(fiber.StatusBadRequest, "visibility required")
	}
	if visibility != "public" && visibility != "unlisted" && visibility != "private" {
		return fiber.NewError(fiber.StatusBadRequest, "visibility invalid")
	}
	publishedAt := sql.NullTime{}
	if visibility == "public" || visibility == "unlisted" {
		publishedAt = sql.NullTime{Time: time.Now(), Valid: true}
	}
	result, err := h.cfg.Store.DB.Exec(
		`UPDATE course_catalog_entries ce
		 JOIN courses c ON ce.course_id = c.id
		 SET ce.visibility = ?, ce.published_at = ?
		 WHERE ce.course_id = ? AND c.teacher_id = ?`,
		visibility,
		publishedAt,
		courseID,
		teacherID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "publish update failed")
	}
	affected, err := result.RowsAffected()
	if err != nil || affected == 0 {
		return fiber.NewError(fiber.StatusNotFound, "course not found")
	}
	return c.JSON(fiber.Map{
		"course_id":  courseID,
		"visibility": visibility,
	})
}

func (h *TeacherCoursesHandler) EnsureBundle(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTSecret)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	teacherID, err := getTeacherAccountID(h.cfg.Store.DB, userID)
	if err != nil {
		if err == sql.ErrNoRows {
			return fiber.NewError(fiber.StatusForbidden, "teacher account required")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "teacher lookup failed")
	}
	courseID, err := parseInt64Param(c, "id")
	if err != nil {
		return err
	}
	var existingID int64
	row := h.cfg.Store.DB.QueryRow(
		"SELECT id FROM bundles WHERE course_id = ? AND teacher_id = ? LIMIT 1",
		courseID, teacherID,
	)
	if err := row.Scan(&existingID); err == nil {
		return c.JSON(fiber.Map{
			"bundle_id": existingID,
			"course_id": courseID,
			"status":    "existing",
		})
	} else if err != sql.ErrNoRows {
		return fiber.NewError(fiber.StatusInternalServerError, "bundle lookup failed")
	}
	result, err := h.cfg.Store.DB.Exec(
		"INSERT INTO bundles (course_id, teacher_id) VALUES (?, ?)",
		courseID, teacherID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "bundle insert failed")
	}
	bundleID, err := result.LastInsertId()
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "bundle insert failed")
	}
	return c.JSON(fiber.Map{
		"bundle_id": bundleID,
		"course_id": courseID,
		"status":    "created",
	})
}

func (h *TeacherCoursesHandler) DeleteCourse(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTSecret)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	teacherID, err := getTeacherAccountID(h.cfg.Store.DB, userID)
	if err != nil {
		if err == sql.ErrNoRows {
			return fiber.NewError(fiber.StatusForbidden, "teacher account required")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "teacher lookup failed")
	}
	courseID, err := parseInt64Param(c, "id")
	if err != nil {
		return err
	}

	filePaths := []string{}
	rows, err := h.cfg.Store.DB.Query(
		`SELECT bv.oss_path
		 FROM bundle_versions bv
		 JOIN bundles b ON bv.bundle_id = b.id
		 WHERE b.course_id = ? AND b.teacher_id = ?`,
		courseID,
		teacherID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "bundle lookup failed")
	}
	for rows.Next() {
		var relPath sql.NullString
		if err := rows.Scan(&relPath); err != nil {
			rows.Close()
			return fiber.NewError(fiber.StatusInternalServerError, "bundle lookup failed")
		}
		if relPath.Valid {
			filePaths = append(filePaths, relPath.String)
		}
	}
	rows.Close()

	tx, err := h.cfg.Store.DB.Begin()
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "transaction failed")
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	if _, err = tx.Exec(
		`DELETE FROM session_text_sync WHERE course_id = ?`,
		courseID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "session sync delete failed")
	}
	if _, err = tx.Exec(
		`DELETE FROM e2ee_events WHERE course_id = ?`,
		courseID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "events delete failed")
	}
	if _, err = tx.Exec(
		`DELETE FROM marketplace_reports WHERE course_id = ?`,
		courseID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "reports delete failed")
	}
	if _, err = tx.Exec(
		`DELETE FROM enrollment_requests WHERE course_id = ?`,
		courseID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "requests delete failed")
	}
	if _, err = tx.Exec(
		`DELETE FROM enrollments WHERE course_id = ?`,
		courseID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "enrollments delete failed")
	}
	if _, err = tx.Exec(
		`DELETE FROM course_catalog_entries WHERE course_id = ? AND teacher_id = ?`,
		courseID,
		teacherID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "catalog delete failed")
	}
	if _, err = tx.Exec(
		`DELETE bv FROM bundle_versions bv
		 JOIN bundles b ON bv.bundle_id = b.id
		 WHERE b.course_id = ? AND b.teacher_id = ?`,
		courseID,
		teacherID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "bundle versions delete failed")
	}
	if _, err = tx.Exec(
		`DELETE FROM bundles WHERE course_id = ? AND teacher_id = ?`,
		courseID,
		teacherID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "bundles delete failed")
	}
	result, err := tx.Exec(
		`DELETE c FROM courses c
		 WHERE c.id = ? AND c.teacher_id = ?`,
		courseID,
		teacherID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "course delete failed")
	}
	affected, err := result.RowsAffected()
	if err != nil || affected == 0 {
		return fiber.NewError(fiber.StatusNotFound, "course not found")
	}
	if err = tx.Commit(); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "commit failed")
	}

	if h.cfg.Storage != nil {
		for _, relPath := range filePaths {
			absPath := h.cfg.Storage.BundleAbsolutePath(relPath)
			if removeErr := os.Remove(absPath); removeErr != nil && !os.IsNotExist(removeErr) {
				return fiber.NewError(fiber.StatusInternalServerError, "bundle file delete failed")
			}
		}
	}

	return c.JSON(fiber.Map{
		"course_id": courseID,
		"status":    "deleted",
	})
}
