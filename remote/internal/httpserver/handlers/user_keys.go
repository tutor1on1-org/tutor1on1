package handlers

import (
	"database/sql"
	"errors"
	"strings"

	"github.com/gofiber/fiber/v2"
)

type UserKeysHandler struct {
	cfg Dependencies
}

func NewUserKeysHandler(deps Dependencies) *UserKeysHandler {
	return &UserKeysHandler{cfg: deps}
}

type upsertUserKeyRequest struct {
	PublicKey       string `json:"public_key"`
	EncPrivateKey   string `json:"enc_private_key"`
	KdfSalt         string `json:"kdf_salt"`
	KdfIterations   int    `json:"kdf_iterations"`
	KdfAlgorithm    string `json:"kdf_algorithm"`
}

func (h *UserKeysHandler) GetSelf(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	row := h.cfg.Store.DB.QueryRow(
		`SELECT public_key, enc_private_key, kdf_salt, kdf_iterations, kdf_algorithm
		 FROM user_keys WHERE user_id = ? LIMIT 1`,
		userID,
	)
	var (
		publicKey    string
		encPrivate   string
		kdfSalt      string
		kdfIter      int
		kdfAlgorithm string
	)
	if err := row.Scan(&publicKey, &encPrivate, &kdfSalt, &kdfIter, &kdfAlgorithm); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return c.JSON(fiber.Map{})
		}
		return fiber.NewError(fiber.StatusInternalServerError, "key lookup failed")
	}
	return c.JSON(fiber.Map{
		"public_key":       publicKey,
		"enc_private_key":  encPrivate,
		"kdf_salt":         kdfSalt,
		"kdf_iterations":   kdfIter,
		"kdf_algorithm":    kdfAlgorithm,
	})
}

func (h *UserKeysHandler) UpsertSelf(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	var req upsertUserKeyRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	if strings.TrimSpace(req.PublicKey) == "" ||
		strings.TrimSpace(req.EncPrivateKey) == "" ||
		strings.TrimSpace(req.KdfSalt) == "" ||
		strings.TrimSpace(req.KdfAlgorithm) == "" ||
		req.KdfIterations <= 0 {
		return fiber.NewError(fiber.StatusBadRequest, "key fields required")
	}
	_, err = h.cfg.Store.DB.Exec(
		`INSERT INTO user_keys
		 (user_id, public_key, enc_private_key, kdf_salt, kdf_iterations, kdf_algorithm)
		 VALUES (?, ?, ?, ?, ?, ?)
		 ON DUPLICATE KEY UPDATE
		   public_key = VALUES(public_key),
		   enc_private_key = VALUES(enc_private_key),
		   kdf_salt = VALUES(kdf_salt),
		   kdf_iterations = VALUES(kdf_iterations),
		   kdf_algorithm = VALUES(kdf_algorithm)`,
		userID,
		strings.TrimSpace(req.PublicKey),
		strings.TrimSpace(req.EncPrivateKey),
		strings.TrimSpace(req.KdfSalt),
		req.KdfIterations,
		strings.TrimSpace(req.KdfAlgorithm),
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "key save failed")
	}
	return c.JSON(fiber.Map{"status": "ok"})
}

func (h *UserKeysHandler) GetCourseKeys(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	courseID, err := parseInt64Query(c, "course_id")
	if err != nil {
		return err
	}
	var (
		teacherUserID int64
	)
	row := h.cfg.Store.DB.QueryRow(
		`SELECT ta.user_id
		 FROM courses c
		 JOIN teacher_accounts ta ON c.teacher_id = ta.id
		 WHERE c.id = ?`,
		courseID,
	)
	if err := row.Scan(&teacherUserID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusNotFound, "course not found")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "course lookup failed")
	}

	var studentUserID int64
	if userID == teacherUserID {
		studentUserID, err = parseInt64Query(c, "student_user_id")
		if err != nil {
			return err
		}
		if ok, err := isEnrolled(h.cfg.Store.DB, studentUserID, courseID); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "enrollment check failed")
		} else if !ok {
			return fiber.NewError(fiber.StatusForbidden, "student not enrolled")
		}
	} else {
		if ok, err := isEnrolled(h.cfg.Store.DB, userID, courseID); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "enrollment check failed")
		} else if !ok {
			return fiber.NewError(fiber.StatusForbidden, "forbidden")
		}
		studentUserID = userID
	}

	teacherKey, err := lookupPublicKey(h.cfg.Store.DB, teacherUserID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusConflict, "teacher key missing")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "teacher key lookup failed")
	}
	studentKey, err := lookupPublicKey(h.cfg.Store.DB, studentUserID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusConflict, "student key missing")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "student key lookup failed")
	}

	return c.JSON(fiber.Map{
		"course_id":         courseID,
		"teacher_user_id":   teacherUserID,
		"teacher_public_key": teacherKey,
		"student_user_id":   studentUserID,
		"student_public_key": studentKey,
	})
}

func lookupPublicKey(db *sql.DB, userID int64) (string, error) {
	row := db.QueryRow("SELECT public_key FROM user_keys WHERE user_id = ? LIMIT 1", userID)
	var key string
	if err := row.Scan(&key); err != nil {
		return "", err
	}
	return key, nil
}

func isEnrolled(db *sql.DB, studentID int64, courseID int64) (bool, error) {
	row := db.QueryRow(
		`SELECT 1 FROM enrollments
		 WHERE student_id = ? AND course_id = ? AND status = 'active' LIMIT 1`,
		studentID, courseID,
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
