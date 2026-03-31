CREATE TABLE teacher_course_sync_state1_items (
  user_id BIGINT NOT NULL,
  course_id BIGINT NOT NULL,
  subject VARCHAR(255) NOT NULL,
  latest_bundle_version_id BIGINT NOT NULL DEFAULT 0,
  latest_bundle_hash VARCHAR(191) NOT NULL DEFAULT '',
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, course_id),
  KEY idx_teacher_course_sync_state1_items_user_id (user_id)
);

CREATE TABLE student_enrollment_sync_state1_items (
  user_id BIGINT NOT NULL,
  course_id BIGINT NOT NULL,
  teacher_user_id BIGINT NOT NULL,
  teacher_name VARCHAR(255) NOT NULL,
  course_subject VARCHAR(255) NOT NULL,
  latest_bundle_version_id BIGINT NOT NULL DEFAULT 0,
  latest_bundle_hash VARCHAR(191) NOT NULL DEFAULT '',
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, course_id),
  KEY idx_student_enrollment_sync_state1_items_user_id (user_id)
);
