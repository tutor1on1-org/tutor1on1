CREATE TABLE users (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  email VARCHAR(255) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  status VARCHAR(32) NOT NULL DEFAULT 'active',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE refresh_tokens (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  user_id BIGINT NOT NULL,
  token_hash VARCHAR(128) NOT NULL UNIQUE,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at DATETIME NOT NULL,
  revoked_at DATETIME NULL,
  CONSTRAINT fk_refresh_tokens_user
    FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE devices (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  user_id BIGINT NOT NULL,
  device_key VARCHAR(64) NOT NULL,
  public_key TEXT NOT NULL,
  status VARCHAR(32) NOT NULL DEFAULT 'active',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_seen_at DATETIME NULL,
  UNIQUE KEY uq_devices_user_device (user_id, device_key),
  CONSTRAINT fk_devices_user
    FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE teacher_accounts (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  user_id BIGINT NOT NULL UNIQUE,
  display_name VARCHAR(128) NOT NULL,
  bio TEXT NULL,
  avatar_url VARCHAR(512) NULL,
  contact TEXT NULL,
  contact_published BOOLEAN NOT NULL DEFAULT FALSE,
  status VARCHAR(32) NOT NULL DEFAULT 'active',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_teacher_accounts_user
    FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE courses (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  teacher_id BIGINT NOT NULL,
  subject VARCHAR(128) NOT NULL,
  grade VARCHAR(64) NULL,
  description TEXT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_courses_teacher
    FOREIGN KEY (teacher_id) REFERENCES teacher_accounts(id)
);

CREATE TABLE course_catalog_entries (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  course_id BIGINT NOT NULL,
  teacher_id BIGINT NOT NULL,
  visibility VARCHAR(16) NOT NULL DEFAULT 'private',
  published_at DATETIME NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_catalog_course
    FOREIGN KEY (course_id) REFERENCES courses(id),
  CONSTRAINT fk_catalog_teacher
    FOREIGN KEY (teacher_id) REFERENCES teacher_accounts(id)
);

CREATE TABLE bundles (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  course_id BIGINT NOT NULL,
  teacher_id BIGINT NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_bundles_course
    FOREIGN KEY (course_id) REFERENCES courses(id),
  CONSTRAINT fk_bundles_teacher
    FOREIGN KEY (teacher_id) REFERENCES teacher_accounts(id)
);

CREATE TABLE bundle_versions (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  bundle_id BIGINT NOT NULL,
  version INT NOT NULL,
  hash VARCHAR(128) NOT NULL,
  oss_path VARCHAR(512) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_bundle_versions (bundle_id, version),
  CONSTRAINT fk_bundle_versions_bundle
    FOREIGN KEY (bundle_id) REFERENCES bundles(id)
);

CREATE TABLE enrollment_requests (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  student_id BIGINT NOT NULL,
  teacher_id BIGINT NOT NULL,
  course_id BIGINT NOT NULL,
  message TEXT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'pending',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  resolved_at DATETIME NULL,
  CONSTRAINT fk_enrollment_requests_student
    FOREIGN KEY (student_id) REFERENCES users(id),
  CONSTRAINT fk_enrollment_requests_teacher
    FOREIGN KEY (teacher_id) REFERENCES teacher_accounts(id),
  CONSTRAINT fk_enrollment_requests_course
    FOREIGN KEY (course_id) REFERENCES courses(id)
);

CREATE TABLE enrollments (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  student_id BIGINT NOT NULL,
  teacher_id BIGINT NOT NULL,
  course_id BIGINT NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'active',
  assigned_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_enrollments_student
    FOREIGN KEY (student_id) REFERENCES users(id),
  CONSTRAINT fk_enrollments_teacher
    FOREIGN KEY (teacher_id) REFERENCES teacher_accounts(id),
  CONSTRAINT fk_enrollments_course
    FOREIGN KEY (course_id) REFERENCES courses(id)
);

CREATE TABLE marketplace_reports (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  reporter_user_id BIGINT NOT NULL,
  teacher_id BIGINT NULL,
  course_id BIGINT NULL,
  reason TEXT NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'open',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  resolved_at DATETIME NULL,
  CONSTRAINT fk_marketplace_reports_reporter
    FOREIGN KEY (reporter_user_id) REFERENCES users(id),
  CONSTRAINT fk_marketplace_reports_teacher
    FOREIGN KEY (teacher_id) REFERENCES teacher_accounts(id),
  CONSTRAINT fk_marketplace_reports_course
    FOREIGN KEY (course_id) REFERENCES courses(id)
);

CREATE TABLE e2ee_events (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  event_id VARCHAR(64) NOT NULL UNIQUE,
  event_type VARCHAR(16) NOT NULL,
  course_id BIGINT NOT NULL,
  conversation_id VARCHAR(64) NOT NULL,
  sender_user_id BIGINT NOT NULL,
  sender_device_id BIGINT NOT NULL,
  recipient_user_id BIGINT NOT NULL,
  seq BIGINT NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  payload_size INT NOT NULL,
  ciphertext MEDIUMBLOB NOT NULL,
  cipher_hash VARCHAR(128) NULL,
  INDEX idx_events_recipient_seq (recipient_user_id, seq),
  CONSTRAINT fk_events_course
    FOREIGN KEY (course_id) REFERENCES courses(id),
  CONSTRAINT fk_events_sender_user
    FOREIGN KEY (sender_user_id) REFERENCES users(id),
  CONSTRAINT fk_events_sender_device
    FOREIGN KEY (sender_device_id) REFERENCES devices(id),
  CONSTRAINT fk_events_recipient
    FOREIGN KEY (recipient_user_id) REFERENCES users(id)
);

CREATE TABLE ack_state (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  recipient_user_id BIGINT NOT NULL,
  sender_device_id BIGINT NOT NULL,
  ack_seq BIGINT NOT NULL DEFAULT 0,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_ack_state (recipient_user_id, sender_device_id),
  CONSTRAINT fk_ack_state_recipient
    FOREIGN KEY (recipient_user_id) REFERENCES users(id),
  CONSTRAINT fk_ack_state_sender_device
    FOREIGN KEY (sender_device_id) REFERENCES devices(id)
);

CREATE TABLE offline_queue (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  recipient_user_id BIGINT NOT NULL,
  sender_user_id BIGINT NOT NULL,
  sender_device_id BIGINT NOT NULL,
  event_id VARCHAR(64) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at DATETIME NOT NULL,
  payload_size INT NOT NULL,
  ciphertext MEDIUMBLOB NOT NULL,
  INDEX idx_offline_queue_recipient (recipient_user_id, created_at),
  CONSTRAINT fk_offline_queue_recipient
    FOREIGN KEY (recipient_user_id) REFERENCES users(id),
  CONSTRAINT fk_offline_queue_sender
    FOREIGN KEY (sender_user_id) REFERENCES users(id),
  CONSTRAINT fk_offline_queue_device
    FOREIGN KEY (sender_device_id) REFERENCES devices(id)
);
