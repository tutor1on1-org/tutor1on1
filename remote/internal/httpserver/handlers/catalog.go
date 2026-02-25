package handlers

import (
	"database/sql"
	"strconv"
	"strings"

	"github.com/gofiber/fiber/v2"
)

type CatalogHandler struct {
	cfg Dependencies
}

func NewCatalogHandler(deps Dependencies) *CatalogHandler {
	return &CatalogHandler{cfg: deps}
}

func (h *CatalogHandler) ListTeachers(c *fiber.Ctx) error {
	if _, err := requireUserID(c, h.cfg.Config.JWTSecret); err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	limit, err := parseLimitQuery(c, 50, 100)
	if err != nil {
		return err
	}
	offset, err := parseOffsetQuery(c)
	if err != nil {
		return err
	}
	q := strings.TrimSpace(c.Query("q"))
	args := []interface{}{}
	query := `
SELECT t.id, t.display_name, t.bio, t.avatar_url, t.contact, t.contact_published
FROM teacher_accounts t
WHERE t.status = 'active'
  AND EXISTS (
    SELECT 1 FROM course_catalog_entries ce
    WHERE ce.teacher_id = t.id AND ce.visibility = 'public'
  )
`
	if q != "" {
		query += " AND (t.display_name LIKE ? OR t.bio LIKE ?)"
		qLike := "%" + q + "%"
		args = append(args, qLike, qLike)
	}
	query += " ORDER BY t.display_name ASC LIMIT ? OFFSET ?"
	args = append(args, limit, offset)

	rows, err := h.cfg.Store.DB.Query(query, args...)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "teacher list failed")
	}
	defer rows.Close()

	type teacherSummary struct {
		ID              int64  `json:"teacher_id"`
		DisplayName     string `json:"display_name"`
		Bio             string `json:"bio"`
		AvatarURL       string `json:"avatar_url"`
		Contact         string `json:"contact"`
		ContactPublished bool  `json:"contact_published"`
	}

	results := []teacherSummary{}
	for rows.Next() {
		var (
			id        int64
			display   string
			bio       sql.NullString
			avatar    sql.NullString
			contact   sql.NullString
			contactOk bool
		)
		if err := rows.Scan(&id, &display, &bio, &avatar, &contact, &contactOk); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "teacher list failed")
		}
		contactValue := ""
		if contactOk && contact.Valid {
			contactValue = contact.String
		}
		results = append(results, teacherSummary{
			ID:               id,
			DisplayName:      display,
			Bio:              bio.String,
			AvatarURL:        avatar.String,
			Contact:          contactValue,
			ContactPublished: contactOk,
		})
	}
	return c.JSON(results)
}

func (h *CatalogHandler) ListCourses(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTSecret)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	_ = userID
	limit, err := parseLimitQuery(c, 50, 100)
	if err != nil {
		return err
	}
	offset, err := parseOffsetQuery(c)
	if err != nil {
		return err
	}
	q := strings.TrimSpace(c.Query("q"))
	subject := strings.TrimSpace(c.Query("subject"))
	grade := strings.TrimSpace(c.Query("grade"))
	teacherID := strings.TrimSpace(c.Query("teacher_id"))

	args := []interface{}{}
	query := `
SELECT c.id, c.subject, c.grade, c.description,
       c.teacher_id, t.display_name, t.avatar_url,
       ce.visibility, ce.published_at,
       (
         SELECT bv.id FROM bundles b
         JOIN bundle_versions bv ON bv.bundle_id = b.id
         WHERE b.course_id = c.id
         ORDER BY bv.version DESC
         LIMIT 1
       ) AS latest_bundle_version_id
FROM courses c
JOIN teacher_accounts t ON c.teacher_id = t.id
JOIN course_catalog_entries ce ON ce.course_id = c.id
WHERE t.status = 'active' AND ce.visibility = 'public'
`
	if teacherID != "" {
		parsedID, err := strconv.ParseInt(teacherID, 10, 64)
		if err != nil || parsedID <= 0 {
			return fiber.NewError(fiber.StatusBadRequest, "teacher_id invalid")
		}
		query += " AND c.teacher_id = ?"
		args = append(args, parsedID)
	}
	if subject != "" {
		query += " AND c.subject LIKE ?"
		args = append(args, "%"+subject+"%")
	}
	if grade != "" {
		query += " AND c.grade = ?"
		args = append(args, grade)
	}
	if q != "" {
		query += " AND (c.subject LIKE ? OR c.description LIKE ? OR t.display_name LIKE ?)"
		qLike := "%" + q + "%"
		args = append(args, qLike, qLike, qLike)
	}
	query += " ORDER BY ce.published_at DESC, c.id DESC LIMIT ? OFFSET ?"
	args = append(args, limit, offset)

	rows, err := h.cfg.Store.DB.Query(query, args...)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "course list failed")
	}
	defer rows.Close()

	type courseSummary struct {
		CourseID              int64  `json:"course_id"`
		Subject               string `json:"subject"`
		Grade                 string `json:"grade"`
		Description           string `json:"description"`
		TeacherID             int64  `json:"teacher_id"`
		TeacherName           string `json:"teacher_name"`
		TeacherAvatarURL      string `json:"teacher_avatar_url"`
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
			teacherIDVal int64
			teacherName string
			teacherAvatar sql.NullString
			visibility string
			publishedAt sql.NullTime
			latestBundle sql.NullInt64
		)
		if err := rows.Scan(
			&courseID,
			&subjectVal,
			&gradeVal,
			&descVal,
			&teacherIDVal,
			&teacherName,
			&teacherAvatar,
			&visibility,
			&publishedAt,
			&latestBundle,
		); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "course list failed")
		}
		publishedStr := ""
		if publishedAt.Valid {
			publishedStr = publishedAt.Time.Format(timeLayout)
		}
		results = append(results, courseSummary{
			CourseID:              courseID,
			Subject:               subjectVal,
			Grade:                 gradeVal.String,
			Description:           descVal.String,
			TeacherID:             teacherIDVal,
			TeacherName:           teacherName,
			TeacherAvatarURL:      teacherAvatar.String,
			Visibility:            visibility,
			PublishedAt:           publishedStr,
			LatestBundleVersionID: latestBundle.Int64,
		})
	}
	return c.JSON(results)
}

const timeLayout = "2006-01-02 15:04:05"
