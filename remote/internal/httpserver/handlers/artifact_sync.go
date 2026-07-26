package handlers

import (
	"archive/zip"
	"bytes"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"hash/fnv"
	"io"
	"log"
	"mime/multipart"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"family_teacher_remote/internal/artifactsync"
	"family_teacher_remote/internal/storage"

	"github.com/gofiber/fiber/v2"
)

type ArtifactSyncHandler struct {
	cfg           Dependencies
	mutationLocks [64]sync.Mutex
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

type artifactDeleteRequest struct {
	ArtifactID      string `json:"artifact_id"`
	BaseSHA256      string `json:"base_sha256"`
	OverwriteServer bool   `json:"overwrite_server"`
}

type teacherStudentSessionDeleteRequest struct {
	ArtifactID    string `json:"artifact_id"`
	SessionSyncID string `json:"session_sync_id"`
	BaseSHA256    string `json:"base_sha256"`
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

func (h *ArtifactSyncHandler) lockArtifactMutation(artifactID string) func() {
	hasher := fnv.New32a()
	_, _ = hasher.Write([]byte(strings.TrimSpace(artifactID)))
	lock := &h.mutationLocks[int(hasher.Sum32())%len(h.mutationLocks)]
	lock.Lock()
	return lock.Unlock
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

	results := make([]artifactBatchUploadItemResponse, 0, len(request.Items))
	state2 := ""
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
		storedSHA, _, nextState2, err := h.uploadStudentKpFileHeader(
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
		state2 = nextState2
		results = append(results, artifactBatchUploadItemResponse{
			ArtifactID: artifactID,
			SHA256:     storedSHA,
		})
	}
	if strings.TrimSpace(state2) == "" {
		return fiber.NewError(fiber.StatusInternalServerError, "artifact state refresh failed")
	}
	return c.JSON(fiber.Map{
		"status": "uploaded",
		"items":  results,
		"state2": state2,
	})
}

func (h *ArtifactSyncHandler) Delete(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	if h.cfg.Storage == nil {
		return fiber.NewError(fiber.StatusServiceUnavailable, "storage unavailable")
	}
	var request artifactDeleteRequest
	if err := json.Unmarshal(c.Body(), &request); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "delete request invalid")
	}
	artifactID := strings.TrimSpace(request.ArtifactID)
	if !strings.HasPrefix(artifactID, "student_kp:") {
		return fiber.NewError(fiber.StatusBadRequest, "student_kp artifact required")
	}
	studentUserID, courseID, kpKey, err := artifactsync.ParseStudentKpArtifactID(artifactID)
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "artifact_id invalid")
	}
	if userID != studentUserID {
		return fiber.NewError(fiber.StatusForbidden, "student artifact delete forbidden")
	}
	enrollmentID, err := lookupActiveEnrollmentID(h.cfg.Store.DB, userID, courseID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusForbidden, "student not enrolled")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "enrollment check failed")
	}
	teacherUserID, err := getTeacherUserIDForCourse(h.cfg.Store.DB, courseID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusNotFound, "course not found")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "course lookup failed")
	}
	unlockMutation := h.lockArtifactMutation(artifactID)
	defer unlockMutation()
	tx, err := h.cfg.Store.DB.Begin()
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "transaction failed")
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()
	enrolled, err := isEnrollmentActiveTx(
		tx,
		enrollmentID,
		userID,
		courseID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "enrollment check failed")
	}
	if !enrolled {
		return fiber.NewError(fiber.StatusForbidden, "student not enrolled")
	}
	currentSHA, storageRelPath, err := lookupStudentKpMutationStateTx(tx, artifactID)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return fiber.NewError(fiber.StatusInternalServerError, "student artifact lookup failed")
	}
	if conflict := uploadConflict(currentSHA, strings.TrimSpace(request.BaseSHA256), request.OverwriteServer); conflict != nil {
		return c.Status(fiber.StatusConflict).JSON(conflict)
	}
	if strings.TrimSpace(currentSHA) == "" {
		if err := tx.Rollback(); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "rollback failed")
		}
		committed = true
		state2, err := artifactsync.ReadState2(h.cfg.Store.DB, userID)
		if err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "artifact state read failed")
		}
		return c.JSON(fiber.Map{
			"status":      "deleted",
			"artifact_id": artifactID,
			"state2":      state2,
		})
	}
	result, err := tx.Exec(
		`DELETE FROM student_kp_artifacts
		 WHERE artifact_id = ? AND student_user_id = ? AND sha256 = ?`,
		artifactID,
		userID,
		currentSHA,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "student artifact delete failed")
	}
	affected, err := result.RowsAffected()
	if err != nil || affected != 1 {
		return fiber.NewError(fiber.StatusConflict, "student artifact changed")
	}
	state2ByUserID, err := artifactsync.ApplyStudentKpArtifactVisibilityTx(
		tx,
		artifactsync.VisibleArtifact{
			ArtifactID:    artifactID,
			ArtifactClass: "student_kp",
			CourseID:      courseID,
			TeacherUserID: teacherUserID,
			StudentUserID: studentUserID,
			KpKey:         kpKey,
			LastModified:  time.Now().UTC(),
		},
		true,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "artifact state refresh failed")
	}
	state2, ok := state2ByUserID[userID]
	if !ok || strings.TrimSpace(state2) == "" {
		return fiber.NewError(fiber.StatusInternalServerError, "artifact state refresh failed")
	}
	if err := tx.Commit(); err != nil {
		log.Printf(
			"student artifact delete commit outcome uncertain; artifact_id=%s path=%s",
			artifactID,
			storageRelPath,
		)
		return fiber.NewError(fiber.StatusInternalServerError, "commit failed")
	}
	committed = true
	// Keep the old artifact file so an already-issued X-Accel-Redirect remains valid.
	return c.JSON(fiber.Map{
		"status":      "deleted",
		"artifact_id": artifactID,
		"state2":      state2,
	})
}

func (h *ArtifactSyncHandler) DeleteStudentSessionAsTeacher(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	if h.cfg.Storage == nil {
		return fiber.NewError(fiber.StatusServiceUnavailable, "storage unavailable")
	}
	var request teacherStudentSessionDeleteRequest
	if err := json.Unmarshal(c.Body(), &request); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "delete request invalid")
	}
	artifactID := strings.TrimSpace(request.ArtifactID)
	sessionSyncID := strings.TrimSpace(request.SessionSyncID)
	baseSHA := strings.TrimSpace(request.BaseSHA256)
	studentUserID, courseID, kpKey, err := artifactsync.ParseStudentKpArtifactID(artifactID)
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "artifact_id invalid")
	}
	if sessionSyncID == "" || baseSHA == "" {
		return fiber.NewError(fiber.StatusBadRequest, "session_sync_id and base_sha256 required")
	}
	teacherAccountID, err := getTeacherAccountID(h.cfg.Store.DB, userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusForbidden, "active teacher account required")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "teacher lookup failed")
	}
	ownsCourse, err := isCourseOwnedByTeacher(h.cfg.Store.DB, teacherAccountID, courseID)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "course ownership check failed")
	}
	if !ownsCourse {
		return fiber.NewError(fiber.StatusForbidden, "teacher does not own course")
	}
	enrollmentID, err := lookupActiveEnrollmentID(
		h.cfg.Store.DB,
		studentUserID,
		courseID,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusForbidden, "student not enrolled")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "enrollment check failed")
	}
	unlockMutation := h.lockArtifactMutation(artifactID)
	defer unlockMutation()
	tx, err := h.cfg.Store.DB.Begin()
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "transaction failed")
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()
	enrolled, err := isEnrollmentActiveTx(
		tx,
		enrollmentID,
		studentUserID,
		courseID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "enrollment check failed")
	}
	if !enrolled {
		return fiber.NewError(fiber.StatusForbidden, "student not enrolled")
	}
	currentSHA, storageRelPath, err := lookupStudentKpMutationStateTx(tx, artifactID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			if err := tx.Rollback(); err != nil {
				return fiber.NewError(fiber.StatusInternalServerError, "rollback failed")
			}
			committed = true
			state2, err := artifactsync.ReadState2(h.cfg.Store.DB, userID)
			if err != nil {
				return fiber.NewError(fiber.StatusInternalServerError, "artifact state read failed")
			}
			return c.JSON(fiber.Map{
				"status":           "session_already_deleted",
				"artifact_id":      artifactID,
				"artifact_deleted": true,
				"sha256":           "",
				"state2":           state2,
			})
		}
		return fiber.NewError(fiber.StatusInternalServerError, "student artifact lookup failed")
	}
	if currentSHA == "" || storageRelPath == "" {
		return fiber.NewError(fiber.StatusNotFound, "student artifact not found")
	}
	originalBytes, err := os.ReadFile(h.cfg.Storage.AbsolutePath(storageRelPath))
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "student artifact read failed")
	}
	typedPayload, computedSHA, err := artifactsync.ReadStudentKpArtifactPayload(originalBytes)
	if err != nil || computedSHA != currentSHA {
		return fiber.NewError(fiber.StatusInternalServerError, "stored student artifact invalid")
	}
	if typedPayload.CourseID != courseID ||
		typedPayload.StudentRemoteUserID != studentUserID ||
		typedPayload.TeacherRemoteUserID != userID ||
		strings.TrimSpace(typedPayload.KpKey) != strings.TrimSpace(kpKey) {
		return fiber.NewError(fiber.StatusInternalServerError, "stored student artifact identity mismatch")
	}
	rawPayload, rawSHA, err := artifactsync.ReadStudentKpArtifactPayloadMap(originalBytes)
	if err != nil || rawSHA != currentSHA {
		return fiber.NewError(fiber.StatusInternalServerError, "stored student artifact invalid")
	}
	rawSessions, ok := rawPayload["sessions"].([]interface{})
	if !ok {
		return fiber.NewError(fiber.StatusInternalServerError, "stored student sessions invalid")
	}
	remainingSessions := make([]interface{}, 0, len(rawSessions))
	sessionFound := false
	for _, rawSession := range rawSessions {
		session, ok := rawSession.(map[string]interface{})
		if !ok {
			return fiber.NewError(fiber.StatusInternalServerError, "stored student session invalid")
		}
		storedSyncID, ok := session["session_sync_id"].(string)
		if !ok || strings.TrimSpace(storedSyncID) == "" {
			return fiber.NewError(fiber.StatusInternalServerError, "stored student session invalid")
		}
		if strings.TrimSpace(storedSyncID) == sessionSyncID {
			sessionFound = true
			continue
		}
		remainingSessions = append(remainingSessions, rawSession)
	}
	if !sessionFound {
		if err := tx.Rollback(); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "rollback failed")
		}
		committed = true
		state2, err := artifactsync.ReadState2(h.cfg.Store.DB, userID)
		if err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "artifact state read failed")
		}
		return c.JSON(fiber.Map{
			"status":           "session_already_deleted",
			"artifact_id":      artifactID,
			"artifact_deleted": false,
			"sha256":           currentSHA,
			"state2":           state2,
		})
	}
	if conflict := uploadConflict(currentSHA, baseSHA, false); conflict != nil {
		return c.Status(fiber.StatusConflict).JSON(conflict)
	}
	mistakeCount, err := studentKpMistakeCount(rawPayload["mistakes"])
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "stored student mistakes invalid")
	}
	delete(rawPayload, "progress")
	rawPayload["sessions"] = remainingSessions
	now := time.Now().UTC()
	rawPayload["updated_at"] = now.Format(time.RFC3339Nano)

	artifactDeleted := len(remainingSessions) == 0 &&
		mistakeCount == 0 &&
		!studentKpPayloadHasUnknownTopLevelFields(rawPayload)
	nextSHA := ""
	nextStorageRelPath := ""
	commitAttempted := false
	defer func() {
		if !committed && nextStorageRelPath != "" {
			if !commitAttempted && nextStorageRelPath != storageRelPath {
				if err := h.cfg.Storage.RemoveRelativePath(nextStorageRelPath); err != nil {
					log.Printf(
						"teacher session delete candidate cleanup failed; artifact_id=%s path=%s error=%v",
						artifactID,
						nextStorageRelPath,
						err,
					)
				}
			} else {
				log.Printf(
					"teacher session delete left candidate after uncertain commit; artifact_id=%s path=%s",
					artifactID,
					nextStorageRelPath,
				)
			}
		}
	}()
	visibleArtifact := artifactsync.VisibleArtifact{
		ArtifactID:    artifactID,
		ArtifactClass: "student_kp",
		CourseID:      courseID,
		TeacherUserID: userID,
		StudentUserID: studentUserID,
		KpKey:         kpKey,
		LastModified:  now,
	}
	if artifactDeleted {
		result, err := tx.Exec(
			`DELETE FROM student_kp_artifacts
			 WHERE artifact_id = ? AND student_user_id = ? AND sha256 = ?`,
			artifactID,
			studentUserID,
			currentSHA,
		)
		if err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "student artifact delete failed")
		}
		affected, err := result.RowsAffected()
		if err != nil || affected != 1 {
			return fiber.NewError(fiber.StatusConflict, "student artifact changed")
		}
	} else {
		nextBytes, builtSHA, err := artifactsync.BuildStudentKpArtifactZipFromMap(rawPayload)
		if err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "student artifact rebuild failed")
		}
		nextStorageRelPath, err = artifactsync.StudentKpVersionedStorageRelPath(
			studentUserID,
			courseID,
			kpKey,
			builtSHA,
		)
		if err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "student artifact path failed")
		}
		_, storedSHA, err := h.cfg.Storage.SaveRelativePath(
			nextStorageRelPath,
			bytes.NewReader(nextBytes),
		)
		if err != nil {
			if errors.Is(err, storage.ErrTooLarge) {
				return fiber.NewError(fiber.StatusRequestEntityTooLarge, "artifact too large")
			}
			return fiber.NewError(fiber.StatusInternalServerError, "artifact save failed")
		}
		if storedSHA != builtSHA {
			return fiber.NewError(fiber.StatusInternalServerError, "artifact sha256 mismatch")
		}
		result, err := tx.Exec(
			`UPDATE student_kp_artifacts
			 SET teacher_user_id = ?,
			     storage_rel_path = ?,
			     sha256 = ?,
			     last_modified = ?
			 WHERE artifact_id = ? AND student_user_id = ? AND sha256 = ?`,
			userID,
			nextStorageRelPath,
			storedSHA,
			now,
			artifactID,
			studentUserID,
			currentSHA,
		)
		if err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "student artifact save failed")
		}
		affected, err := result.RowsAffected()
		if err != nil || affected != 1 {
			return fiber.NewError(fiber.StatusConflict, "student artifact changed")
		}
		nextSHA = storedSHA
		visibleArtifact.StorageRelPath = nextStorageRelPath
		visibleArtifact.SHA256 = nextSHA
	}
	state2ByUserID, err := artifactsync.ApplyStudentKpArtifactVisibilityTx(
		tx,
		visibleArtifact,
		artifactDeleted,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "artifact state refresh failed")
	}
	state2, ok := state2ByUserID[userID]
	if !ok || strings.TrimSpace(state2) == "" {
		return fiber.NewError(fiber.StatusInternalServerError, "artifact state refresh failed")
	}
	commitAttempted = true
	if err := tx.Commit(); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "commit failed")
	}
	committed = true
	// Keep the old artifact file so an already-issued X-Accel-Redirect remains valid.
	return c.JSON(fiber.Map{
		"status":           "session_deleted",
		"artifact_id":      artifactID,
		"artifact_deleted": artifactDeleted,
		"sha256":           nextSHA,
		"state2":           state2,
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
	storedSHA, _, state2, err := h.uploadStudentKpFileHeader(
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
) (string, int64, string, error) {
	studentUserID, courseID, kpKey, err := artifactsync.ParseStudentKpArtifactID(artifactID)
	if err != nil {
		return "", 0, "", fiber.NewError(fiber.StatusBadRequest, "artifact_id invalid")
	}
	if userID != studentUserID {
		return "", 0, "", fiber.NewError(fiber.StatusForbidden, "student artifact upload forbidden")
	}
	enrollmentID, err := lookupActiveEnrollmentID(h.cfg.Store.DB, userID, courseID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", 0, "", fiber.NewError(fiber.StatusForbidden, "student not enrolled")
		}
		return "", 0, "", fiber.NewError(fiber.StatusInternalServerError, "enrollment check failed")
	}
	teacherUserID, err := getTeacherUserIDForCourse(h.cfg.Store.DB, courseID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", 0, "", fiber.NewError(fiber.StatusNotFound, "course not found")
		}
		return "", 0, "", fiber.NewError(fiber.StatusInternalServerError, "course lookup failed")
	}
	file, err := fileHeader.Open()
	if err != nil {
		return "", 0, "", fiber.NewError(fiber.StatusBadRequest, "artifact open failed")
	}
	defer file.Close()
	zipBytes, err := io.ReadAll(file)
	if err != nil {
		return "", 0, "", fiber.NewError(fiber.StatusBadRequest, "artifact read failed")
	}
	payload, computedSHA, err := artifactsync.ReadStudentKpArtifactPayload(zipBytes)
	if err != nil {
		return "", 0, "", fiber.NewError(fiber.StatusBadRequest, "student artifact invalid")
	}
	if computedSHA != declaredSHA {
		return "", 0, "", fiber.NewError(fiber.StatusBadRequest, "sha256 mismatch")
	}
	if payload.CourseID != courseID ||
		payload.StudentRemoteUserID != studentUserID ||
		strings.TrimSpace(payload.KpKey) != strings.TrimSpace(kpKey) ||
		payload.TeacherRemoteUserID != teacherUserID {
		return "", 0, "", fiber.NewError(fiber.StatusBadRequest, "student artifact payload identity mismatch")
	}
	storageRelPath, err := artifactsync.StudentKpVersionedStorageRelPath(
		studentUserID,
		courseID,
		kpKey,
		declaredSHA,
	)
	if err != nil {
		return "", 0, "", fiber.NewError(fiber.StatusInternalServerError, "artifact path failed")
	}
	unlockMutation := h.lockArtifactMutation(artifactID)
	defer unlockMutation()
	tx, err := h.cfg.Store.DB.Begin()
	if err != nil {
		return "", 0, "", fiber.NewError(fiber.StatusInternalServerError, "transaction failed")
	}
	committed := false
	defer func() {
		if !committed {
			_ = tx.Rollback()
		}
	}()
	enrolled, err := isEnrollmentActiveTx(
		tx,
		enrollmentID,
		userID,
		courseID,
	)
	if err != nil {
		return "", 0, "", fiber.NewError(fiber.StatusInternalServerError, "enrollment check failed")
	}
	if !enrolled {
		return "", 0, "", fiber.NewError(fiber.StatusForbidden, "student not enrolled")
	}
	currentSHA, previousStorageRelPath, err := lookupStudentKpMutationStateTx(tx, artifactID)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return "", 0, "", fiber.NewError(fiber.StatusInternalServerError, "student artifact lookup failed")
	}
	if currentSHA != declaredSHA {
		if conflict := uploadConflict(currentSHA, baseSHA, overwriteServer); conflict != nil {
			return "", 0, "", artifactUploadConflict{payload: conflict}
		}
	}
	commitAttempted := false
	candidateIsNewPath := storageRelPath != previousStorageRelPath
	storedSHA := declaredSHA
	if candidateIsNewPath {
		_, storedSHA, err = h.cfg.Storage.SaveRelativePath(
			storageRelPath,
			bytes.NewReader(zipBytes),
		)
		if err != nil {
			if errors.Is(err, storage.ErrTooLarge) {
				return "", 0, "", fiber.NewError(fiber.StatusRequestEntityTooLarge, "artifact too large")
			}
			return "", 0, "", fiber.NewError(fiber.StatusInternalServerError, "artifact save failed")
		}
	}
	defer func() {
		if !committed && candidateIsNewPath {
			if !commitAttempted {
				if err := h.cfg.Storage.RemoveRelativePath(storageRelPath); err != nil {
					log.Printf(
						"student artifact upload candidate cleanup failed; artifact_id=%s path=%s error=%v",
						artifactID,
						storageRelPath,
						err,
					)
				}
			} else {
				log.Printf(
					"student artifact upload left candidate after uncertain commit; artifact_id=%s path=%s",
					artifactID,
					storageRelPath,
				)
			}
		}
	}()
	if storedSHA != declaredSHA {
		return "", 0, "", fiber.NewError(fiber.StatusBadRequest, "sha256 mismatch")
	}
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
		return "", 0, "", fiber.NewError(fiber.StatusInternalServerError, "student artifact save failed")
	}
	state2ByUserID, err := artifactsync.ApplyStudentKpArtifactVisibilityTx(
		tx,
		artifactsync.VisibleArtifact{
			ArtifactID:     artifactID,
			ArtifactClass:  "student_kp",
			CourseID:       courseID,
			TeacherUserID:  teacherUserID,
			StudentUserID:  studentUserID,
			KpKey:          kpKey,
			StorageRelPath: storageRelPath,
			SHA256:         storedSHA,
			LastModified:   lastModified,
		},
		false,
	)
	if err != nil {
		return "", 0, "", fiber.NewError(fiber.StatusInternalServerError, "artifact state refresh failed")
	}
	state2, ok := state2ByUserID[userID]
	if !ok || strings.TrimSpace(state2) == "" {
		return "", 0, "", fiber.NewError(fiber.StatusInternalServerError, "artifact state refresh failed")
	}
	commitAttempted = true
	if err := tx.Commit(); err != nil {
		return "", 0, "", fiber.NewError(fiber.StatusInternalServerError, "commit failed")
	}
	committed = true
	// Keep the old artifact file so an already-issued X-Accel-Redirect remains valid.
	return storedSHA, courseID, state2, nil
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

func lookupStudentKpMutationStateTx(
	tx *sql.Tx,
	artifactID string,
) (string, string, error) {
	row := tx.QueryRow(
		`SELECT sha256, storage_rel_path
		 FROM student_kp_artifacts
		 WHERE artifact_id = ?
		 LIMIT 1
		 FOR UPDATE`,
		strings.TrimSpace(artifactID),
	)
	var sha string
	var storageRelPath string
	if err := row.Scan(&sha, &storageRelPath); err != nil {
		return "", "", err
	}
	return strings.TrimSpace(sha), strings.TrimSpace(storageRelPath), nil
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

func lookupActiveEnrollmentID(
	db *sql.DB,
	studentUserID int64,
	courseID int64,
) (int64, error) {
	row := db.QueryRow(
		`SELECT id
		 FROM enrollments
		 WHERE student_id = ? AND course_id = ? AND status = 'active'
		 LIMIT 1`,
		studentUserID,
		courseID,
	)
	var enrollmentID int64
	if err := row.Scan(&enrollmentID); err != nil {
		return 0, err
	}
	return enrollmentID, nil
}

func isEnrollmentActiveTx(
	tx *sql.Tx,
	enrollmentID int64,
	studentUserID int64,
	courseID int64,
) (bool, error) {
	row := tx.QueryRow(
		`SELECT status
		 FROM enrollments
		 WHERE id = ? AND student_id = ? AND course_id = ?
		 LIMIT 1
		 FOR UPDATE`,
		enrollmentID,
		studentUserID,
		courseID,
	)
	var status string
	if err := row.Scan(&status); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return false, nil
		}
		return false, err
	}
	return strings.TrimSpace(status) == "active", nil
}

func isCourseOwnedByTeacher(db *sql.DB, teacherAccountID int64, courseID int64) (bool, error) {
	row := db.QueryRow(
		`SELECT 1
		 FROM courses
		 WHERE id = ? AND teacher_id = ?
		 LIMIT 1`,
		courseID,
		teacherAccountID,
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

func studentKpMistakeCount(raw interface{}) (int, error) {
	if raw == nil {
		return 0, nil
	}
	items, ok := raw.([]interface{})
	if !ok {
		return 0, errors.New("mistakes must be a list")
	}
	return len(items), nil
}

func studentKpPayloadHasUnknownTopLevelFields(payload map[string]interface{}) bool {
	knownFields := map[string]struct{}{
		"schema":                 {},
		"course_id":              {},
		"course_subject":         {},
		"kp_key":                 {},
		"teacher_remote_user_id": {},
		"student_remote_user_id": {},
		"student_username":       {},
		"updated_at":             {},
		"progress":               {},
		"mistakes":               {},
		"sessions":               {},
	}
	for key := range payload {
		if _, ok := knownFields[key]; !ok {
			return true
		}
	}
	return false
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
