CREATE TABLE course_quit_requests (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  student_id BIGINT NOT NULL,
  teacher_id BIGINT NOT NULL,
  course_id BIGINT NOT NULL,
  reason TEXT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'pending',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  resolved_at DATETIME NULL,
  INDEX idx_course_quit_student (student_id, created_at),
  INDEX idx_course_quit_teacher_status (teacher_id, status, created_at),
  CONSTRAINT fk_course_quit_student
    FOREIGN KEY (student_id) REFERENCES users(id),
  CONSTRAINT fk_course_quit_teacher
    FOREIGN KEY (teacher_id) REFERENCES teacher_accounts(id),
  CONSTRAINT fk_course_quit_course
    FOREIGN KEY (course_id) REFERENCES courses(id)
);

CREATE TABLE enrollment_deletion_events (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  student_id BIGINT NOT NULL,
  teacher_user_id BIGINT NOT NULL,
  course_id BIGINT NOT NULL,
  reason VARCHAR(32) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_enrollment_delete_student (student_id, id),
  INDEX idx_enrollment_delete_teacher (teacher_user_id, id),
  CONSTRAINT fk_enrollment_delete_student
    FOREIGN KEY (student_id) REFERENCES users(id),
  CONSTRAINT fk_enrollment_delete_teacher_user
    FOREIGN KEY (teacher_user_id) REFERENCES users(id),
  CONSTRAINT fk_enrollment_delete_course
    FOREIGN KEY (course_id) REFERENCES courses(id)
);

CREATE TABLE progress_sync (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  course_id BIGINT NOT NULL,
  teacher_user_id BIGINT NOT NULL,
  student_user_id BIGINT NOT NULL,
  kp_key VARCHAR(128) NOT NULL,
  lit BOOLEAN NOT NULL DEFAULT FALSE,
  lit_percent INT NOT NULL DEFAULT 0,
  question_level VARCHAR(32) NULL,
  summary_text TEXT NULL,
  summary_raw_response MEDIUMTEXT NULL,
  summary_valid BOOLEAN NULL,
  updated_at DATETIME NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_progress_sync (course_id, student_user_id, kp_key),
  INDEX idx_progress_sync_student (student_user_id, updated_at),
  INDEX idx_progress_sync_teacher (teacher_user_id, updated_at),
  CONSTRAINT fk_progress_sync_course
    FOREIGN KEY (course_id) REFERENCES courses(id),
  CONSTRAINT fk_progress_sync_teacher_user
    FOREIGN KEY (teacher_user_id) REFERENCES users(id),
  CONSTRAINT fk_progress_sync_student_user
    FOREIGN KEY (student_user_id) REFERENCES users(id)
);
