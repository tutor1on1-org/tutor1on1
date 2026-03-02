CREATE TABLE progress_sync_audit (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  course_id BIGINT NOT NULL,
  student_user_id BIGINT NOT NULL,
  teacher_user_id BIGINT NOT NULL,
  kp_key VARCHAR(128) NOT NULL,
  actor_user_id BIGINT NOT NULL,
  device_id VARCHAR(128) NULL,
  action VARCHAR(32) NOT NULL,
  old_lit_percent INT NULL,
  new_lit_percent INT NOT NULL,
  old_question_level VARCHAR(32) NULL,
  new_question_level VARCHAR(32) NULL,
  old_updated_at DATETIME NULL,
  new_updated_at DATETIME NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_progress_sync_audit_scope (student_user_id, course_id, kp_key, created_at),
  INDEX idx_progress_sync_audit_actor (actor_user_id, created_at),
  CONSTRAINT fk_progress_sync_audit_course
    FOREIGN KEY (course_id) REFERENCES courses(id),
  CONSTRAINT fk_progress_sync_audit_student_user
    FOREIGN KEY (student_user_id) REFERENCES users(id),
  CONSTRAINT fk_progress_sync_audit_teacher_user
    FOREIGN KEY (teacher_user_id) REFERENCES users(id),
  CONSTRAINT fk_progress_sync_audit_actor_user
    FOREIGN KEY (actor_user_id) REFERENCES users(id)
);
