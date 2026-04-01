CREATE TABLE student_kp_artifacts (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  artifact_id VARCHAR(255) NOT NULL UNIQUE,
  course_id BIGINT NOT NULL,
  teacher_user_id BIGINT NOT NULL,
  student_user_id BIGINT NOT NULL,
  kp_key VARCHAR(128) NOT NULL,
  storage_rel_path VARCHAR(512) NOT NULL,
  sha256 VARCHAR(64) NOT NULL,
  last_modified DATETIME NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_student_kp_artifacts_scope (course_id, student_user_id, kp_key),
  INDEX idx_student_kp_artifacts_teacher (teacher_user_id, course_id, student_user_id),
  INDEX idx_student_kp_artifacts_student (student_user_id, course_id, kp_key),
  CONSTRAINT fk_student_kp_artifacts_course
    FOREIGN KEY (course_id) REFERENCES courses(id),
  CONSTRAINT fk_student_kp_artifacts_teacher_user
    FOREIGN KEY (teacher_user_id) REFERENCES users(id),
  CONSTRAINT fk_student_kp_artifacts_student_user
    FOREIGN KEY (student_user_id) REFERENCES users(id)
);

CREATE TABLE artifact_state1_items (
  user_id BIGINT NOT NULL,
  artifact_id VARCHAR(255) NOT NULL,
  artifact_class VARCHAR(32) NOT NULL,
  course_id BIGINT NOT NULL,
  teacher_user_id BIGINT NOT NULL,
  student_user_id BIGINT NULL,
  kp_key VARCHAR(128) NULL,
  bundle_version_id BIGINT NULL,
  storage_rel_path VARCHAR(512) NOT NULL,
  sha256 VARCHAR(64) NOT NULL,
  last_modified DATETIME NOT NULL,
  PRIMARY KEY (user_id, artifact_id),
  INDEX idx_artifact_state1_user (user_id, artifact_class, artifact_id),
  CONSTRAINT fk_artifact_state1_user
    FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT fk_artifact_state1_course
    FOREIGN KEY (course_id) REFERENCES courses(id),
  CONSTRAINT fk_artifact_state1_teacher_user
    FOREIGN KEY (teacher_user_id) REFERENCES users(id),
  CONSTRAINT fk_artifact_state1_student_user
    FOREIGN KEY (student_user_id) REFERENCES users(id),
  CONSTRAINT fk_artifact_state1_bundle_version
    FOREIGN KEY (bundle_version_id) REFERENCES bundle_versions(id)
);

CREATE TABLE artifact_state2 (
  user_id BIGINT PRIMARY KEY,
  state2 VARCHAR(191) NOT NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_artifact_state2_user
    FOREIGN KEY (user_id) REFERENCES users(id)
);
