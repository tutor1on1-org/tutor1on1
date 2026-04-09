package handlers

import (
	"archive/zip"
	"bytes"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"os"
	"strconv"
	"strings"
	"time"

	"family_teacher_remote/internal/artifactsync"
	"family_teacher_remote/internal/storage"

	"github.com/gofiber/fiber/v2"
)

type ArtifactSyncHandler struct {
	cfg Dependencies
}

type artifactState1ItemResponse struct {
	ArtifactID      string `json:"artifact_id"`
	ArtifactClass   string `json:"artifact_class"`
	CourseID        int64  `json:"course_id"`
	TeacherUserID   int64  `json:"teacher_user_id"`
	StudentUserID   int64  `json:"student_user_id,omitempty"`
	KpKey           string `json:"kp_key,omitempty"`
	BundleVersionID int64  `json:"bundle_version_id,omitempty"`
	SHA256          string `json:"sha256"`
	LastModified    string `json:"last_modified"`
}

type artifactBatchDownloadRequest struct {
	ArtifactIDs []string `json:"artifact_ids"`
}

type artifactBatchUploadRequest struct {
	Items []artifactBatchUploadItemRequest `json:"items"`
}

type artifactBatchUploadItemRequest struct {
	ArtifactID      string `json:"artifact_id"`
	SHA256          string `json:"sha256"`
	BaseSHA256      string `json:"base_sha256"`
	OverwriteServer bool   `json:"overwrite_server"`
	FileField       string `json:"file_field"`
}

type artifactBatchUploadItemResponse struct {
	ArtifactID string `json:"artifact_id"`
	SHA256     string `json:"sha256"`
}

type artifactUploadConflict struct {
	payload fiber.Map
}

func (c artifactUploadConflict) Error() string {
	return "artifact conflict"
}

type artifactBatchManifestItemResponse struct {
	ArtifactID    string `json:"artifact_id"`
	ArtifactClass string `json:"artifact_class"`
	SHA256        string `json:"sha256"`
	LastModified  string `json:"last_modified"`
	EntryName     string `json:"entry_name"`
}

func NewArtifactSyncHandler(deps Dependencies) *ArtifactSyncHandler {
	return &ArtifactSyncHandler{cfg: deps}
}

func (h *ArtifactSyncHandler) State2(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	filter, err := parseVisibleArtifactFilter(c)
	if err != nil {
		return err
	}
	state2, err := h.readFilteredState2(userID, filter)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "artifact state2 failed")
	}
	return c.JSON(fiber.Map{"state2": state2})
}

func (h *ArtifactSyncHandler) State1(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	filter, err := parseVisibleArtifactFilter(c)
	if err != nil {
		return err
	}
	items, err := artifactsync.ListState1Filtered(h.cfg.Store.DB, userID, filter)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "artifact state1 failed")
	}
	responseItems := make([]artifactState1ItemResponse, 0, len(items))
	for _, item := range items {
		responseItems = append(responseItems, artifactState1ItemResponse{
			ArtifactID:      item.ArtifactID,
			ArtifactClass:   item.ArtifactClass,
			CourseID:        item.CourseID,
			TeacherUserID:   item.TeacherUserID,
			StudentUserID:   item.StudentUserID,
			KpKey:           item.KpKey,
			BundleVersionID: item.BundleVersionID,
			SHA256:          item.SHA256,
			LastModified:    item.LastModified.UTC().Format(time.RFC3339),
		})
	}
	return c.JSON(fiber.Map{
		"state2": buildState2FromVisibleArtifacts(items),
		"items":  responseItems,
	})
}

func (h *ArtifactSyncHandler) readFilteredState2(userID int64, filter artifactsync.VisibleArtifactFilter) (string, error) {
	if strings.TrimSpace(filter.ArtifactClass) == "" &&
		filter.StudentUserID <= 0 &&
		filter.CourseID <= 0 {
		return artifactsync.ReadState2(h.cfg.Store.DB, userID)
	}
	items, err := artifactsync.ListState1Filtered(h.cfg.Store.DB, userID, filter)
	if err != nil {
		return "", err
	}
	return buildState2FromVisibleArtifacts(items), nil
}

func parseVisibleArtifactFilter(c *fiber.Ctx) (artifactsync.VisibleArtifactFilter, error) {
	filter := artifactsync.VisibleArtifactFilter{
		ArtifactClass: normalizeArtifactClassFilter(c.Query("artifact_class")),
	}
	if rawStudentUserID := strings.TrimSpace(c.Query("student_user_id")); rawStudentUserID != "" {
		studentUserID, err := strconv.ParseInt(rawStudentUserID, 10, 64)
		if err != nil || studentUserID <= 0 {
			return artifactsync.VisibleArtifactFilter{}, fiber.NewError(
				fiber.StatusBadRequest,
				"student_user_id invalid",
			)
		}
		filter.StudentUserID = studentUserID
	}
	if rawCourseID := strings.TrimSpace(c.Query("course_id")); rawCourseID != "" {
		courseID, err := strconv.ParseInt(rawCourseID, 10, 64)
		if err != nil || courseID <= 0 {
			return artifactsync.VisibleArtifactFilter{}, fiber.NewError(
				fiber.StatusBadRequest,
				"course_id invalid",
			)
		}
		filter.CourseID = courseID
	}
	return filter, nil
}

func buildState2FromVisibleArtifacts(items []artifactsync.VisibleArtifact) string {
	stateItems := make([]artifactsync.State2Item, 0, len(items))
	for _, item := range items {
		stateItems = append(stateItems, artifactsync.State2Item{
			ArtifactID: item.ArtifactID,
			SHA256:     item.SHA256,
		})
	}
	return artifactsync.BuildState2(stateItems)
}

func (h *ArtifactSyncHandler) Download(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	artifactID := strings.TrimSpace(c.Query("artifact_id"))
	if artifactID == "" {
		return fiber.NewError(fiber.StatusBadRequest, "artifact_id required")
	}
	item, err := artifactsync.ReadVisibleArtifact(h.cfg.Store.DB, userID, artifactID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusNotFound, "artifact not found")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "artifact download lookup failed")
	}
	if h.cfg.Storage == nil {
		return fiber.NewError(fiber.StatusServiceUnavailable, "storage unavailable")
	}
	absPath := h.cfg.Storage.AbsolutePath(item.StorageRelPath)
	if _, err := os.Stat(absPath); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return fiber.NewError(fiber.StatusNotFound, "artifact file not found")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "artifact download failed")
	}
	filename := sanitizeArtifactFilename(item.ArtifactID) + ".zip"
	c.Set("X-Accel-Redirect", "/_files/"+strings.TrimLeft(item.StorageRelPath, "/"))
	c.Set("Content-Type", "application/zip")
	c.Set("Content-Disposition", fmt.Sprintf("attachment; filename=\"%s\"", filename))
	c.Set("X-Artifact-Id", item.ArtifactID)
	c.Set("X-Artifact-Sha256", item.SHA256)
	c.Set("X-Artifact-Class", item.ArtifactClass)
	c.Set("X-Artifact-Last-Modified", item.LastModified.UTC().Format(time.RFC3339))
	return c.SendStatus(fiber.StatusOK)
}

func (h *ArtifactSyncHandler) DownloadBatch(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	if h.cfg.Storage == nil {
		return fiber.NewError(fiber.StatusServiceUnavailable, "storage unavailable")
	}
	var request artifactBatchDownloadRequest
	if err := c.BodyParser(&request); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "artifact_ids required")
	}
	artifactIDs := normalizeArtifactIDList(request.ArtifactIDs)
	if len(artifactIDs) == 0 {
		return fiber.NewError(fiber.StatusBadRequest, "artifact_ids required")
	}

	type batchItem struct {
		item      artifactsync.VisibleArtifact
		entryName string
		absPath   string
		sizeBytes int64
	}
	items, err := artifactsync.ReadVisibleArtifactsByIDs(
		h.cfg.Store.DB,
		userID,
		artifactIDs,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusNotFound, "artifact not found")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "artifact download lookup failed")
	}
	batchItems := make([]batchItem, 0, len(items))
	manifestItems := make([]artifactBatchManifestItemResponse, 0, len(artifactIDs))
	for _, item := range items {
		absPath := h.cfg.Storage.AbsolutePath(item.StorageRelPath)
		info, err := os.Stat(absPath)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) {
				return fiber.NewError(fiber.StatusNotFound, "artifact file not found")
			}
			return fiber.NewError(fiber.StatusInternalServerError, "artifact download failed")
		}
		entryName := batchArtifactEntryName(item.ArtifactID)
		batchItems = append(batchItems, batchItem{
			item:      item,
			entryName: entryName,
			absPath:   absPath,
			sizeBytes: info.Size(),
		})
		manifestItems = append(manifestItems, artifactBatchManifestItemResponse{
			ArtifactID:    item.ArtifactID,
			ArtifactClass: item.ArtifactClass,
			SHA256:        item.SHA256,
			LastModified:  item.LastModified.UTC().Format(time.RFC3339),
			EntryName:     entryName,
		})
	}

	manifestBytes, err := json.Marshal(fiber.Map{
		"schema": "artifact_batch_v1",
		"items":  manifestItems,
	})
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "artifact batch manifest failed")
	}

	c.Set("Content-Type", "application/zip")
	c.Set("Content-Disposition", "attachment; filename=\"artifacts_batch.zip\"")
	c.Set("X-Artifact-Batch-Count", fmt.Sprintf("%d", len(batchItems)))
	var buffer bytes.Buffer
	zipWriter := zip.NewWriter(&buffer)
	if err := writeBatchZipEntry(zipWriter, "manifest.json", manifestBytes); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "artifact batch build failed")
	}
	for _, batchItem := range batchItems {
		if err := writeBatchZipFileEntry(
			zipWriter,
			batchItem.entryName,
			batchItem.absPath,
			batchItem.sizeBytes,
		); err != nil {
			_ = zipWriter.Close()
			return fiber.NewError(fiber.StatusInternalServerError, "artifact batch build failed")
		}
	}
	if err := zipWriter.Close(); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "artifact batch build failed")
	}
	return c.SendStream(bytes.NewReader(buffer.Bytes()), buffer.Len())
}

func (h *ArtifactSyncHandler) Upload(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	if h.cfg.Storage == nil {
		return fiber.NewError(fiber.StatusServiceUnavailable, "storage unavailable")
	}
	artifactID := strings.TrimSpace(c.FormValue("artifact_id"))
	baseSHA := strings.TrimSpace(c.FormValue("base_sha256"))
	declaredSHA := strings.TrimSpace(c.FormValue("sha256"))
	overwriteServer := parseBoolFormValue(c.FormValue("overwrite_server"))
	if artifactID == "" || declaredSHA == "" {
		return fiber.NewError(fiber.StatusBadRequest, "artifact_id and sha256 required")
	}
	fileHeader, err := c.FormFile("artifact")
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "artifact file required")
	}
	switch {
	case strings.HasPrefix(artifactID, "course_bundle:"):
		return h.uploadCourseBundle(c, userID, artifactID, baseSHA, declaredSHA, overwriteServer, fileHeader)
	case strings.HasPrefix(artifactID, "student_kp:"):
		return h.uploadStudentKp(c, userID, artifactID, baseSHA, declaredSHA, overwriteServer, fileHeader)
	default:
		return fiber.NewError(fiber.StatusBadRequest, "unsupported artifact_id")
	}
}

func (h *ArtifactSyncHandler) UploadBatch(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	if h.cfg.Storage == nil {
		return fiber.NewError(fiber.StatusServiceUnavailable, "storage unavailable")
	}

	manifestRaw := strings.TrimSpace(c.FormValue("manifest"))
	if manifestRaw == "" {
		return fiber.NewError(fiber.StatusBadRequest, "manifest required")
	}
	var request artifactBatchUploadRequest
	if err := json.Unmarshal([]byte(manifestRaw), &request); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "manifest invalid")
	}
	if len(request.Items) == 0 {
		return fiber.NewError(fiber.StatusBadRequest, "items required")
	}

	form, err := c.MultipartForm()
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "artifact files required")
	}

	affectedCourses := make(map[int64]struct{}, len(request.Items))
	results := make([]artifactBatchUploadItemResponse, 0, len(request.Items))
	for _, item := range request.Items {
		artifactID := strings.TrimSpace(item.ArtifactID)
		if !strings.HasPrefix(artifactID, "student_kp:") {
			return fiber.NewError(fiber.StatusBadRequest, "student_kp artifacts required")
		}
		fileField := strings.TrimSpace(item.FileField)
		if fileField == "" {
			return fiber.NewError(fiber.StatusBadRequest, "file_field required")
		}
		fileHeaders := form.File[fileField]
		if len(fileHeaders) == 0 || fileHeaders[0] == nil {
			return fiber.NewError(fiber.StatusBadRequest, "artifact file required")
		}
		storedSHA, courseID, err := h.uploadStudentKpFileHeader(
			userID,
			artifactID,
			strings.TrimSpace(item.BaseSHA256),
			strings.TrimSpace(item.SHA256),
			item.OverwriteServer,
			fileHeaders[0],
		)
		if err != nil {
			var conflict artifactUploadConflict
			if errors.As(err, &conflict) {
				return c.Status(fiber.StatusConflict).JSON(conflict.payload)
			}
			return err
		}
		affectedCourses[courseID] = struct{}{}
		results = append(results, artifactBatchUploadItemResponse{
			ArtifactID: artifactID,
			SHA256:     storedSHA,
		})
	}

	for courseID := range affectedCourses {
		if err := artifactsync.RefreshUsersForCourse(h.cfg.Store.DB, courseID); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "artifact state refresh failed")
		}
	}
	state2, err := artifactsync.ReadState2(h.cfg.Store.DB, userID)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "artifact state refresh failed")
	}
	return c.JSON(fiber.Map{
		"status": "uploaded",
		"items":  results,
		"state2": state2,
	})
}

func (h *ArtifactSyncHandler) uploadCourseBundle(
	c *fiber.Ctx,
	userID int64,
	artifactID string,
	baseSHA string,
	declaredSHA string,
	overwriteServer bool,
	fileHeader *multipart.FileHeader,
) error {
	courseID, err := artifactsync.ParseCourseBundleArtifactID(artifactID)
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "artifact_id invalid")
	}
	teacherID, err := getTeacherAccountID(h.cfg.Store.DB, userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusForbidden, "teacher account required")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "teacher lookup failed")
	}
	bundleID, currentSHA, currentVersion, err := h.lookupCourseBundleUploadState(courseID, teacherID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusNotFound, "course bundle not found")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "course bundle lookup failed")
	}
	if conflict := uploadConflict(currentSHA, baseSHA, overwriteServer); conflict != nil {
		return c.Status(fiber.StatusConflict).JSON(conflict)
	}
	file, err := fileHeader.Open()
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "artifact open failed")
	}
	defer file.Close()
	nextVersion := currentVersion + 1
	relPath, _, storedSHA, err := h.cfg.Storage.SaveBundle(bundleID, nextVersion, file)
	if err != nil {
		if errors.Is(err, storage.ErrFileExists) {
			return fiber.NewError(fiber.StatusConflict, "bundle version already exists")
		}
		if errors.Is(err, storage.ErrTooLarge) {
			return fiber.NewError(fiber.StatusRequestEntityTooLarge, "artifact too large")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "artifact save failed")
	}
	if storedSHA != declaredSHA {
		_ = h.cfg.Storage.RemoveRelativePath(relPath)
		return fiber.NewError(fiber.StatusBadRequest, "sha256 mismatch")
	}
	result, err := h.cfg.Store.DB.Exec(
		`INSERT INTO bundle_versions (bundle_id, version, hash, oss_path)
		 VALUES (?, ?, ?, ?)`,
		bundleID,
		nextVersion,
		storedSHA,
		relPath,
	)
	if err != nil {
		_ = h.cfg.Storage.RemoveRelativePath(relPath)
		return fiber.NewError(fiber.StatusInternalServerError, "bundle version insert failed")
	}
	bundleVersionID, err := result.LastInsertId()
	if err != nil {
		_ = h.cfg.Storage.RemoveRelativePath(relPath)
		return fiber.NewError(fiber.StatusInternalServerError, "bundle version insert failed")
	}
	if err := artifactsync.RefreshUsersForCourse(h.cfg.Store.DB, courseID); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "artifact state refresh failed")
	}
	state2, err := artifactsync.ReadState2(h.cfg.Store.DB, userID)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "artifact state refresh failed")
	}
	return c.JSON(fiber.Map{
		"status":            "uploaded",
		"artifact_id":       artifactID,
		"sha256":            storedSHA,
		"bundle_version_id": bundleVersionID,
		"state2":            state2,
	})
}

func (h *ArtifactSyncHandler) uploadStudentKp(
	c *fiber.Ctx,
	userID int64,
	artifactID string,
	baseSHA string,
	declaredSHA string,
	overwriteServer bool,
	fileHeader *multipart.FileHeader,
) error {
	storedSHA, courseID, err := h.uploadStudentKpFileHeader(
		userID,
		artifactID,
		baseSHA,
		declaredSHA,
		overwriteServer,
		fileHeader,
	)
	if err != nil {
		var conflict artifactUploadConflict
		if errors.As(err, &conflict) {
			return c.Status(fiber.StatusConflict).JSON(conflict.payload)
		}
		return err
	}
	if err := artifactsync.RefreshUsersForCourse(h.cfg.Store.DB, courseID); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "artifact state refresh failed")
	}
	state2, err := artifactsync.ReadState2(h.cfg.Store.DB, userID)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "artifact state refresh failed")
	}
	return c.JSON(fiber.Map{
		"status":      "uploaded",
		"artifact_id": artifactID,
		"sha256":      storedSHA,
		"state2":      state2,
	})
}

func (h *ArtifactSyncHandler) uploadStudentKpFileHeader(
	userID int64,
	artifactID string,
	baseSHA string,
	declaredSHA string,
	overwriteServer bool,
	fileHeader *multipart.FileHeader,
) (string, int64, error) {
	studentUserID, courseID, kpKey, err := artifactsync.ParseStudentKpArtifactID(artifactID)
	if err != nil {
		return "", 0, fiber.NewError(fiber.StatusBadRequest, "artifact_id invalid")
	}
	if userID != studentUserID {
		return "", 0, fiber.NewError(fiber.StatusForbidden, "student artifact upload forbidden")
	}
	enrolled, err := isEnrolled(h.cfg.Store.DB, userID, courseID)
	if err != nil {
		return "", 0, fiber.NewError(fiber.StatusInternalServerError, "enrollment check failed")
	}
	if !enrolled {
		return "", 0, fiber.NewError(fiber.StatusForbidden, "student not enrolled")
	}
	teacherUserID, err := getTeacherUserIDForCourse(h.cfg.Store.DB, courseID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", 0, fiber.NewError(fiber.StatusNotFound, "course not found")
		}
		return "", 0, fiber.NewError(fiber.StatusInternalServerError, "course lookup failed")
	}
	currentSHA, err := h.lookupStudentKpUploadState(artifactID)
	if err != nil {
		return "", 0, fiber.NewError(fiber.StatusInternalServerError, "student artifact lookup failed")
	}
	if conflict := uploadConflict(currentSHA, baseSHA, overwriteServer); conflict != nil {
		return "", 0, artifactUploadConflict{payload: conflict}
	}
	file, err := fileHeader.Open()
	if err != nil {
		return "", 0, fiber.NewError(fiber.StatusBadRequest, "artifact open failed")
	}
	defer file.Close()
	zipBytes, err := io.ReadAll(file)
	if err != nil {
		return "", 0, fiber.NewError(fiber.StatusBadRequest, "artifact read failed")
	}
	payload, computedSHA, err := artifactsync.ReadStudentKpArtifactPayload(zipBytes)
	if err != nil {
		return "", 0, fiber.NewError(fiber.StatusBadRequest, "student artifact invalid")
	}
	if computedSHA != declaredSHA {
		return "", 0, fiber.NewError(fiber.StatusBadRequest, "sha256 mismatch")
	}
	if payload.CourseID != courseID ||
		payload.StudentRemoteUserID != studentUserID ||
		strings.TrimSpace(payload.KpKey) != strings.TrimSpace(kpKey) ||
		payload.TeacherRemoteUserID != teacherUserID {
		return "", 0, fiber.NewError(fiber.StatusBadRequest, "student artifact payload identity mismatch")
	}
	storageRelPath := artifactsync.StudentKpStorageRelPath(studentUserID, courseID, kpKey)
	_, storedSHA, err := h.cfg.Storage.SaveRelativePath(storageRelPath, bytes.NewReader(zipBytes))
	if err != nil {
		if errors.Is(err, storage.ErrTooLarge) {
			return "", 0, fiber.NewError(fiber.StatusRequestEntityTooLarge, "artifact too large")
		}
		return "", 0, fiber.NewError(fiber.StatusInternalServerError, "artifact save failed")
	}
	if storedSHA != declaredSHA {
		return "", 0, fiber.NewError(fiber.StatusBadRequest, "sha256 mismatch")
	}
	tx, err := h.cfg.Store.DB.Begin()
	if err != nil {
		return "", 0, fiber.NewError(fiber.StatusInternalServerError, "transaction failed")
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()
	lastModified := parseRFC3339OrNow(payload.UpdatedAt)
	if err := artifactsync.UpsertStudentKpArtifactTx(
		tx,
		artifactID,
		courseID,
		teacherUserID,
		studentUserID,
		kpKey,
		storageRelPath,
		storedSHA,
		lastModified,
	); err != nil {
		return "", 0, fiber.NewError(fiber.StatusInternalServerError, "student artifact save failed")
	}
	if err := tx.Commit(); err != nil {
		return "", 0, fiber.NewError(fiber.StatusInternalServerError, "commit failed")
	}
	committed = true
	return storedSHA, courseID, nil
}

func (h *ArtifactSyncHandler) lookupCourseBundleUploadState(
	courseID int64,
	teacherAccountID int64,
) (int64, string, int, error) {
	row := h.cfg.Store.DB.QueryRow(
		`SELECT b.id,
		        COALESCE((
		          SELECT bv.hash
		          FROM bundle_versions bv
		          WHERE bv.bundle_id = b.id
		          ORDER BY bv.version DESC, bv.id DESC
		          LIMIT 1
		        ), ''),
		        COALESCE((
		          SELECT bv.version
		          FROM bundle_versions bv
		          WHERE bv.bundle_id = b.id
		          ORDER BY bv.version DESC, bv.id DESC
		          LIMIT 1
		        ), 0)
		 FROM bundles b
		 WHERE b.course_id = ? AND b.teacher_id = ?
		 LIMIT 1`,
		courseID,
		teacherAccountID,
	)
	var bundleID int64
	var currentSHA string
	var currentVersion int
	if err := row.Scan(&bundleID, &currentSHA, &currentVersion); err != nil {
		return 0, "", 0, err
	}
	return bundleID, strings.TrimSpace(currentSHA), currentVersion, nil
}

func (h *ArtifactSyncHandler) lookupStudentKpUploadState(artifactID string) (string, error) {
	row := h.cfg.Store.DB.QueryRow(
		`SELECT sha256
		 FROM student_kp_artifacts
		 WHERE artifact_id = ?
		 LIMIT 1`,
		artifactID,
	)
	var sha string
	if err := row.Scan(&sha); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", nil
		}
		return "", err
	}
	return strings.TrimSpace(sha), nil
}

func uploadConflict(currentSHA string, baseSHA string, overwriteServer bool) fiber.Map {
	trimmedCurrent := strings.TrimSpace(currentSHA)
	trimmedBase := strings.TrimSpace(baseSHA)
	if overwriteServer {
		return nil
	}
	if trimmedCurrent == "" {
		if trimmedBase != "" {
			return fiber.Map{
				"status":          "conflict",
				"conflict_type":   "server_missing_expected",
				"server_sha256":   "",
				"expected_base":   trimmedBase,
				"resolution":      "explicit_choice_required",
				"allowed_actions": []string{"keep_server", "overwrite_server_with_local", "defer"},
			}
		}
		return nil
	}
	if trimmedBase == "" {
		return fiber.Map{
			"status":          "conflict",
			"conflict_type":   "base_sha256_required",
			"server_sha256":   trimmedCurrent,
			"expected_base":   "",
			"resolution":      "explicit_choice_required",
			"allowed_actions": []string{"keep_server", "overwrite_server_with_local", "defer"},
		}
	}
	if trimmedBase != trimmedCurrent {
		return fiber.Map{
			"status":          "conflict",
			"conflict_type":   "server_changed",
			"server_sha256":   trimmedCurrent,
			"expected_base":   trimmedBase,
			"resolution":      "explicit_choice_required",
			"allowed_actions": []string{"keep_server", "overwrite_server_with_local", "defer"},
		}
	}
	return nil
}

func parseBoolFormValue(raw string) bool {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "1", "true", "yes", "y", "on":
		return true
	default:
		return false
	}
}

func sanitizeArtifactFilename(artifactID string) string {
	replacer := strings.NewReplacer(":", "_", "/", "_", "\\", "_", " ", "_")
	trimmed := strings.TrimSpace(replacer.Replace(artifactID))
	if trimmed == "" {
		return "artifact"
	}
	return trimmed
}

func normalizeArtifactIDList(values []string) []string {
	normalized := make([]string, 0, len(values))
	seen := make(map[string]struct{}, len(values))
	for _, value := range values {
		trimmed := strings.TrimSpace(value)
		if trimmed == "" {
			continue
		}
		if _, ok := seen[trimmed]; ok {
			continue
		}
		seen[trimmed] = struct{}{}
		normalized = append(normalized, trimmed)
	}
	return normalized
}

func batchArtifactEntryName(artifactID string) string {
	return "artifacts/" + base64.RawURLEncoding.EncodeToString([]byte(strings.TrimSpace(artifactID))) + ".zip"
}

func writeBatchZipEntry(writer *zip.Writer, name string, data []byte) error {
	header := &zip.FileHeader{
		Name:     name,
		Method:   zip.Store,
		Modified: time.Unix(0, 0).UTC(),
	}
	header.SetMode(0600)
	entry, err := writer.CreateHeader(header)
	if err != nil {
		return err
	}
	_, err = entry.Write(data)
	return err
}

func writeBatchZipFileEntry(
	writer *zip.Writer,
	name string,
	absPath string,
	sizeBytes int64,
) error {
	file, err := os.Open(absPath)
	if err != nil {
		return err
	}
	defer file.Close()

	header := &zip.FileHeader{
		Name:               name,
		Method:             zip.Store,
		Modified:           time.Unix(0, 0).UTC(),
		UncompressedSize64: uint64(sizeBytes),
	}
	header.SetMode(0600)
	entry, err := writer.CreateHeader(header)
	if err != nil {
		return err
	}
	_, err = io.Copy(entry, file)
	return err
}

func parseRFC3339OrNow(raw string) time.Time {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return time.Now().UTC()
	}
	parsed, err := time.Parse(time.RFC3339, trimmed)
	if err != nil {
		return time.Now().UTC()
	}
	return parsed.UTC()
}

func normalizeArtifactClassFilter(raw string) string {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "":
		return ""
	case "student_kp":
		return "student_kp"
	case "course_bundle":
		return "course_bundle"
	default:
		return ""
	}
}

func filterVisibleArtifacts(
	items []artifactsync.VisibleArtifact,
	artifactClass string,
) []artifactsync.VisibleArtifact {
	if artifactClass == "" {
		return items
	}
	filtered := make([]artifactsync.VisibleArtifact, 0, len(items))
	for _, item := range items {
		if item.ArtifactClass == artifactClass {
			filtered = append(filtered, item)
		}
	}
	return filtered
}

func isEnrolled(db *sql.DB, studentUserID int64, courseID int64) (bool, error) {
	row := db.QueryRow(
		`SELECT 1
		 FROM enrollments
		 WHERE student_id = ? AND course_id = ? AND status = 'active'
		 LIMIT 1`,
		studentUserID,
		courseID,
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

func getTeacherUserIDForCourse(db *sql.DB, courseID int64) (int64, error) {
	row := db.QueryRow(
		`SELECT ta.user_id
		 FROM courses c
		 JOIN teacher_accounts ta ON ta.id = c.teacher_id
		 WHERE c.id = ?
		 LIMIT 1`,
		courseID,
	)
	var teacherUserID int64
	if err := row.Scan(&teacherUserID); err != nil {
		return 0, err
	}
	return teacherUserID, nil
}
