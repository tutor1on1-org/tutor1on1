package handlers

import (
	"archive/zip"
	"bufio"
	"database/sql"
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

func NewBundlesHandler(deps Dependencies) *BundlesHandler {
	return &BundlesHandler{
		cfg:     deps,
		storage: deps.Storage,
	}
}

func (h *BundlesHandler) Upload(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTSecret)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	bundleID, err := parseInt64Query(c, "bundle_id")
	if err != nil {
		return err
	}
	version, err := parseIntQuery(c, "version")
	if err != nil {
		return err
	}
	if h.storage == nil {
		return fiber.NewError(fiber.StatusServiceUnavailable, "storage unavailable")
	}
	if err := h.ensureTeacherOwnsBundle(userID, bundleID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusNotFound, "bundle not found")
		}
		return fiber.NewError(fiber.StatusForbidden, "forbidden")
	}
	file, err := c.FormFile("bundle")
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "bundle file required")
	}
	if file.Size > h.cfg.Config.BundleMaxBytes {
		return fiber.NewError(fiber.StatusRequestEntityTooLarge, "bundle too large")
	}
	src, err := file.Open()
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "bundle open failed")
	}
	defer src.Close()

	relPath, size, hash, err := h.storage.SaveBundle(bundleID, version, src)
	if err != nil {
		if errors.Is(err, storage.ErrFileExists) {
			return fiber.NewError(fiber.StatusConflict, "bundle version exists")
		}
		if errors.Is(err, storage.ErrTooLarge) {
			return fiber.NewError(fiber.StatusRequestEntityTooLarge, "bundle too large")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "bundle save failed")
	}
	absPath := h.storage.BundleAbsolutePath(relPath)
	if err := validateCourseBundle(absPath); err != nil {
		_ = h.removeStoredFile(relPath)
		return fiber.NewError(fiber.StatusBadRequest, "invalid bundle: "+err.Error())
	}
	var (
		latestID      int64
		latestVersion int
		latestHash    string
		latestPath    string
	)
	latestRow := h.cfg.Store.DB.QueryRow(
		`SELECT id, version, hash, oss_path
		 FROM bundle_versions
		 WHERE bundle_id = ?
		 ORDER BY version DESC, id DESC
		 LIMIT 1`,
		bundleID,
	)
	if err := latestRow.Scan(&latestID, &latestVersion, &latestHash, &latestPath); err == nil {
		if latestHash == hash {
			_ = h.removeStoredFile(relPath)
			return c.JSON(fiber.Map{
				"bundle_version_id": latestID,
				"bundle_id":         bundleID,
				"version":           latestVersion,
				"path":              latestPath,
				"size":              size,
				"hash":              hash,
				"status":            "unchanged",
			})
		}
	} else if !errors.Is(err, sql.ErrNoRows) {
		_ = h.removeStoredFile(relPath)
		return fiber.NewError(fiber.StatusInternalServerError, "bundle lookup failed")
	}

	tx, err := h.cfg.Store.DB.Begin()
	if err != nil {
		_ = h.removeStoredFile(relPath)
		return fiber.NewError(fiber.StatusInternalServerError, "transaction failed")
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	result, err := tx.Exec(
		"INSERT INTO bundle_versions (bundle_id, version, hash, oss_path) VALUES (?, ?, ?, ?)",
		bundleID, version, hash, relPath,
	)
	if err != nil {
		_ = h.removeStoredFile(relPath)
		return fiber.NewError(fiber.StatusBadRequest, "bundle version insert failed")
	}
	insertID, err := result.LastInsertId()
	if err != nil {
		_ = h.removeStoredFile(relPath)
		return fiber.NewError(fiber.StatusInternalServerError, "bundle version insert failed")
	}

	prunedTargets, err := h.collectPruneTargets(tx, bundleID, 5)
	if err != nil {
		_ = h.removeStoredFile(relPath)
		return fiber.NewError(fiber.StatusInternalServerError, "bundle prune lookup failed")
	}
	for _, target := range prunedTargets {
		if _, err = tx.Exec(
			"DELETE FROM bundle_versions WHERE id = ?",
			target.id,
		); err != nil {
			_ = h.removeStoredFile(relPath)
			return fiber.NewError(fiber.StatusInternalServerError, "bundle prune failed")
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
		"version":           version,
		"path":              relPath,
		"size":              size,
		"hash":              hash,
		"status":            "uploaded",
		"pruned_count":      len(prunedTargets),
	})
}

func (h *BundlesHandler) ListTeacherCourseBundleVersions(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTSecret)
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

		sizeBytes := int64(0)
		fileMissing := false
		if h.storage != nil {
			absPath := h.storage.BundleAbsolutePath(relPathVal)
			info, statErr := os.Stat(absPath)
			if statErr != nil {
				if errors.Is(statErr, os.ErrNotExist) {
					fileMissing = true
				} else {
					return fiber.NewError(fiber.StatusInternalServerError, "bundle file stat failed")
				}
			} else {
				sizeBytes = info.Size()
			}
		}

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

func (h *BundlesHandler) DeleteTeacherCourseBundleVersion(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTSecret)
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
	userID, err := requireUserID(c, h.cfg.Config.JWTSecret)
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

func (h *BundlesHandler) ensureTeacherOwnsBundle(userID int64, bundleID int64) error {
	var teacherUserID int64
	row := h.cfg.Store.DB.QueryRow(
		`SELECT ta.user_id
		 FROM bundles b
		 JOIN teacher_accounts ta ON b.teacher_id = ta.id
		 WHERE b.id = ?`,
		bundleID,
	)
	if err := row.Scan(&teacherUserID); err != nil {
		return err
	}
	if teacherUserID != userID {
		return errors.New("not owner")
	}
	return nil
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

func parseIntQuery(c *fiber.Ctx, name string) (int, error) {
	val := strings.TrimSpace(c.Query(name))
	if val == "" {
		return 0, fiber.NewError(fiber.StatusBadRequest, name+" required")
	}
	parsed, err := strconv.Atoi(val)
	if err != nil || parsed <= 0 {
		return 0, fiber.NewError(fiber.StatusBadRequest, name+" invalid")
	}
	return parsed, nil
}

func validateCourseBundle(zipPath string) error {
	reader, err := zip.OpenReader(zipPath)
	if err != nil {
		return errors.New("zip open failed")
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
		return errors.New("bundle contains no usable files")
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
		return errors.New("missing contents.txt or context.txt")
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
		return errors.New("missing contents.txt or context.txt")
	}

	contentsFile := filesByName[contentsName]
	if contentsFile == nil {
		return errors.New("missing contents.txt or context.txt")
	}
	nodeIDs, err := parseNodeIDs(contentsFile)
	if err != nil {
		return err
	}
	if len(nodeIDs) == 0 {
		return errors.New("contents has no nodes")
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
		return fmt.Errorf("missing lecture files for ids: %s", strings.Join(preview, ", "))
	}
	return nil
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
