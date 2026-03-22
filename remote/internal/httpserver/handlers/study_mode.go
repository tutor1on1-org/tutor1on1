package handlers

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
)

type StudyModeHandler struct {
	cfg Dependencies
}

func NewStudyModeHandler(deps Dependencies) *StudyModeHandler {
	return &StudyModeHandler{cfg: deps}
}

type updateTeacherControlPinRequest struct {
	ControlPin string `json:"control_pin"`
}

type studyModeOverrideRequest struct {
	Enabled    bool   `json:"enabled"`
	ControlPin string `json:"control_pin"`
}

type createStudyModeScheduleRequest struct {
	Mode                          string `json:"mode"`
	Enabled                       bool   `json:"enabled"`
	ControlPin                    string `json:"control_pin"`
	StartAtUTC                    string `json:"start_at_utc"`
	EndAtUTC                      string `json:"end_at_utc"`
	LocalWeekday                  int    `json:"local_weekday"`
	LocalStartMinuteOfDay         int    `json:"local_start_minute_of_day"`
	LocalEndMinuteOfDay           int    `json:"local_end_minute_of_day"`
	TimezoneNameSnapshot          string `json:"timezone_name_snapshot"`
	TimezoneOffsetSnapshotMinutes int    `json:"timezone_offset_snapshot_minutes"`
}

type deleteStudyModeScheduleRequest struct {
	ControlPin string `json:"control_pin"`
}

type studentDeviceHeartbeatRequest struct {
	DeviceKey               string `json:"device_key"`
	DeviceName              string `json:"device_name"`
	Platform                string `json:"platform"`
	TimezoneName            string `json:"timezone_name"`
	TimezoneOffsetMinutes   int    `json:"timezone_offset_minutes"`
	LocalWeekday            int    `json:"local_weekday"`
	LocalMinuteOfDay        int    `json:"local_minute_of_day"`
	CurrentStudyModeEnabled bool   `json:"current_study_mode_enabled"`
	AppVersion              string `json:"app_version"`
}

type verifyStudentStudyModeControlPinRequest struct {
	ControlPin       string `json:"control_pin"`
	LocalWeekday     int    `json:"local_weekday"`
	LocalMinuteOfDay int    `json:"local_minute_of_day"`
}

type studyModeScheduleSummary struct {
	ScheduleID                    int64  `json:"schedule_id"`
	Mode                          string `json:"mode"`
	Enabled                       bool   `json:"enabled"`
	StartAtUTC                    string `json:"start_at_utc"`
	EndAtUTC                      string `json:"end_at_utc"`
	LocalWeekday                  int    `json:"local_weekday"`
	LocalStartMinuteOfDay         int    `json:"local_start_minute_of_day"`
	LocalEndMinuteOfDay           int    `json:"local_end_minute_of_day"`
	TimezoneNameSnapshot          string `json:"timezone_name_snapshot"`
	TimezoneOffsetSnapshotMinutes int    `json:"timezone_offset_snapshot_minutes"`
	Status                        string `json:"status"`
	DisplayLabel                  string `json:"display_label"`
	UpdatedAt                     string `json:"updated_at"`
}

type studyModeDecision struct {
	Enabled        bool
	Source         string
	TeacherUserID  int64
	TeacherName    string
	ControlPinHash string
	ScheduleID     int64
	ScheduleLabel  string
}

type scheduleCandidate struct {
	ID                            int64
	TeacherUserID                 int64
	TeacherName                   string
	ControlPinHash                string
	Mode                          string
	Enabled                       bool
	StartAtUTC                    sql.NullTime
	EndAtUTC                      sql.NullTime
	LocalWeekday                  sql.NullInt64
	LocalStartMinuteOfDay         sql.NullInt64
	LocalEndMinuteOfDay           sql.NullInt64
	TimezoneNameSnapshot          sql.NullString
	TimezoneOffsetSnapshotMinutes int
	UpdatedAt                     time.Time
	Status                        string
}

func (h *StudyModeHandler) GetTeacherControlPinStatus(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	teacherAccountID, err := getTeacherAccountID(h.cfg.Store.DB, userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusForbidden, "teacher account required")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "teacher lookup failed")
	}
	row := h.cfg.Store.DB.QueryRow(
		`SELECT control_pin_hash
		 FROM teacher_accounts
		 WHERE id = ? LIMIT 1`,
		teacherAccountID,
	)
	var controlPinHash sql.NullString
	if err := row.Scan(&controlPinHash); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "teacher control pin lookup failed")
	}
	return c.JSON(fiber.Map{
		"configured": strings.TrimSpace(controlPinHash.String) != "",
	})
}

func (h *StudyModeHandler) UpsertTeacherControlPin(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	teacherAccountID, err := getTeacherAccountID(h.cfg.Store.DB, userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusForbidden, "teacher account required")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "teacher lookup failed")
	}
	var req updateTeacherControlPinRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	controlPin := strings.TrimSpace(req.ControlPin)
	if controlPin == "" {
		return fiber.NewError(fiber.StatusBadRequest, "control_pin required")
	}
	if _, err := h.cfg.Store.DB.Exec(
		`UPDATE teacher_accounts
		 SET control_pin_hash = ?
		 WHERE id = ?`,
		hashControlPin(controlPin),
		teacherAccountID,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "teacher control pin save failed")
	}
	return c.JSON(fiber.Map{
		"configured": true,
	})
}

func (h *StudyModeHandler) ListTeacherStudentDevices(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	teacherAccountID, err := getTeacherAccountID(h.cfg.Store.DB, userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusForbidden, "teacher account required")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "teacher lookup failed")
	}
	rows, err := h.cfg.Store.DB.Query(
		`SELECT DISTINCT u.id, u.username
		 FROM enrollments e
		 JOIN users u ON u.id = e.student_id
		 WHERE e.teacher_id = ? AND e.status = 'active'
		 ORDER BY u.username ASC`,
		teacherAccountID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "student device list failed")
	}
	defer rows.Close()

	type deviceSummary struct {
		DeviceKey                 string `json:"device_key"`
		DeviceName                string `json:"device_name"`
		Platform                  string `json:"platform"`
		TimezoneName              string `json:"timezone_name"`
		TimezoneOffsetMinutes     int    `json:"timezone_offset_minutes"`
		Online                    bool   `json:"online"`
		LastSeenAt                string `json:"last_seen_at"`
		CurrentStudyModeEnabled   bool   `json:"current_study_mode_enabled"`
		EffectiveStudyModeEnabled bool   `json:"effective_study_mode_enabled"`
		EffectiveSource           string `json:"effective_source"`
		EffectiveScheduleID       int64  `json:"effective_schedule_id"`
		EffectiveScheduleLabel    string `json:"effective_schedule_label"`
		ControllerTeacherUserID   int64  `json:"controller_teacher_user_id"`
		ControllerTeacherName     string `json:"controller_teacher_name"`
	}
	type studentSummary struct {
		StudentUserID         int64           `json:"student_user_id"`
		StudentUsername       string          `json:"student_username"`
		HasTeacherControlPin  bool            `json:"has_teacher_control_pin"`
		TeacherManualOverride *bool           `json:"teacher_manual_override"`
		Devices               []deviceSummary `json:"devices"`
	}

	nowUTC := time.Now().UTC()
	hasPin, pinErr := h.teacherHasControlPin(userID)
	if pinErr != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "teacher control pin lookup failed")
	}
	results := []studentSummary{}
	for rows.Next() {
		var (
			studentUserID   int64
			studentUsername string
		)
		if err := rows.Scan(&studentUserID, &studentUsername); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "student device list failed")
		}
		overrideEnabled, overridePresent, overrideErr := h.lookupTeacherManualOverride(
			userID,
			studentUserID,
		)
		if overrideErr != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "study mode override lookup failed")
		}
		deviceRows, deviceErr := h.cfg.Store.DB.Query(
			`SELECT device_key, device_name, platform,
			        timezone_name, timezone_offset_minutes,
			        local_weekday, local_minute_of_day,
			        current_study_mode_enabled, last_seen_at, auth_session_nonce
			 FROM app_user_devices
			 WHERE user_id = ?
			 ORDER BY COALESCE(last_seen_at, created_at) DESC, id DESC`,
			studentUserID,
		)
		if deviceErr != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "student device list failed")
		}
		devices := []deviceSummary{}
		for deviceRows.Next() {
			var (
				deviceKey               string
				deviceName              string
				platform                string
				timezoneName            sql.NullString
				timezoneOffsetMinutes   int
				localWeekday            int
				localMinuteOfDay        int
				currentStudyModeEnabled bool
				lastSeenAt              sql.NullTime
				authSessionNonce        sql.NullString
			)
			if err := deviceRows.Scan(
				&deviceKey,
				&deviceName,
				&platform,
				&timezoneName,
				&timezoneOffsetMinutes,
				&localWeekday,
				&localMinuteOfDay,
				&currentStudyModeEnabled,
				&lastSeenAt,
				&authSessionNonce,
			); err != nil {
				_ = deviceRows.Close()
				return fiber.NewError(fiber.StatusInternalServerError, "student device list failed")
			}
			decision, decisionErr := h.resolveEffectiveStudyModeForStudent(
				studentUserID,
				localWeekday,
				localMinuteOfDay,
				nowUTC,
			)
			if decisionErr != nil {
				_ = deviceRows.Close()
				return fiber.NewError(fiber.StatusInternalServerError, "study mode resolution failed")
			}
			lastSeen := ""
			online := false
			if lastSeenAt.Valid {
				lastSeen = lastSeenAt.Time.UTC().Format(time.RFC3339)
				online = strings.TrimSpace(authSessionNonce.String) != "" &&
					nowUTC.Sub(lastSeenAt.Time.UTC()) <= 90*time.Second
			}
			devices = append(devices, deviceSummary{
				DeviceKey:                 deviceKey,
				DeviceName:                deviceName,
				Platform:                  platform,
				TimezoneName:              timezoneName.String,
				TimezoneOffsetMinutes:     timezoneOffsetMinutes,
				Online:                    online,
				LastSeenAt:                lastSeen,
				CurrentStudyModeEnabled:   currentStudyModeEnabled,
				EffectiveStudyModeEnabled: decision.Enabled,
				EffectiveSource:           decision.Source,
				EffectiveScheduleID:       decision.ScheduleID,
				EffectiveScheduleLabel:    decision.ScheduleLabel,
				ControllerTeacherUserID:   decision.TeacherUserID,
				ControllerTeacherName:     decision.TeacherName,
			})
		}
		_ = deviceRows.Close()
		var overrideValue *bool
		if overridePresent {
			value := overrideEnabled
			overrideValue = &value
		}
		results = append(results, studentSummary{
			StudentUserID:         studentUserID,
			StudentUsername:       studentUsername,
			HasTeacherControlPin:  hasPin,
			TeacherManualOverride: overrideValue,
			Devices:               devices,
		})
	}
	return c.JSON(results)
}

func (h *StudyModeHandler) UpsertStudyModeOverride(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	teacherAccountID, err := getTeacherAccountID(h.cfg.Store.DB, userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusForbidden, "teacher account required")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "teacher lookup failed")
	}
	studentUserID, err := parseInt64Param(c, "studentUserId")
	if err != nil {
		return err
	}
	if ok, authErr := teacherCanControlStudent(h.cfg.Store.DB, teacherAccountID, studentUserID); authErr != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "enrollment lookup failed")
	} else if !ok {
		return fiber.NewError(fiber.StatusForbidden, "student enrollment required")
	}
	var req studyModeOverrideRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	if err := h.requireTeacherControlPin(userID, strings.TrimSpace(req.ControlPin)); err != nil {
		return err
	}
	if _, err := h.cfg.Store.DB.Exec(
		`INSERT INTO teacher_study_mode_overrides (
		   teacher_user_id,
		   student_user_id,
		   enabled
		 ) VALUES (?, ?, ?)
		 ON DUPLICATE KEY UPDATE
		   enabled = VALUES(enabled),
		   updated_at = CURRENT_TIMESTAMP`,
		userID,
		studentUserID,
		req.Enabled,
	); err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "study mode override save failed")
	}
	return c.JSON(fiber.Map{
		"status":  "ok",
		"enabled": req.Enabled,
	})
}

func (h *StudyModeHandler) ListStudyModeSchedules(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	teacherAccountID, err := getTeacherAccountID(h.cfg.Store.DB, userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusForbidden, "teacher account required")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "teacher lookup failed")
	}
	studentUserID, err := parseInt64Param(c, "studentUserId")
	if err != nil {
		return err
	}
	if ok, authErr := teacherCanControlStudent(h.cfg.Store.DB, teacherAccountID, studentUserID); authErr != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "enrollment lookup failed")
	} else if !ok {
		return fiber.NewError(fiber.StatusForbidden, "student enrollment required")
	}
	rows, err := h.cfg.Store.DB.Query(
		`SELECT id, mode, enabled, start_at_utc, end_at_utc,
		        local_weekday, local_start_minute_of_day, local_end_minute_of_day,
		        timezone_name_snapshot, timezone_offset_snapshot_minutes,
		        status, updated_at
		 FROM teacher_study_mode_schedules
		 WHERE teacher_user_id = ? AND student_user_id = ? AND status = 'active'
		 ORDER BY updated_at DESC, id DESC`,
		userID,
		studentUserID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "study mode schedule list failed")
	}
	defer rows.Close()
	results := []studyModeScheduleSummary{}
	for rows.Next() {
		var candidate scheduleCandidate
		if err := rows.Scan(
			&candidate.ID,
			&candidate.Mode,
			&candidate.Enabled,
			&candidate.StartAtUTC,
			&candidate.EndAtUTC,
			&candidate.LocalWeekday,
			&candidate.LocalStartMinuteOfDay,
			&candidate.LocalEndMinuteOfDay,
			&candidate.TimezoneNameSnapshot,
			&candidate.TimezoneOffsetSnapshotMinutes,
			&candidate.Status,
			&candidate.UpdatedAt,
		); err != nil {
			return fiber.NewError(fiber.StatusInternalServerError, "study mode schedule list failed")
		}
		results = append(results, buildScheduleSummary(candidate))
	}
	return c.JSON(results)
}

func (h *StudyModeHandler) CreateStudyModeSchedule(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	teacherAccountID, err := getTeacherAccountID(h.cfg.Store.DB, userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusForbidden, "teacher account required")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "teacher lookup failed")
	}
	studentUserID, err := parseInt64Param(c, "studentUserId")
	if err != nil {
		return err
	}
	if ok, authErr := teacherCanControlStudent(h.cfg.Store.DB, teacherAccountID, studentUserID); authErr != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "enrollment lookup failed")
	} else if !ok {
		return fiber.NewError(fiber.StatusForbidden, "student enrollment required")
	}
	var req createStudyModeScheduleRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	if err := h.requireTeacherControlPin(userID, strings.TrimSpace(req.ControlPin)); err != nil {
		return err
	}
	mode := strings.TrimSpace(strings.ToLower(req.Mode))
	if mode != "one_time" && mode != "weekly" {
		return fiber.NewError(fiber.StatusBadRequest, "mode invalid")
	}
	var (
		startAtUTC       sql.NullTime
		endAtUTC         sql.NullTime
		localWeekday     sql.NullInt64
		localStartMinute sql.NullInt64
		localEndMinute   sql.NullInt64
	)
	switch mode {
	case "one_time":
		start, parseStartErr := time.Parse(time.RFC3339, strings.TrimSpace(req.StartAtUTC))
		end, parseEndErr := time.Parse(time.RFC3339, strings.TrimSpace(req.EndAtUTC))
		if parseStartErr != nil || parseEndErr != nil {
			return fiber.NewError(fiber.StatusBadRequest, "start_at_utc and end_at_utc required")
		}
		if !start.Before(end) {
			return fiber.NewError(fiber.StatusBadRequest, "end_at_utc must be after start_at_utc")
		}
		startAtUTC = sql.NullTime{Time: start.UTC(), Valid: true}
		endAtUTC = sql.NullTime{Time: end.UTC(), Valid: true}
	case "weekly":
		if req.LocalWeekday < 1 || req.LocalWeekday > 7 {
			return fiber.NewError(fiber.StatusBadRequest, "local_weekday invalid")
		}
		if req.LocalStartMinuteOfDay < 0 || req.LocalStartMinuteOfDay > 1439 {
			return fiber.NewError(fiber.StatusBadRequest, "local_start_minute_of_day invalid")
		}
		if req.LocalEndMinuteOfDay < 0 || req.LocalEndMinuteOfDay > 1439 {
			return fiber.NewError(fiber.StatusBadRequest, "local_end_minute_of_day invalid")
		}
		if req.LocalStartMinuteOfDay == req.LocalEndMinuteOfDay {
			return fiber.NewError(fiber.StatusBadRequest, "weekly schedule window cannot be empty")
		}
		localWeekday = sql.NullInt64{Int64: int64(req.LocalWeekday), Valid: true}
		localStartMinute = sql.NullInt64{Int64: int64(req.LocalStartMinuteOfDay), Valid: true}
		localEndMinute = sql.NullInt64{Int64: int64(req.LocalEndMinuteOfDay), Valid: true}
	}
	result, err := h.cfg.Store.DB.Exec(
		`INSERT INTO teacher_study_mode_schedules (
		   teacher_user_id,
		   student_user_id,
		   mode,
		   enabled,
		   start_at_utc,
		   end_at_utc,
		   local_weekday,
		   local_start_minute_of_day,
		   local_end_minute_of_day,
		   timezone_name_snapshot,
		   timezone_offset_snapshot_minutes,
		   status
		 ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active')`,
		userID,
		studentUserID,
		mode,
		req.Enabled,
		startAtUTC,
		endAtUTC,
		localWeekday,
		localStartMinute,
		localEndMinute,
		nullableString(req.TimezoneNameSnapshot),
		req.TimezoneOffsetSnapshotMinutes,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "study mode schedule save failed")
	}
	scheduleID, _ := result.LastInsertId()
	return c.JSON(fiber.Map{
		"schedule_id": scheduleID,
		"status":      "active",
	})
}

func (h *StudyModeHandler) DeleteStudyModeSchedule(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	teacherAccountID, err := getTeacherAccountID(h.cfg.Store.DB, userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusForbidden, "teacher account required")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "teacher lookup failed")
	}
	studentUserID, err := parseInt64Param(c, "studentUserId")
	if err != nil {
		return err
	}
	if ok, authErr := teacherCanControlStudent(h.cfg.Store.DB, teacherAccountID, studentUserID); authErr != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "enrollment lookup failed")
	} else if !ok {
		return fiber.NewError(fiber.StatusForbidden, "student enrollment required")
	}
	scheduleID, err := parseInt64Param(c, "id")
	if err != nil {
		return err
	}
	var req deleteStudyModeScheduleRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	if err := h.requireTeacherControlPin(userID, strings.TrimSpace(req.ControlPin)); err != nil {
		return err
	}
	result, err := h.cfg.Store.DB.Exec(
		`UPDATE teacher_study_mode_schedules
		 SET status = 'deleted',
		     updated_at = CURRENT_TIMESTAMP
		 WHERE id = ? AND teacher_user_id = ? AND student_user_id = ?`,
		scheduleID,
		userID,
		studentUserID,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "study mode schedule delete failed")
	}
	affected, _ := result.RowsAffected()
	if affected <= 0 {
		return fiber.NewError(fiber.StatusNotFound, "schedule not found")
	}
	return c.JSON(fiber.Map{"status": "deleted"})
}

func (h *StudyModeHandler) HeartbeatStudentDevice(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	isTeacher, _, err := isTeacherAccount(h.cfg.Store.DB, userID)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "role lookup failed")
	}
	if isTeacher {
		return fiber.NewError(fiber.StatusForbidden, "student account required")
	}
	var req studentDeviceHeartbeatRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	req.DeviceKey = strings.TrimSpace(req.DeviceKey)
	if req.DeviceKey == "" {
		return fiber.NewError(fiber.StatusBadRequest, "device_key required")
	}
	tokenDeviceKey, _ := c.Locals(AuthLocalDeviceKeyKey).(string)
	if strings.TrimSpace(tokenDeviceKey) == "" {
		return fiber.NewError(fiber.StatusUnauthorized, "device session required")
	}
	if strings.TrimSpace(tokenDeviceKey) != req.DeviceKey {
		return fiber.NewError(fiber.StatusUnauthorized, "device mismatch")
	}
	if req.LocalWeekday < 1 || req.LocalWeekday > 7 {
		return fiber.NewError(fiber.StatusBadRequest, "local_weekday invalid")
	}
	if req.LocalMinuteOfDay < 0 || req.LocalMinuteOfDay > 1439 {
		return fiber.NewError(fiber.StatusBadRequest, "local_minute_of_day invalid")
	}
	result, err := h.cfg.Store.DB.Exec(
		`UPDATE app_user_devices
		 SET device_name = ?,
		     platform = ?,
		     timezone_name = ?,
		     timezone_offset_minutes = ?,
		     local_weekday = ?,
		     local_minute_of_day = ?,
		     current_study_mode_enabled = ?,
		     app_version = ?,
		     last_seen_at = ?
		 WHERE user_id = ? AND device_key = ?`,
		strings.TrimSpace(req.DeviceName),
		strings.TrimSpace(strings.ToLower(req.Platform)),
		nullableString(req.TimezoneName),
		req.TimezoneOffsetMinutes,
		req.LocalWeekday,
		req.LocalMinuteOfDay,
		req.CurrentStudyModeEnabled,
		nullableString(req.AppVersion),
		time.Now().UTC(),
		userID,
		req.DeviceKey,
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "device heartbeat failed")
	}
	affected, rowsErr := result.RowsAffected()
	if rowsErr != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "device heartbeat failed")
	}
	if affected <= 0 {
		return fiber.NewError(fiber.StatusConflict, "device not registered")
	}
	decision, err := h.resolveEffectiveStudyModeForStudent(
		userID,
		req.LocalWeekday,
		req.LocalMinuteOfDay,
		time.Now().UTC(),
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "study mode resolution failed")
	}
	return c.JSON(fiber.Map{
		"effective_enabled":          decision.Enabled,
		"effective_source":           decision.Source,
		"controller_teacher_user_id": decision.TeacherUserID,
		"controller_teacher_name":    decision.TeacherName,
		"active_schedule_id":         decision.ScheduleID,
		"active_schedule_label":      decision.ScheduleLabel,
	})
}

func (h *StudyModeHandler) VerifyStudentStudyModeControlPin(c *fiber.Ctx) error {
	userID, err := requireUserID(c, h.cfg.Config.JWTVerifySecrets)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, "unauthorized")
	}
	var req verifyStudentStudyModeControlPinRequest
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid request body")
	}
	if strings.TrimSpace(req.ControlPin) == "" {
		return fiber.NewError(fiber.StatusBadRequest, "control_pin required")
	}
	if req.LocalWeekday < 1 || req.LocalWeekday > 7 {
		return fiber.NewError(fiber.StatusBadRequest, "local_weekday invalid")
	}
	if req.LocalMinuteOfDay < 0 || req.LocalMinuteOfDay > 1439 {
		return fiber.NewError(fiber.StatusBadRequest, "local_minute_of_day invalid")
	}
	decision, err := h.resolveEffectiveStudyModeForStudent(
		userID,
		req.LocalWeekday,
		req.LocalMinuteOfDay,
		time.Now().UTC(),
	)
	if err != nil {
		return fiber.NewError(fiber.StatusInternalServerError, "study mode resolution failed")
	}
	if !decision.Enabled || strings.TrimSpace(strings.ToLower(decision.Source)) == "default" {
		return fiber.NewError(fiber.StatusConflict, "teacher enforced study mode inactive")
	}
	expected := strings.TrimSpace(decision.ControlPinHash)
	if expected == "" {
		return fiber.NewError(fiber.StatusInternalServerError, "teacher control pin missing for active study mode")
	}
	if hashControlPin(req.ControlPin) != expected {
		return fiber.NewError(fiber.StatusForbidden, "invalid control pin")
	}
	return c.JSON(fiber.Map{
		"verified":                   true,
		"effective_source":           decision.Source,
		"controller_teacher_user_id": decision.TeacherUserID,
		"controller_teacher_name":    decision.TeacherName,
		"active_schedule_id":         decision.ScheduleID,
		"active_schedule_label":      decision.ScheduleLabel,
	})
}

func (h *StudyModeHandler) requireTeacherControlPin(
	teacherUserID int64,
	controlPin string,
) error {
	if strings.TrimSpace(controlPin) == "" {
		return fiber.NewError(fiber.StatusBadRequest, "control_pin required")
	}
	row := h.cfg.Store.DB.QueryRow(
		`SELECT control_pin_hash
		 FROM teacher_accounts
		 WHERE user_id = ? LIMIT 1`,
		teacherUserID,
	)
	var controlPinHash sql.NullString
	if err := row.Scan(&controlPinHash); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return fiber.NewError(fiber.StatusForbidden, "teacher account required")
		}
		return fiber.NewError(fiber.StatusInternalServerError, "teacher control pin lookup failed")
	}
	expected := strings.TrimSpace(controlPinHash.String)
	if expected == "" {
		return fiber.NewError(fiber.StatusConflict, "teacher control pin not configured")
	}
	if hashControlPin(controlPin) != expected {
		return fiber.NewError(fiber.StatusForbidden, "invalid control pin")
	}
	return nil
}

func (h *StudyModeHandler) teacherHasControlPin(
	teacherUserID int64,
) (bool, error) {
	row := h.cfg.Store.DB.QueryRow(
		`SELECT control_pin_hash
		 FROM teacher_accounts
		 WHERE user_id = ? LIMIT 1`,
		teacherUserID,
	)
	var controlPinHash sql.NullString
	if err := row.Scan(&controlPinHash); err != nil {
		return false, err
	}
	return strings.TrimSpace(controlPinHash.String) != "", nil
}

func (h *StudyModeHandler) lookupTeacherManualOverride(
	teacherUserID int64,
	studentUserID int64,
) (bool, bool, error) {
	row := h.cfg.Store.DB.QueryRow(
		`SELECT enabled
		 FROM teacher_study_mode_overrides
		 WHERE teacher_user_id = ? AND student_user_id = ?
		 LIMIT 1`,
		teacherUserID,
		studentUserID,
	)
	var enabled bool
	if err := row.Scan(&enabled); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return false, false, nil
		}
		return false, false, err
	}
	return enabled, true, nil
}

func (h *StudyModeHandler) resolveEffectiveStudyModeForStudent(
	studentUserID int64,
	localWeekday int,
	localMinuteOfDay int,
	nowUTC time.Time,
) (studyModeDecision, error) {
	schedules, err := h.listScheduleCandidates(studentUserID)
	if err != nil {
		return studyModeDecision{}, err
	}
	for _, candidate := range schedules {
		if scheduleCandidateMatches(candidate, localWeekday, localMinuteOfDay, nowUTC) {
			return studyModeDecision{
				Enabled:        candidate.Enabled,
				Source:         "schedule",
				TeacherUserID:  candidate.TeacherUserID,
				TeacherName:    candidate.TeacherName,
				ControlPinHash: candidate.ControlPinHash,
				ScheduleID:     candidate.ID,
				ScheduleLabel:  formatScheduleLabel(candidate),
			}, nil
		}
	}
	overrideRow := h.cfg.Store.DB.QueryRow(
		`SELECT o.teacher_user_id, u.username, ta.control_pin_hash, o.enabled
		 FROM teacher_study_mode_overrides o
		 JOIN users u ON u.id = o.teacher_user_id
		 JOIN teacher_accounts ta ON ta.user_id = o.teacher_user_id
		 WHERE o.student_user_id = ?
		   AND EXISTS (
		     SELECT 1
		     FROM enrollments e
		     WHERE e.student_id = o.student_user_id
		       AND e.status = 'active'
		       AND e.teacher_id = ta.id
		   )
		 ORDER BY o.updated_at DESC, o.id DESC
		 LIMIT 1`,
		studentUserID,
	)
	var (
		teacherUserID  int64
		teacherName    string
		controlPinHash sql.NullString
		enabled        bool
	)
	if err := overrideRow.Scan(&teacherUserID, &teacherName, &controlPinHash, &enabled); err == nil {
		return studyModeDecision{
			Enabled:        enabled,
			Source:         "manual",
			TeacherUserID:  teacherUserID,
			TeacherName:    teacherName,
			ControlPinHash: strings.TrimSpace(controlPinHash.String),
		}, nil
	} else if !errors.Is(err, sql.ErrNoRows) {
		return studyModeDecision{}, err
	}
	return studyModeDecision{
		Enabled: false,
		Source:  "default",
	}, nil
}

func (h *StudyModeHandler) listScheduleCandidates(
	studentUserID int64,
) ([]scheduleCandidate, error) {
	rows, err := h.cfg.Store.DB.Query(
		`SELECT s.id, s.teacher_user_id, u.username,
		        ta.control_pin_hash,
		        s.mode, s.enabled, s.start_at_utc, s.end_at_utc,
		        s.local_weekday, s.local_start_minute_of_day, s.local_end_minute_of_day,
		        s.timezone_name_snapshot, s.timezone_offset_snapshot_minutes,
		        s.updated_at, s.status
		 FROM teacher_study_mode_schedules s
		 JOIN users u ON u.id = s.teacher_user_id
		 JOIN teacher_accounts ta ON ta.user_id = s.teacher_user_id
		 WHERE s.student_user_id = ?
		   AND s.status = 'active'
		   AND EXISTS (
		     SELECT 1
		     FROM enrollments e
		     WHERE e.student_id = s.student_user_id
		       AND e.status = 'active'
		       AND e.teacher_id = ta.id
		   )
		 ORDER BY s.updated_at DESC, s.id DESC`,
		studentUserID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	results := []scheduleCandidate{}
	for rows.Next() {
		var candidate scheduleCandidate
		if err := rows.Scan(
			&candidate.ID,
			&candidate.TeacherUserID,
			&candidate.TeacherName,
			&candidate.ControlPinHash,
			&candidate.Mode,
			&candidate.Enabled,
			&candidate.StartAtUTC,
			&candidate.EndAtUTC,
			&candidate.LocalWeekday,
			&candidate.LocalStartMinuteOfDay,
			&candidate.LocalEndMinuteOfDay,
			&candidate.TimezoneNameSnapshot,
			&candidate.TimezoneOffsetSnapshotMinutes,
			&candidate.UpdatedAt,
			&candidate.Status,
		); err != nil {
			return nil, err
		}
		results = append(results, candidate)
	}
	return results, nil
}

func teacherCanControlStudent(
	db *sql.DB,
	teacherAccountID int64,
	studentUserID int64,
) (bool, error) {
	row := db.QueryRow(
		`SELECT 1
		 FROM enrollments
		 WHERE teacher_id = ? AND student_id = ? AND status = 'active'
		 LIMIT 1`,
		teacherAccountID,
		studentUserID,
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

func scheduleCandidateMatches(
	candidate scheduleCandidate,
	localWeekday int,
	localMinuteOfDay int,
	nowUTC time.Time,
) bool {
	switch strings.TrimSpace(strings.ToLower(candidate.Mode)) {
	case "one_time":
		if !candidate.StartAtUTC.Valid || !candidate.EndAtUTC.Valid {
			return false
		}
		return !nowUTC.Before(candidate.StartAtUTC.Time.UTC()) &&
			nowUTC.Before(candidate.EndAtUTC.Time.UTC())
	case "weekly":
		if !candidate.LocalWeekday.Valid ||
			!candidate.LocalStartMinuteOfDay.Valid ||
			!candidate.LocalEndMinuteOfDay.Valid {
			return false
		}
		startMinute := int(candidate.LocalStartMinuteOfDay.Int64)
		endMinute := int(candidate.LocalEndMinuteOfDay.Int64)
		weekday := int(candidate.LocalWeekday.Int64)
		if startMinute < endMinute {
			return localWeekday == weekday &&
				localMinuteOfDay >= startMinute &&
				localMinuteOfDay < endMinute
		}
		nextWeekday := weekday + 1
		if nextWeekday > 7 {
			nextWeekday = 1
		}
		return (localWeekday == weekday && localMinuteOfDay >= startMinute) ||
			(localWeekday == nextWeekday && localMinuteOfDay < endMinute)
	default:
		return false
	}
}

func buildScheduleSummary(candidate scheduleCandidate) studyModeScheduleSummary {
	startAtUTC := ""
	if candidate.StartAtUTC.Valid {
		startAtUTC = candidate.StartAtUTC.Time.UTC().Format(time.RFC3339)
	}
	endAtUTC := ""
	if candidate.EndAtUTC.Valid {
		endAtUTC = candidate.EndAtUTC.Time.UTC().Format(time.RFC3339)
	}
	localWeekday := 0
	if candidate.LocalWeekday.Valid {
		localWeekday = int(candidate.LocalWeekday.Int64)
	}
	localStartMinute := 0
	if candidate.LocalStartMinuteOfDay.Valid {
		localStartMinute = int(candidate.LocalStartMinuteOfDay.Int64)
	}
	localEndMinute := 0
	if candidate.LocalEndMinuteOfDay.Valid {
		localEndMinute = int(candidate.LocalEndMinuteOfDay.Int64)
	}
	return studyModeScheduleSummary{
		ScheduleID:                    candidate.ID,
		Mode:                          candidate.Mode,
		Enabled:                       candidate.Enabled,
		StartAtUTC:                    startAtUTC,
		EndAtUTC:                      endAtUTC,
		LocalWeekday:                  localWeekday,
		LocalStartMinuteOfDay:         localStartMinute,
		LocalEndMinuteOfDay:           localEndMinute,
		TimezoneNameSnapshot:          candidate.TimezoneNameSnapshot.String,
		TimezoneOffsetSnapshotMinutes: candidate.TimezoneOffsetSnapshotMinutes,
		Status:                        candidate.Status,
		DisplayLabel:                  formatScheduleLabel(candidate),
		UpdatedAt:                     candidate.UpdatedAt.UTC().Format(time.RFC3339),
	}
}

func formatScheduleLabel(candidate scheduleCandidate) string {
	prefix := "Turn off"
	if candidate.Enabled {
		prefix = "Turn on"
	}
	switch strings.TrimSpace(strings.ToLower(candidate.Mode)) {
	case "one_time":
		start := ""
		end := ""
		if candidate.StartAtUTC.Valid {
			start = candidate.StartAtUTC.Time.UTC().Format(time.RFC3339)
		}
		if candidate.EndAtUTC.Valid {
			end = candidate.EndAtUTC.Time.UTC().Format(time.RFC3339)
		}
		return fmt.Sprintf("%s once (%s to %s UTC)", prefix, start, end)
	case "weekly":
		weekday := weekdayLabel(int(candidate.LocalWeekday.Int64))
		start := minuteOfDayLabel(int(candidate.LocalStartMinuteOfDay.Int64))
		end := minuteOfDayLabel(int(candidate.LocalEndMinuteOfDay.Int64))
		return fmt.Sprintf("%s weekly (%s %s-%s)", prefix, weekday, start, end)
	default:
		return prefix
	}
}

func weekdayLabel(weekday int) string {
	switch weekday {
	case 1:
		return "Mon"
	case 2:
		return "Tue"
	case 3:
		return "Wed"
	case 4:
		return "Thu"
	case 5:
		return "Fri"
	case 6:
		return "Sat"
	case 7:
		return "Sun"
	default:
		return "Day"
	}
}

func minuteOfDayLabel(value int) string {
	if value < 0 {
		value = 0
	}
	hour := value / 60
	minute := value % 60
	return fmt.Sprintf("%02d:%02d", hour, minute)
}

func hashControlPin(value string) string {
	sum := sha256.Sum256([]byte(strings.TrimSpace(value)))
	return hex.EncodeToString(sum[:])
}
