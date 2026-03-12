package handlers

import (
	"archive/zip"
	"bufio"
	"bytes"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"family_teacher_remote/internal/storage"

	"github.com/gofiber/fiber/v2"
)

var contentsLinePattern = regexp.MustCompile(`^(\d+(?:\.\d+)*)\s*(.+)$`)

type BundlesHandler struct {
	cfg     Dependencies
	storage *storage.Service
}

type bundleVersionPruneTarget struct {
	id      int64
	relPath string
}

type bundleCourseInfo struct {
	teacherUserID int64
	courseID      int64
	courseName    string
}

type latestBundleInfo struct {
	id      int64
	version int
	hash    string
	relPath string
}

func ensureStoredBundleHash(
	db *sql.DB,
	bundleStorage *storage.Service,
	bundleVersionID int64,
	currentHash string,
	relPath string,
) (string, bool, int64, error) {
	hashVal := strings.TrimSpace(currentHash)
	if bundleStorage == nil {
		return hashVal, false, 0, nil
	}
	absPath := strings.TrimSpace(bundleStorage.BundleAbsolutePath(relPath))
	if absPath == "" {
		return hashVal, false, 0, nil
	}
	info, statErr := os.Stat(absPath)
	if statErr != nil {
		if errors.Is(statErr, os.ErrNotExist) {
			return hashVal, true, 0, nil
		}
		return "", false, 0, statErr
	}
	sizeBytes := info.Size()
	if hashVal != "" {
		return hashVal, false, sizeBytes, nil
	}
	semanticHash, hashErr := computeBundleSemanticHash(absPath)
	if hashErr != nil {
		return "", false, 0, hashErr
	}
	if bundleVersionID > 0 {
		if _, updateErr := db.Exec(
			"UPDATE bundle_versions SET hash = ? WHERE id = ?",
			semanticHash,
			bundleVersionID,
		); updateErr != nil {
			return "", false, 0, updateErr
		}
	}
	return semanticHash, false, sizeBytes, nil
}

func bundleHashResolutionError(err error) error {
	if errors.Is(err, os.ErrNotExist) {
		return fiber.NewError(fiber.StatusInternalServerError, "bundle file stat failed")
	}
	if _, ok := err.(*os.PathError); ok {
		return fiber.NewError(fiber.StatusInternalServerError, "bundle file stat failed")
	}
	return fiber.NewError(fiber.StatusInternalServerError, "bundle hash rebuild failed")
}

func NewBundlesHandler(deps Dependencies) *BundlesHandler {
	return &BundlesHandler{
		cfg:     deps,
		storage: deps.Storage,
	}
}

func (h *BundlesHandler) Upload(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	bundleID, err := parseInt64Query(c, "bundle_id")
	if err != nil {
		return err
	}
	courseName := strings.TrimSpace(c.Query("course_name"))
	if courseName == "" {
		return fiber.NewError(fiber.StatusBadRequest, "course_name required")
	}
	if h.storage == nil {
		return fiber.NewError(fiber.StatusServiceUnavailable, "storage unavailable")
	}
	info, err := h.getBundleCourseInfo(bundleID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusNotFound, "bundle not found")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "bundle lookup failed")
	}
	if info.teacherUserID != userID {
		return fiber.NewError(fiber.StatusForbidden, "forbidden")
	}
	if normalizeCourseName(courseName) != normalizeCourseName(info.courseName) {
		return fiber.NewError(fiber.StatusBadRequest, "course_name mismatch")
	}
	file, err := c.FormFile("bundle")
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "bundle file required")
	}
	if file.Size > h.cfg.Config.BundleMaxBytes {
		return fiber.NewError(fiber.StatusRequestEntityTooLarge, "bundle too large")
	}

	const maxAttempts = 6
	for attempt := 0; attempt < maxAttempts; attempt++ {
		latest, hasLatest, err := h.lookupLatestBundleVersion(bundleID)
		if err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "bundle lookup failed")
		}
		nextVersion := 1
		if hasLatest {
			nextVersion = latest.version + 1
		}

		src, err := file.Open()
		if err != nil {
			return fiber.NewError(fiber.StatusBadRequest, "bundle open failed")
		}
		relPath, size, _, saveErr := h.storage.SaveBundle(bundleID, nextVersion, src)
		_ = src.Close()
		if saveErr != nil {
			if errors.Is(saveErr, storage.ErrFileExists) {
				continue
			}
			if errors.Is(saveErr, storage.ErrTooLarge) {
				return fiber.NewError(fiber.StatusRequestEntityTooLarge, "bundle too large")
			}
			return fiber.NewError(fiber.StatusInternalServerError, "bundle save failed")
		}

		absPath := h.storage.BundleAbsolutePath(relPath)
		newNodeSet, validateErr := extractNodeIDsFromBundle(absPath)
		if validateErr != nil {
			_ = h.removeStoredFile(relPath)
			return fiber.NewError(fiber.StatusBadRequest, "invalid bundle: "+validateErr.Error())
		}
		semanticHash, hashErr := computeBundleSemanticHash(absPath)
		if hashErr != nil {
			_ = h.removeStoredFile(relPath)
			return fiber.NewError(fiber.StatusBadRequest, "invalid bundle: "+hashErr.Error())
		}

		addedCount := len(newNodeSet)
		removedCount := 0
		if hasLatest {
			oldPath := h.storage.BundleAbsolutePath(latest.relPath)
			oldNodeSet, oldErr := extractNodeIDsFromBundle(oldPath)
			if oldErr != nil {
				_ = h.removeStoredFile(relPath)
				return fiber.NewError(fiber.StatusInternalServerError, "latest bundle parse failed")
			}
			addedCount, removedCount = countNodeDiff(oldNodeSet, newNodeSet)
			latestSemanticHash, latestHashErr := computeBundleSemanticHash(oldPath)
			if latestHashErr != nil {
				_ = h.removeStoredFile(relPath)
				return fiber.NewError(fiber.StatusInternalServerError, "latest bundle hash failed")
			}
			if latestSemanticHash == semanticHash {
				_ = h.removeStoredFile(relPath)
				return c.JSON(fiber.Map{
					"bundle_version_id": latest.id,
					"bundle_id":         bundleID,
					"version":           latest.version,
					"path":              latest.relPath,
					"size":              size,
					"hash":              latestSemanticHash,
					"status":            "unchanged",
					"added_nodes":       0,
					"removed_nodes":     0,
				})
			}
		}

		tx, err := h.cfg.Store.DB.Begin()
		if err != nil {
			_ = h.removeStoredFile(relPath)
			return fiber.NewError(fiber.StatusInternalServerError, "transaction failed")
		}
		result, insertErr := tx.Exec(
			"INSERT INTO bundle_versions (bundle_id, version, hash, oss_path) VALUES (?, ?, ?, ?)",
			bundleID, nextVersion, semanticHash, relPath,
		)
		if insertErr != nil {
			_ = tx.Rollback()
			_ = h.removeStoredFile(relPath)
			if isDuplicateEntryError(insertErr) {
				continue
			}
			return fiber.NewError(fiber.StatusBadRequest, "bundle version insert failed")
		}
		insertID, err := result.LastInsertId()
		if err != nil {
			_ = tx.Rollback()
			_ = h.removeStoredFile(relPath)
			return fiber.NewError(fiber.StatusInternalServerError, "bundle version insert failed")
		}
		prunedTargets, pruneErr := h.collectPruneTargets(tx, bundleID, 5)
		if pruneErr != nil {
			_ = tx.Rollback()
			_ = h.removeStoredFile(relPath)
			return fiber.NewError(fiber.StatusInternalServerError, "bundle prune lookup failed")
		}
		for _, target := range prunedTargets {
			if _, err = tx.Exec(
				"DELETE FROM bundle_versions WHERE id = ?",
				target.id,
			); err != nil {
				_ = tx.Rollback()
				_ = h.removeStoredFile(relPath)
				return fiber.NewError(fiber.StatusInternalServerError, "bundle prune failed")
			}
		}
		var approvalStatus string
		statusRow := tx.QueryRow(
			`SELECT approval_status
			 FROM course_catalog_entries
			 WHERE course_id = ?
			 LIMIT 1`,
			info.courseID,
		)
		if err := statusRow.Scan(&approvalStatus); err != nil {
			_ = tx.Rollback()
			_ = h.removeStoredFile(relPath)
			return fiber.NewError(fiber.StatusInternalServerError, "course approval lookup failed")
		}
		if strings.TrimSpace(strings.ToLower(approvalStatus)) != "approved" {
			if _, err := tx.Exec(
				`INSERT INTO course_upload_requests
				 (course_id, bundle_id, bundle_version_id, requested_visibility, status)
				 VALUES (?, ?, ?, 'public', 'pending')
				 ON DUPLICATE KEY UPDATE
				   bundle_id = VALUES(bundle_id),
				   bundle_version_id = VALUES(bundle_version_id),
				   requested_visibility = VALUES(requested_visibility),
				   status = 'pending',
				   resolved_at = NULL,
				   resolved_by_user_id = NULL,
				   created_at = CURRENT_TIMESTAMP`,
				info.courseID,
				bundleID,
				insertID,
			); err != nil {
				_ = tx.Rollback()
				_ = h.removeStoredFile(relPath)
				return fiber.NewError(fiber.StatusInternalServerError, "course upload request save failed")
			}
		}
		if err = tx.Commit(); err != nil {
			_ = h.removeStoredFile(relPath)
			return fiber.NewError(fiber.StatusInternalServerError, "commit failed")
		}
		for _, target := range prunedTargets {
			if removeErr := h.removeStoredFile(target.relPath); removeErr != nil {
				return fiber.NewError(fiber.StatusInternalServerError, "bundle file delete failed")
			}
		}
		return c.JSON(fiber.Map{
			"bundle_version_id": insertID,
			"bundle_id":         bundleID,
			"version":           nextVersion,
			"path":              relPath,
			"size":              size,
			"hash":              semanticHash,
			"status":            "uploaded",
			"pruned_count":      len(prunedTargets),
			"added_nodes":       addedCount,
			"removed_nodes":     removedCount,
		})
	}

	return fiber.NewError(fiber.StatusConflict, "bundle version retry limit reached")
}

func (h *BundlesHandler) ListTeacherCourseBundleVersions(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	teacherID, err := getTeacherAccountID(h.cfg.Store.DB, userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusForbidden, "teacher account required")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "teacher lookup failed")
	}
	courseID, err := parseInt64Param(c, "id")
	if err != nil {
		return err
	}

	rows, err := h.cfg.Store.DB.Query(
		`SELECT bv.id, b.id, bv.version, bv.hash, bv.oss_path, bv.created_at
		 FROM bundle_versions bv
		 JOIN bundles b ON b.id = bv.bundle_id
		 WHERE b.course_id = ? AND b.teacher_id = ?
		 ORDER BY bv.version DESC, bv.id DESC`,
		courseID,
		teacherID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "bundle version list failed")
	}
	defer rows.Close()

	type bundleVersionSummary struct {
		BundleVersionID int64  `json:"bundle_version_id"`
		BundleID        int64  `json:"bundle_id"`
		Version         int    `json:"version"`
		Hash            string `json:"hash"`
		CreatedAt       string `json:"created_at"`
		SizeBytes       int64  `json:"size_bytes"`
		IsLatest        bool   `json:"is_latest"`
		FileMissing     bool   `json:"file_missing"`
	}

	results := []bundleVersionSummary{}
	index := 0
	for rows.Next() {
		var (
			bundleVersionID int64
			bundleID        int64
			versionVal      int
			hashVal         string
			relPathVal      string
			createdAt       sql.NullTime
		)
		if err := rows.Scan(
			&bundleVersionID,
			&bundleID,
			&versionVal,
			&hashVal,
			&relPathVal,
			&createdAt,
		); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "bundle version list failed")
		}

		resolvedHash, fileMissing, sizeBytes, hashErr := ensureStoredBundleHash(
			h.cfg.Store.DB,
			h.storage,
			bundleVersionID,
			hashVal,
			relPathVal,
		)
		if hashErr != nil {
			return bundleHashResolutionError(hashErr)
		}
		hashVal = resolvedHash

		created := ""
		if createdAt.Valid {
			created = createdAt.Time.Format(timeLayout)
		}
		results = append(results, bundleVersionSummary{
			BundleVersionID: bundleVersionID,
			BundleID:        bundleID,
			Version:         versionVal,
			Hash:            hashVal,
			CreatedAt:       created,
			SizeBytes:       sizeBytes,
			IsLatest:        index == 0,
			FileMissing:     fileMissing,
		})
		index++
	}
	if err := rows.Err(); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "bundle version list failed")
	}

	return c.JSON(results)
}

func (h *BundlesHandler) GetLatestCourseBundleInfo(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	courseID, err := parseInt64Query(c, "course_id")
	if err != nil {
		return err
	}

	row := h.cfg.Store.DB.QueryRow(
		`SELECT bv.id, b.id, bv.version, bv.hash, bv.oss_path, b.teacher_id, ta.user_id
		 FROM bundle_versions bv
		 JOIN bundles b ON b.id = bv.bundle_id
		 JOIN courses c ON c.id = b.course_id
		 JOIN teacher_accounts ta ON ta.id = c.teacher_id
		 WHERE c.id = ?
		 ORDER BY bv.version DESC, bv.id DESC
		 LIMIT 1`,
		courseID,
	)
	var (
		bundleVersionID int64
		bundleID        int64
		versionVal      int
		hashVal         string
		relPathVal      string
		teacherID       int64
		teacherUserID   int64
	)
	if err := row.Scan(
		&bundleVersionID,
		&bundleID,
		&versionVal,
		&hashVal,
		&relPathVal,
		&teacherID,
		&teacherUserID,
	); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusNotFound, "bundle version not found")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "bundle lookup failed")
	}

	if userID != teacherUserID {
		enrolled, enrollErr := h.isEnrolled(userID, courseID, teacherID)
		if enrollErr != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "bundle access check failed")
		}
		if !enrolled {
			return fiber.NewError(fiber.StatusForbidden, "bundle access denied")
		}
	}

	resolvedHash, fileMissing, _, hashErr := ensureStoredBundleHash(
		h.cfg.Store.DB,
		h.storage,
		bundleVersionID,
		hashVal,
		relPathVal,
	)
	if hashErr != nil {
		return bundleHashResolutionError(hashErr)
	}

	return c.JSON(fiber.Map{
		"course_id":         courseID,
		"bundle_id":         bundleID,
		"bundle_version_id": bundleVersionID,
		"version":           versionVal,
		"hash":              resolvedHash,
		"file_missing":      fileMissing,
	})
}

func (h *BundlesHandler) DeleteTeacherCourseBundleVersion(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	teacherID, err := getTeacherAccountID(h.cfg.Store.DB, userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusForbidden, "teacher account required")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "teacher lookup failed")
	}
	courseID, err := parseInt64Param(c, "id")
	if err != nil {
		return err
	}
	bundleVersionID, err := parseInt64Param(c, "versionId")
	if err != nil {
		return err
	}

	var relPath string
	row := h.cfg.Store.DB.QueryRow(
		`SELECT bv.oss_path
		 FROM bundle_versions bv
		 JOIN bundles b ON b.id = bv.bundle_id
		 WHERE bv.id = ? AND b.course_id = ? AND b.teacher_id = ?`,
		bundleVersionID,
		courseID,
		teacherID,
	)
	if err := row.Scan(&relPath); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusNotFound, "bundle version not found")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "bundle version lookup failed")
	}

	result, err := h.cfg.Store.DB.Exec(
		`DELETE bv FROM bundle_versions bv
		 JOIN bundles b ON b.id = bv.bundle_id
		 WHERE bv.id = ? AND b.course_id = ? AND b.teacher_id = ?`,
		bundleVersionID,
		courseID,
		teacherID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "bundle version delete failed")
	}
	affected, err := result.RowsAffected()
	if err != nil || affected == 0 {
		return fiber.NewError(fiber.StatusNotFound, "bundle version not found")
	}
	hasRemaining, err := h.hasBundleVersions(courseID, teacherID)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "bundle version lookup failed")
	}
	if !hasRemaining {
		if _, err := h.cfg.Store.DB.Exec(
			`UPDATE course_catalog_entries
			 SET visibility = 'private', published_at = NULL
			 WHERE course_id = ? AND teacher_id = ?`,
			courseID,
			teacherID,
		); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "catalog update failed")
		}
	}

	if removeErr := h.removeStoredFile(relPath); removeErr != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "bundle file delete failed")
	}
	return c.JSON(fiber.Map{
		"bundle_version_id": bundleVersionID,
		"status":            "deleted",
	})
}

func (h *BundlesHandler) collectPruneTargets(
	tx *sql.Tx,
	bundleID int64,
	keep int,
) ([]bundleVersionPruneTarget, error) {
	rows, err := tx.Query(
		`SELECT id, oss_path
		 FROM bundle_versions
		 WHERE bundle_id = ?
		 ORDER BY version DESC, id DESC`,
		bundleID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	targets := []bundleVersionPruneTarget{}
	index := 0
	for rows.Next() {
		var (
			id      int64
			relPath string
		)
		if err := rows.Scan(&id, &relPath); err != nil {
			return nil, err
		}
		if index >= keep {
			targets = append(targets, bundleVersionPruneTarget{
				id:      id,
				relPath: relPath,
			})
		}
		index++
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return targets, nil
}

func (h *BundlesHandler) Download(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	bundleVersionID, err := parseInt64Query(c, "bundle_version_id")
	if err != nil {
		return err
	}
	var (
		relPath       string
		version       int
		bundleID      int64
		courseID      int64
		teacherID     int64
		teacherUserID int64
	)
	row := h.cfg.Store.DB.QueryRow(
		`SELECT bv.oss_path, bv.version, b.id, b.course_id, b.teacher_id, ta.user_id
		 FROM bundle_versions bv
		 JOIN bundles b ON bv.bundle_id = b.id
		 JOIN teacher_accounts ta ON b.teacher_id = ta.id
		 WHERE bv.id = ?`,
		bundleVersionID,
	)
	if err := row.Scan(&relPath, &version, &bundleID, &courseID, &teacherID, &teacherUserID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusNotFound, "bundle version not found")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "bundle lookup failed")
	}

	if userID != teacherUserID {
		ok, err := h.isEnrolled(userID, courseID, teacherID)
		if err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "enrollment check failed")
		}
		if !ok {
			return fiber.NewError(fiber.StatusForbidden, "forbidden")
		}
	}

	accelPath := "/_files/" + strings.TrimLeft(relPath, "/")
	filename := fmt.Sprintf("bundle_%d_v%d.zip", bundleID, version)
	c.Set("X-Accel-Redirect", accelPath)
	c.Set("Content-Type", "application/zip")
	c.Set("Content-Disposition", fmt.Sprintf("attachment; filename=\"%s\"", filename))
	return c.SendStatus(fiber.StatusOK)
}

func (h *BundlesHandler) getBundleCourseInfo(bundleID int64) (bundleCourseInfo, error) {
	row := h.cfg.Store.DB.QueryRow(
		`SELECT ta.user_id, c.id, c.subject
		 FROM bundles b
		 JOIN courses c ON c.id = b.course_id
		 JOIN teacher_accounts ta ON b.teacher_id = ta.id
		 WHERE b.id = ?`,
		bundleID,
	)
	var (
		teacherUserID int64
		courseID      int64
		courseName    string
	)
	if err := row.Scan(&teacherUserID, &courseID, &courseName); err != nil {
		return bundleCourseInfo{}, err
	}
	return bundleCourseInfo{
		teacherUserID: teacherUserID,
		courseID:      courseID,
		courseName:    courseName,
	}, nil
}

func (h *BundlesHandler) lookupLatestBundleVersion(bundleID int64) (latestBundleInfo, bool, error) {
	row := h.cfg.Store.DB.QueryRow(
		`SELECT id, version, hash, oss_path
		 FROM bundle_versions
		 WHERE bundle_id = ?
		 ORDER BY version DESC, id DESC
		 LIMIT 1`,
		bundleID,
	)
	var latest latestBundleInfo
	if err := row.Scan(&latest.id, &latest.version, &latest.hash, &latest.relPath); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return latestBundleInfo{}, false, nil
		}
		return latestBundleInfo{}, false, err
	}
	return latest, true, nil
}

func (h *BundlesHandler) isEnrolled(studentID int64, courseID int64, teacherID int64) (bool, error) {
	row := h.cfg.Store.DB.QueryRow(
		`SELECT 1 FROM enrollments
		 WHERE student_id = ? AND course_id = ? AND teacher_id = ? AND status = 'active'
		 LIMIT 1`,
		studentID, courseID, teacherID,
	)
	var ok int
	if err := row.Scan(&ok); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return false, nil
		}
		return false, err
	}
	return true, nil
}

func (h *BundlesHandler) removeStoredFile(relPath string) error {
	if h.storage == nil {
		return nil
	}
	absPath := h.storage.BundleAbsolutePath(relPath)
	if strings.TrimSpace(absPath) == "" {
		return nil
	}
	if err := os.Remove(absPath); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return nil
}

func (h *BundlesHandler) hasBundleVersions(courseID int64, teacherID int64) (bool, error) {
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
		if errors.Is(err, sql.ErrNoRows) {
			return false, nil
		}
		return false, err
	}
	return true, nil
}

func parseInt64Query(c *fiber.Ctx, name string) (int64, error) {
	val := strings.TrimSpace(c.Query(name))
	if val == "" {
		return 0, fiber.NewError(fiber.StatusBadRequest, name+" required")
	}
	parsed, err := strconv.ParseInt(val, 10, 64)
	if err != nil || parsed <= 0 {
		return 0, fiber.NewError(fiber.StatusBadRequest, name+" invalid")
	}
	return parsed, nil
}

func extractNodeIDsFromBundle(zipPath string) (map[string]struct{}, error) {
	reader, err := zip.OpenReader(zipPath)
	if err != nil {
		return nil, errors.New("zip open failed")
	}
	defer reader.Close()

	filesByName := map[string]*zip.File{}
	normalizedNames := map[string]struct{}{}
	for _, file := range reader.File {
		if file.FileInfo().IsDir() {
			continue
		}
		name := normalizeZipEntryName(file.Name)
		if name == "" {
			continue
		}
		if name == "_family_teacher/prompt_bundle.json" {
			continue
		}
		if strings.HasPrefix(name, "__MACOSX/") {
			continue
		}
		if hasAppleDoubleSegment(name) {
			continue
		}
		filesByName[name] = file
		normalizedNames[name] = struct{}{}
	}
	if len(filesByName) == 0 {
		return nil, errors.New("bundle contains no usable files")
	}

	rootCandidates := []string{}
	for name := range normalizedNames {
		if name == "contents.txt" || name == "context.txt" {
			rootCandidates = append(rootCandidates, "")
			continue
		}
		if strings.HasSuffix(name, "/contents.txt") || strings.HasSuffix(name, "/context.txt") {
			idx := strings.LastIndex(name, "/")
			if idx > 0 {
				rootCandidates = append(rootCandidates, name[:idx])
			}
		}
	}
	if len(rootCandidates) == 0 {
		return nil, errors.New("missing contents.txt or context.txt")
	}
	sort.Slice(rootCandidates, func(i, j int) bool {
		left := rootCandidates[i]
		right := rootCandidates[j]
		if len(left) == len(right) {
			return left < right
		}
		return len(left) < len(right)
	})

	selectedRoot := ""
	contentsName := ""
	for _, root := range rootCandidates {
		contentsPath := joinRoot(root, "contents.txt")
		contextPath := joinRoot(root, "context.txt")
		if _, ok := filesByName[contentsPath]; ok {
			selectedRoot = root
			contentsName = contentsPath
			break
		}
		if _, ok := filesByName[contextPath]; ok {
			selectedRoot = root
			contentsName = contextPath
			break
		}
	}
	if contentsName == "" {
		return nil, errors.New("missing contents.txt or context.txt")
	}

	contentsFile := filesByName[contentsName]
	if contentsFile == nil {
		return nil, errors.New("missing contents.txt or context.txt")
	}
	nodeIDs, err := parseNodeIDs(contentsFile)
	if err != nil {
		return nil, err
	}
	if len(nodeIDs) == 0 {
		return nil, errors.New("contents has no nodes")
	}

	missing := []string{}
	for _, nodeID := range nodeIDs {
		lecturePath := joinRoot(selectedRoot, nodeID+"_lecture.txt")
		legacyPath := joinRoot(selectedRoot, path.Join(nodeID, "lecture.txt"))
		_, hasLecture := normalizedNames[lecturePath]
		_, hasLegacy := normalizedNames[legacyPath]
		if !hasLecture && !hasLegacy {
			missing = append(missing, nodeID)
		}
	}
	if len(missing) > 0 {
		preview := missing
		if len(preview) > 12 {
			preview = preview[:12]
		}
		return nil, fmt.Errorf("missing lecture files for ids: %s", strings.Join(preview, ", "))
	}

	nodeSet := map[string]struct{}{}
	for _, nodeID := range nodeIDs {
		nodeSet[nodeID] = struct{}{}
	}
	return nodeSet, nil
}

func countNodeDiff(oldSet map[string]struct{}, newSet map[string]struct{}) (int, int) {
	added := 0
	for key := range newSet {
		if _, ok := oldSet[key]; !ok {
			added++
		}
	}
	removed := 0
	for key := range oldSet {
		if _, ok := newSet[key]; !ok {
			removed++
		}
	}
	return added, removed
}

func isDuplicateEntryError(err error) bool {
	return strings.Contains(strings.ToLower(err.Error()), "duplicate entry")
}

func normalizeCourseName(value string) string {
	return strings.ToLower(strings.Join(strings.Fields(strings.TrimSpace(value)), " "))
}

func computeBundleSemanticHash(zipPath string) (string, error) {
	reader, err := zip.OpenReader(zipPath)
	if err != nil {
		return "", errors.New("zip open failed")
	}
	defer reader.Close()

	type filePayload struct {
		name string
		data []byte
	}
	files := []filePayload{}
	for _, file := range reader.File {
		if file.FileInfo().IsDir() {
			continue
		}
		name := normalizeZipEntryName(file.Name)
		if name == "" {
			continue
		}
		if strings.HasPrefix(name, "__MACOSX/") {
			continue
		}
		if hasAppleDoubleSegment(name) {
			continue
		}
		entry, err := file.Open()
		if err != nil {
			return "", errors.New("zip entry open failed")
		}
		data, err := io.ReadAll(entry)
		_ = entry.Close()
		if err != nil {
			return "", errors.New("zip entry read failed")
		}
		if name == "_family_teacher/prompt_bundle.json" {
			normalized, normErr := normalizePromptMetadata(data)
			if normErr != nil {
				return "", normErr
			}
			data = normalized
		}
		files = append(files, filePayload{
			name: name,
			data: data,
		})
	}
	sort.Slice(files, func(i, j int) bool {
		return files[i].name < files[j].name
	})

	hasher := sha256.New()
	for _, file := range files {
		_, _ = hasher.Write([]byte(file.name))
		_, _ = hasher.Write([]byte{0})
		_, _ = hasher.Write(file.data)
		_, _ = hasher.Write([]byte{0})
	}
	return hex.EncodeToString(hasher.Sum(nil)), nil
}

func normalizePromptMetadata(raw []byte) ([]byte, error) {
	var decoded interface{}
	if err := json.Unmarshal(raw, &decoded); err != nil {
		return nil, errors.New("prompt metadata json invalid")
	}
	cleaned := removeGeneratedFields(decoded)
	canonical, err := marshalCanonicalJSON(cleaned)
	if err != nil {
		return nil, errors.New("prompt metadata canonicalize failed")
	}
	return canonical, nil
}

func removeGeneratedFields(value interface{}) interface{} {
	switch typed := value.(type) {
	case map[string]interface{}:
		next := make(map[string]interface{}, len(typed))
		for key, inner := range typed {
			if key == "generated_at" {
				continue
			}
			next[key] = removeGeneratedFields(inner)
		}
		return next
	case []interface{}:
		next := make([]interface{}, 0, len(typed))
		for _, inner := range typed {
			next = append(next, removeGeneratedFields(inner))
		}
		return next
	default:
		return value
	}
}

func marshalCanonicalJSON(value interface{}) ([]byte, error) {
	var buf bytes.Buffer
	if err := writeCanonicalJSON(&buf, value); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func writeCanonicalJSON(buf *bytes.Buffer, value interface{}) error {
	switch typed := value.(type) {
	case nil:
		buf.WriteString("null")
		return nil
	case bool:
		if typed {
			buf.WriteString("true")
		} else {
			buf.WriteString("false")
		}
		return nil
	case string:
		encoded, err := json.Marshal(typed)
		if err != nil {
			return err
		}
		buf.Write(encoded)
		return nil
	case float64, json.Number, int, int32, int64, uint, uint32, uint64:
		encoded, err := json.Marshal(typed)
		if err != nil {
			return err
		}
		buf.Write(encoded)
		return nil
	case map[string]interface{}:
		keys := make([]string, 0, len(typed))
		for key := range typed {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		buf.WriteByte('{')
		for index, key := range keys {
			if index > 0 {
				buf.WriteByte(',')
			}
			encodedKey, err := json.Marshal(key)
			if err != nil {
				return err
			}
			buf.Write(encodedKey)
			buf.WriteByte(':')
			if err := writeCanonicalJSON(buf, typed[key]); err != nil {
				return err
			}
		}
		buf.WriteByte('}')
		return nil
	case []interface{}:
		buf.WriteByte('[')
		for index, inner := range typed {
			if index > 0 {
				buf.WriteByte(',')
			}
			if err := writeCanonicalJSON(buf, inner); err != nil {
				return err
			}
		}
		buf.WriteByte(']')
		return nil
	default:
		encoded, err := json.Marshal(typed)
		if err != nil {
			return err
		}
		buf.Write(encoded)
		return nil
	}
}

func parseNodeIDs(file *zip.File) ([]string, error) {
	reader, err := file.Open()
	if err != nil {
		return nil, errors.New("contents read failed")
	}
	defer reader.Close()

	data, err := io.ReadAll(reader)
	if err != nil {
		return nil, errors.New("contents read failed")
	}
	text := string(data)
	scanner := bufio.NewScanner(strings.NewReader(text))
	ids := map[string]struct{}{}
	lineNum := 0
	for scanner.Scan() {
		lineNum++
		line := strings.TrimSpace(scanner.Text())
		if lineNum == 1 {
			line = strings.TrimPrefix(line, "\uFEFF")
		}
		if line == "" {
			continue
		}
		match := contentsLinePattern.FindStringSubmatch(line)
		if len(match) != 3 {
			return nil, fmt.Errorf("invalid contents line %d", lineNum)
		}
		ids[match[1]] = struct{}{}
	}
	if err := scanner.Err(); err != nil {
		return nil, errors.New("contents parse failed")
	}
	list := make([]string, 0, len(ids))
	for id := range ids {
		list = append(list, id)
	}
	sort.Strings(list)
	return list, nil
}

func normalizeZipEntryName(name string) string {
	cleaned := path.Clean(strings.ReplaceAll(name, "\\", "/"))
	cleaned = strings.TrimPrefix(cleaned, "/")
	if cleaned == "." {
		return ""
	}
	return cleaned
}

func hasAppleDoubleSegment(name string) bool {
	parts := strings.Split(name, "/")
	for _, part := range parts {
		if strings.HasPrefix(part, "._") {
			return true
		}
	}
	return false
}

func joinRoot(root string, rel string) string {
	if strings.TrimSpace(root) == "" {
		return normalizeZipEntryName(rel)
	}
	return normalizeZipEntryName(path.Join(root, rel))
}
