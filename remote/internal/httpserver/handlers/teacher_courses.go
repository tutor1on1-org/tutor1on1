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
	Subject         string  `json:"subject"`
	Grade           string  `json:"grade"`
	Description     string  `json:"description"`
	SubjectLabelIDs []int64 `json:"subject_label_ids"`
}

type publishCourseRequest struct {
	Visibility string `json:"visibility"`
}

type teacherCourseSummary struct {
	CourseID              int64                 `json:"course_id"`
	Subject               string                `json:"subject"`
	Grade                 string                `json:"grade"`
	Description           string                `json:"description"`
	Visibility            string                `json:"visibility"`
	ApprovalStatus        string                `json:"approval_status"`
	PublishedAt           string                `json:"published_at"`
	LatestBundleVersionID int64                 `json:"latest_bundle_version_id"`
	LatestBundleHash      string                `json:"latest_bundle_hash"`
	SubjectLabels         []subjectLabelSummary `json:"subject_labels"`
	Status                string                `json:"status,omitempty"`
}

func (h *TeacherCoursesHandler) ListCourses(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
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
	results, err := h.listTeacherCourseSummaries(teacherID)
	if err != nil {
		return err
	}
	return respondJSONWithETag(c, results)
}

func (h *TeacherCoursesHandler) listTeacherCourseSummaries(teacherID int64) ([]teacherCourseSummary, error) {
	rows, err := h.cfg.Store.DB.Query(
		`SELECT c.id, c.subject, c.grade, c.description,
		        ce.visibility, ce.approval_status, ce.published_at,
		        (
		          SELECT bv.id FROM bundles b
		          JOIN bundle_versions bv ON bv.bundle_id = b.id
		          WHERE b.course_id = c.id
		          ORDER BY bv.version DESC
		          LIMIT 1
		        ) AS latest_bundle_version_id,
		        (
		          SELECT bv.hash FROM bundles b
		          JOIN bundle_versions bv ON bv.bundle_id = b.id
		          WHERE b.course_id = c.id
		          ORDER BY bv.version DESC, bv.id DESC
		          LIMIT 1
		        ) AS latest_bundle_hash,
		        (
		          SELECT bv.oss_path FROM bundles b
		          JOIN bundle_versions bv ON bv.bundle_id = b.id
		          WHERE b.course_id = c.id
		          ORDER BY bv.version DESC, bv.id DESC
		          LIMIT 1
		        ) AS latest_bundle_oss_path
		 FROM courses c
		 JOIN (
		   SELECT teacher_id, course_name_key, MAX(id) AS latest_course_id
		   FROM courses
		   WHERE teacher_id = ?
		   GROUP BY teacher_id, course_name_key
		 ) latest ON latest.latest_course_id = c.id
		 JOIN course_catalog_entries ce ON ce.course_id = c.id
		 WHERE c.teacher_id = ?
		 ORDER BY c.created_at DESC`,
		teacherID,
		teacherID,
	)
	if err != nil {
		return nil, fiber.NewError(fiber.StatusInternalServerError, "course list failed")
	}
	defer rows.Close()

	results := []teacherCourseSummary{}
	for rows.Next() {
		var (
			courseID       int64
			subjectVal     string
			gradeVal       sql.NullString
			descVal        sql.NullString
			visibility     string
			approvalStatus string
			published      sql.NullTime
			latest         sql.NullInt64
			latestHash     sql.NullString
			latestRelPath  sql.NullString
		)
		if err := rows.Scan(
			&courseID,
			&subjectVal,
			&gradeVal,
			&descVal,
			&visibility,
			&approvalStatus,
			&published,
			&latest,
			&latestHash,
			&latestRelPath,
		); err != nil {
			return nil, fiber.NewError(fiber.StatusInternalServerError, "course list failed")
		}
		resolvedHash, _, _, hashErr := ensureStoredBundleHash(
			h.cfg.Store.DB,
			h.cfg.Storage,
			latest.Int64,
			latestHash.String,
			latestRelPath.String,
		)
		if hashErr != nil {
			return nil, fiber.NewError(fiber.StatusInternalServerError, "course list failed")
		}
		publishedAt := ""
		if published.Valid {
			publishedAt = published.Time.Format(timeLayout)
		}
		results = append(results, teacherCourseSummary{
			CourseID:              courseID,
			Subject:               subjectVal,
			Grade:                 gradeVal.String,
			Description:           descVal.String,
			Visibility:            visibility,
			ApprovalStatus:        approvalStatus,
			PublishedAt:           publishedAt,
			LatestBundleVersionID: latest.Int64,
			LatestBundleHash:      resolvedHash,
			SubjectLabels:         nil,
		})
	}
	if err := rows.Err(); err != nil {
		return nil, fiber.NewError(fiber.StatusInternalServerError, "course list failed")
	}
	for index := range results {
		labels, err := listCourseSubjectLabels(h.cfg.Store.DB, results[index].CourseID)
		if err != nil {
			return nil, fiber.NewError(fiber.StatusInternalServerError, "course labels failed")
		}
		results[index].SubjectLabels = labels
	}
	return results, nil
}

func (h *TeacherCoursesHandler) CreateCourse(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
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
	courseNameKey := normalizeCourseName(subject)
	if courseNameKey == "" {
		return fiber.NewError(fiber.StatusBadRequest, "subject required")
	}
	grade := strings.TrimSpace(req.Grade)
	description := strings.TrimSpace(req.Description)

	existing, found, err := h.lookupTeacherCourseByNameKey(teacherID, courseNameKey)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "course lookup failed")
	}
	if found {
		existing.Status = "existing"
		return c.JSON(existing)
	}

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
		"INSERT INTO courses (teacher_id, subject, course_name_key, grade, description) VALUES (?, ?, ?, ?, ?)",
		teacherID,
		subject,
		courseNameKey,
		nullableString(grade),
		nullableString(description),
	)
	if err != nil {
		if isDuplicateEntryError(err) {
			_ = tx.Rollback()
			existing, found, lookupErr := h.lookupTeacherCourseByNameKey(teacherID, courseNameKey)
			if lookupErr != nil {
				return fiber.NewError(fiber.StatusInternalServerError, "course lookup failed")
			}
			if !found {
				return fiber.NewError(fiber.StatusConflict, "course already exists")
			}
			existing.Status = "existing"
			return c.JSON(existing)
		}
		return fiber.NewError(fiber.StatusInternalServerError, "course insert failed")
	}
	courseID, err := result.LastInsertId()
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "course insert failed")
	}
	if _, err := tx.Exec(
		"INSERT INTO course_catalog_entries (course_id, teacher_id, visibility, approval_status) VALUES (?, ?, 'private', 'pending')",
		courseID,
		teacherID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "catalog insert failed")
	}
	labelIDs, err := resolveSubjectLabelIDsTx(tx, req.SubjectLabelIDs)
	if err != nil {
		return err
	}
	if err := replaceCourseSubjectLabelsTx(tx, courseID, labelIDs); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "course labels save failed")
	}
	if err := tx.Commit(); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "commit failed")
	}
	labels, err := listCourseSubjectLabels(h.cfg.Store.DB, courseID)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "course labels failed")
	}
	return c.JSON(teacherCourseSummary{
		CourseID:              courseID,
		Subject:               subject,
		Grade:                 grade,
		Description:           description,
		Visibility:            "private",
		ApprovalStatus:        "pending",
		PublishedAt:           "",
		LatestBundleVersionID: 0,
		SubjectLabels:         labels,
		Status:                "created",
	})
}

func (h *TeacherCoursesHandler) PublishCourse(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
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
	if visibility == "public" || visibility == "unlisted" {
		hasBundle, err := h.hasAnyBundleVersion(courseID, teacherID)
		if err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "bundle lookup failed")
		}
		if !hasBundle {
			return fiber.NewError(fiber.StatusBadRequest, "bundle required before publish")
		}
		var approvalStatus string
		row := h.cfg.Store.DB.QueryRow(
			`SELECT ce.approval_status
			 FROM course_catalog_entries ce
			 JOIN courses c ON ce.course_id = c.id
			 WHERE ce.course_id = ? AND c.teacher_id = ?`,
			courseID,
			teacherID,
		)
		if err := row.Scan(&approvalStatus); err != nil {
			if err == sql.ErrNoRows {
				return fiber.NewError(fiber.StatusNotFound, "course not found")
			}
			return fiber.NewError(fiber.StatusInternalServerError, "approval lookup failed")
		}
		if approvalStatus != "approved" {
			return fiber.NewError(fiber.StatusBadRequest, "course approval required before publish")
		}
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

func (h *TeacherCoursesHandler) UpdateCourseSubjectLabels(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
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
	var req createCourseRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	courseExists, err := h.courseExistsByID(courseID, teacherID)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "course lookup failed")
	}
	if !courseExists {
		return fiber.NewError(fiber.StatusNotFound, "course not found")
	}
	tx, err := h.cfg.Store.DB.Begin()
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "transaction failed")
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()
	labelIDs, err := resolveSubjectLabelIDsTx(tx, req.SubjectLabelIDs)
	if err != nil {
		return err
	}
	if err := replaceCourseSubjectLabelsTx(tx, courseID, labelIDs); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "course labels save failed")
	}
	if err := tx.Commit(); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "commit failed")
	}
	labels, err := listCourseSubjectLabels(h.cfg.Store.DB, courseID)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "course labels failed")
	}
	return c.JSON(fiber.Map{
		"course_id":      courseID,
		"subject_labels": labels,
		"status":         "updated",
	})
}

func (h *TeacherCoursesHandler) EnsureBundle(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
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
	courseExists, err := h.courseExistsByID(courseID, teacherID)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "course lookup failed")
	}
	if !courseExists {
		courseName := strings.TrimSpace(c.Query("course_name"))
		if courseName == "" {
			return fiber.NewError(fiber.StatusNotFound, "course not found")
		}
		resolvedCourseID, ensureErr := h.resolveOrCreateCourseByName(teacherID, courseName)
		if ensureErr != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "course ensure failed")
		}
		courseID = resolvedCourseID
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
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
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
	affectedStudentIDs := []int64{}
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

	studentRows, err := h.cfg.Store.DB.Query(
		`SELECT DISTINCT student_id
		 FROM enrollments
		 WHERE course_id = ? AND status = 'active'`,
		courseID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "enrollment lookup failed")
	}
	for studentRows.Next() {
		var studentID int64
		if err := studentRows.Scan(&studentID); err != nil {
			studentRows.Close()
			return fiber.NewError(fiber.StatusInternalServerError, "enrollment lookup failed")
		}
		affectedStudentIDs = append(affectedStudentIDs, studentID)
	}
	if err := studentRows.Err(); err != nil {
		studentRows.Close()
		return fiber.NewError(fiber.StatusInternalServerError, "enrollment lookup failed")
	}
	studentRows.Close()

	tx, err := h.cfg.Store.DB.Begin()
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "transaction failed")
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	if err = deleteStudentArtifactsForCourseTx(tx, courseID); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "student artifact delete failed")
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
	if err = deleteCourseBundleReferencesTx(tx, courseID); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "bundle references delete failed")
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
	if err := refreshArtifactStatesForUsers(
		h.cfg.Store.DB,
		append([]int64{userID}, affectedStudentIDs...),
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "artifact state refresh failed")
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

func (h *TeacherCoursesHandler) lookupTeacherCourseByNameKey(
	teacherID int64,
	courseNameKey string,
) (teacherCourseSummary, bool, error) {
	row := h.cfg.Store.DB.QueryRow(
		`SELECT c.id, c.subject, c.grade, c.description,
		        COALESCE(ce.visibility, 'private') AS visibility,
		        COALESCE(ce.approval_status, 'pending') AS approval_status,
		        ce.published_at,
		        (
		          SELECT bv.id FROM bundles b
		          JOIN bundle_versions bv ON bv.bundle_id = b.id
		          WHERE b.course_id = c.id
		          ORDER BY bv.version DESC, bv.id DESC
		          LIMIT 1
		        ) AS latest_bundle_version_id,
		        (
		          SELECT bv.hash FROM bundles b
		          JOIN bundle_versions bv ON bv.bundle_id = b.id
		          WHERE b.course_id = c.id
		          ORDER BY bv.version DESC, bv.id DESC
		          LIMIT 1
		        ) AS latest_bundle_hash,
		        (
		          SELECT bv.oss_path FROM bundles b
		          JOIN bundle_versions bv ON bv.bundle_id = b.id
		          WHERE b.course_id = c.id
		          ORDER BY bv.version DESC, bv.id DESC
		          LIMIT 1
		        ) AS latest_bundle_oss_path
		 FROM courses c
		 LEFT JOIN course_catalog_entries ce ON ce.course_id = c.id
		 WHERE c.teacher_id = ? AND c.course_name_key = ?
		 ORDER BY c.id DESC
		 LIMIT 1`,
		teacherID,
		courseNameKey,
	)
	var (
		courseID       int64
		subjectVal     string
		gradeVal       sql.NullString
		descVal        sql.NullString
		visibility     string
		approvalStatus string
		published      sql.NullTime
		latest         sql.NullInt64
		latestHash     sql.NullString
		latestRelPath  sql.NullString
	)
	if err := row.Scan(
		&courseID,
		&subjectVal,
		&gradeVal,
		&descVal,
		&visibility,
		&approvalStatus,
		&published,
		&latest,
		&latestHash,
		&latestRelPath,
	); err != nil {
		if err == sql.ErrNoRows {
			return teacherCourseSummary{}, false, nil
		}
		return teacherCourseSummary{}, false, err
	}
	resolvedHash, _, _, hashErr := ensureStoredBundleHash(
		h.cfg.Store.DB,
		h.cfg.Storage,
		latest.Int64,
		latestHash.String,
		latestRelPath.String,
	)
	if hashErr != nil {
		return teacherCourseSummary{}, false, hashErr
	}
	publishedAt := ""
	if published.Valid {
		publishedAt = published.Time.Format(timeLayout)
	}
	labels, err := listCourseSubjectLabels(h.cfg.Store.DB, courseID)
	if err != nil {
		return teacherCourseSummary{}, false, err
	}
	return teacherCourseSummary{
		CourseID:              courseID,
		Subject:               subjectVal,
		Grade:                 gradeVal.String,
		Description:           descVal.String,
		Visibility:            visibility,
		ApprovalStatus:        approvalStatus,
		PublishedAt:           publishedAt,
		LatestBundleVersionID: latest.Int64,
		LatestBundleHash:      resolvedHash,
		SubjectLabels:         labels,
	}, true, nil
}

func (h *TeacherCoursesHandler) hasAnyBundleVersion(courseID int64, teacherID int64) (bool, error) {
	row := h.cfg.Store.DB.QueryRow(
		`SELECT 1
		 FROM bundles b
		 JOIN bundle_versions bv ON bv.bundle_id = b.id
		 WHERE b.course_id = ? AND b.teacher_id = ?
		 LIMIT 1`,
		courseID,
		teacherID,
	)
	var found int
	if err := row.Scan(&found); err != nil {
		if err == sql.ErrNoRows {
			return false, nil
		}
		return false, err
	}
	return true, nil
}

func (h *TeacherCoursesHandler) courseExistsByID(courseID int64, teacherID int64) (bool, error) {
	row := h.cfg.Store.DB.QueryRow(
		`SELECT 1
		 FROM courses
		 WHERE id = ? AND teacher_id = ?
		 LIMIT 1`,
		courseID,
		teacherID,
	)
	var found int
	if err := row.Scan(&found); err != nil {
		if err == sql.ErrNoRows {
			return false, nil
		}
		return false, err
	}
	return true, nil
}

func (h *TeacherCoursesHandler) resolveOrCreateCourseByName(
	teacherID int64,
	courseName string,
) (int64, error) {
	normalized := normalizeCourseName(courseName)
	if normalized == "" {
		return 0, fiber.NewError(fiber.StatusBadRequest, "course_name required")
	}

	tx, err := h.cfg.Store.DB.Begin()
	if err != nil {
		return 0, err
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	var courseID int64
	row := tx.QueryRow(
		`SELECT id
		 FROM courses
		 WHERE teacher_id = ? AND course_name_key = ?
		 ORDER BY id DESC
		 LIMIT 1`,
		teacherID,
		normalized,
	)
	if scanErr := row.Scan(&courseID); scanErr != nil {
		if scanErr != sql.ErrNoRows {
			err = scanErr
			return 0, err
		}
		insertResult, insertErr := tx.Exec(
			`INSERT INTO courses (teacher_id, subject, course_name_key, grade, description)
			 VALUES (?, ?, ?, NULL, NULL)`,
			teacherID,
			strings.TrimSpace(courseName),
			normalized,
		)
		if insertErr != nil {
			if !isDuplicateEntryError(insertErr) {
				err = insertErr
				return 0, err
			}
			row = tx.QueryRow(
				`SELECT id
				 FROM courses
				 WHERE teacher_id = ? AND course_name_key = ?
				 ORDER BY id DESC
				 LIMIT 1`,
				teacherID,
				normalized,
			)
			if scanAgainErr := row.Scan(&courseID); scanAgainErr != nil {
				err = scanAgainErr
				return 0, err
			}
		} else {
			insertedID, idErr := insertResult.LastInsertId()
			if idErr != nil {
				err = idErr
				return 0, err
			}
			courseID = insertedID
		}
	}

	var catalogID int64
	catalogRow := tx.QueryRow(
		`SELECT id
		 FROM course_catalog_entries
		 WHERE course_id = ? AND teacher_id = ?
		 LIMIT 1`,
		courseID,
		teacherID,
	)
	if scanErr := catalogRow.Scan(&catalogID); scanErr != nil {
		if scanErr != sql.ErrNoRows {
			err = scanErr
			return 0, err
		}
		if _, insertErr := tx.Exec(
			`INSERT INTO course_catalog_entries (course_id, teacher_id, visibility, approval_status)
			 VALUES (?, ?, 'private', 'pending')`,
			courseID,
			teacherID,
		); insertErr != nil {
			err = insertErr
			return 0, err
		}
	}

	if commitErr := tx.Commit(); commitErr != nil {
		err = commitErr
		return 0, err
	}
	return courseID, nil
}
