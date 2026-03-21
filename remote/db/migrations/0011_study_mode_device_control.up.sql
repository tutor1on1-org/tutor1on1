ALTER TABLE teacher_accounts
  ADD COLUMN control_pin_hash VARCHAR(128) NULL AFTER status;

ALTER TABLE refresh_tokens
  ADD COLUMN device_key VARCHAR(128) NULL AFTER user_id,
  ADD COLUMN device_session_nonce VARCHAR(64) NULL AFTER device_key;

CREATE TABLE app_user_devices (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  user_id BIGINT NOT NULL,
  device_key VARCHAR(128) NOT NULL,
  device_name VARCHAR(255) NOT NULL,
  platform VARCHAR(64) NOT NULL,
  timezone_name VARCHAR(128) NULL,
  timezone_offset_minutes INT NOT NULL DEFAULT 0,
  local_weekday TINYINT NOT NULL DEFAULT 1,
  local_minute_of_day INT NOT NULL DEFAULT 0,
  current_study_mode_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  app_version VARCHAR(64) NULL,
  auth_session_nonce VARCHAR(64) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  last_seen_at DATETIME NULL,
  UNIQUE KEY uq_app_user_devices_user_device (user_id, device_key),
  INDEX idx_app_user_devices_user_seen (user_id, last_seen_at),
  CONSTRAINT fk_app_user_devices_user
    FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE teacher_study_mode_overrides (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  teacher_user_id BIGINT NOT NULL,
  student_user_id BIGINT NOT NULL,
  enabled BOOLEAN NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_teacher_study_mode_overrides (teacher_user_id, student_user_id),
  INDEX idx_teacher_study_mode_overrides_student_updated (student_user_id, updated_at),
  CONSTRAINT fk_teacher_study_mode_overrides_teacher
    FOREIGN KEY (teacher_user_id) REFERENCES users(id),
  CONSTRAINT fk_teacher_study_mode_overrides_student
    FOREIGN KEY (student_user_id) REFERENCES users(id)
);

CREATE TABLE teacher_study_mode_schedules (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  teacher_user_id BIGINT NOT NULL,
  student_user_id BIGINT NOT NULL,
  mode VARCHAR(16) NOT NULL,
  enabled BOOLEAN NOT NULL,
  start_at_utc DATETIME NULL,
  end_at_utc DATETIME NULL,
  local_weekday TINYINT NULL,
  local_start_minute_of_day INT NULL,
  local_end_minute_of_day INT NULL,
  timezone_name_snapshot VARCHAR(128) NULL,
  timezone_offset_snapshot_minutes INT NOT NULL DEFAULT 0,
  status VARCHAR(16) NOT NULL DEFAULT 'active',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_teacher_study_mode_schedules_student_status (student_user_id, status, updated_at),
  INDEX idx_teacher_study_mode_schedules_teacher_student (teacher_user_id, student_user_id, status),
  CONSTRAINT fk_teacher_study_mode_schedules_teacher
    FOREIGN KEY (teacher_user_id) REFERENCES users(id),
  CONSTRAINT fk_teacher_study_mode_schedules_student
    FOREIGN KEY (student_user_id) REFERENCES users(id)
);
