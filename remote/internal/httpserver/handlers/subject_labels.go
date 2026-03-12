package handlers

import (
	"database/sql"
	"errors"
	"fmt"
	"sort"
	"strings"

	"github.com/gofiber/fiber/v2"
)

type subjectLabelSummary struct {
	ID       int64  `json:"subject_label_id"`
	Slug     string `json:"slug"`
	Name     string `json:"name"`
	IsActive bool   `json:"is_active"`
}

func resolveSubjectLabelIDsTx(tx *sql.Tx, rawIDs []int64) ([]int64, error) {
	if tx == nil {
		return nil, errors.New("transaction required")
	}
	normalized := dedupePositiveInt64s(rawIDs)
	if len(normalized) == 0 {
		fallbackID, err := findSubjectLabelIDBySlugTx(tx, "others")
		if err != nil {
			return nil, err
		}
		return []int64{fallbackID}, nil
	}
	placeholders := strings.TrimRight(strings.Repeat("?,", len(normalized)), ",")
	args := make([]interface{}, 0, len(normalized))
	for _, id := range normalized {
		args = append(args, id)
	}
	rows, err := tx.Query(
		fmt.Sprintf(
			`SELECT id
			 FROM subject_labels
			 WHERE is_active = TRUE AND id IN (%s)`,
			placeholders,
		),
		args...,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	valid := make(map[int64]struct{}, len(normalized))
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		valid[id] = struct{}{}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if len(valid) != len(normalized) {
		return nil, fiber.NewError(fiber.StatusBadRequest, "subject_label_ids invalid")
	}
	return normalized, nil
}

func replaceTeacherSubjectLabelsTx(tx *sql.Tx, teacherID int64, labelIDs []int64) error {
	if _, err := tx.Exec(
		"DELETE FROM teacher_subject_labels WHERE teacher_id = ?",
		teacherID,
	); err != nil {
		return err
	}
	for _, labelID := range labelIDs {
		if _, err := tx.Exec(
			`INSERT INTO teacher_subject_labels (teacher_id, subject_label_id)
			 VALUES (?, ?)`,
			teacherID,
			labelID,
		); err != nil {
			return err
		}
	}
	return nil
}

func replaceCourseSubjectLabelsTx(tx *sql.Tx, courseID int64, labelIDs []int64) error {
	if _, err := tx.Exec(
		"DELETE FROM course_subject_labels WHERE course_id = ?",
		courseID,
	); err != nil {
		return err
	}
	for _, labelID := range labelIDs {
		if _, err := tx.Exec(
			`INSERT INTO course_subject_labels (course_id, subject_label_id)
			 VALUES (?, ?)`,
			courseID,
			labelID,
		); err != nil {
			return err
		}
	}
	return nil
}

func listAllSubjectLabels(db *sql.DB) ([]subjectLabelSummary, error) {
	rows, err := db.Query(
		`SELECT id, slug, name, is_active
		 FROM subject_labels
		 ORDER BY name ASC, id ASC`,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	results := []subjectLabelSummary{}
	for rows.Next() {
		var (
			item   subjectLabelSummary
			active bool
		)
		if err := rows.Scan(&item.ID, &item.Slug, &item.Name, &active); err != nil {
			return nil, err
		}
		item.IsActive = active
		results = append(results, item)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return results, nil
}

func listTeacherSubjectLabels(db *sql.DB, teacherID int64) ([]subjectLabelSummary, error) {
	rows, err := db.Query(
		`SELECT sl.id, sl.slug, sl.name, sl.is_active
		 FROM teacher_subject_labels tsl
		 JOIN subject_labels sl ON sl.id = tsl.subject_label_id
		 WHERE tsl.teacher_id = ?
		 ORDER BY sl.name ASC, sl.id ASC`,
		teacherID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	results := []subjectLabelSummary{}
	for rows.Next() {
		var (
			item   subjectLabelSummary
			active bool
		)
		if err := rows.Scan(&item.ID, &item.Slug, &item.Name, &active); err != nil {
			return nil, err
		}
		item.IsActive = active
		results = append(results, item)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return results, nil
}

func listCourseSubjectLabels(db *sql.DB, courseID int64) ([]subjectLabelSummary, error) {
	rows, err := db.Query(
		`SELECT sl.id, sl.slug, sl.name, sl.is_active
		 FROM course_subject_labels csl
		 JOIN subject_labels sl ON sl.id = csl.subject_label_id
		 WHERE csl.course_id = ?
		 ORDER BY sl.name ASC, sl.id ASC`,
		courseID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	results := []subjectLabelSummary{}
	for rows.Next() {
		var (
			item   subjectLabelSummary
			active bool
		)
		if err := rows.Scan(&item.ID, &item.Slug, &item.Name, &active); err != nil {
			return nil, err
		}
		item.IsActive = active
		results = append(results, item)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return results, nil
}

func findSubjectLabelIDBySlugTx(tx *sql.Tx, slug string) (int64, error) {
	row := tx.QueryRow(
		`SELECT id
		 FROM subject_labels
		 WHERE slug = ? AND is_active = TRUE
		 LIMIT 1`,
		strings.TrimSpace(strings.ToLower(slug)),
	)
	var id int64
	if err := row.Scan(&id); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return 0, fiber.NewError(fiber.StatusBadRequest, "subject label not found")
		}
		return 0, err
	}
	return id, nil
}

func dedupePositiveInt64s(values []int64) []int64 {
	seen := map[int64]struct{}{}
	results := make([]int64, 0, len(values))
	for _, value := range values {
		if value <= 0 {
			continue
		}
		if _, ok := seen[value]; ok {
			continue
		}
		seen[value] = struct{}{}
		results = append(results, value)
	}
	sort.Slice(results, func(i, j int) bool {
		return results[i] < results[j]
	})
	return results
}
