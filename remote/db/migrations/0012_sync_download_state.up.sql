CREATE TABLE sync_download_state_items (
  user_id BIGINT NOT NULL,
  item_kind VARCHAR(32) NOT NULL,
  scope_key VARCHAR(255) NOT NULL,
  course_id BIGINT NOT NULL,
  student_user_id BIGINT NOT NULL,
  updated_at DATETIME NOT NULL,
  content_hash VARCHAR(128) NOT NULL,
  PRIMARY KEY (user_id, item_kind, scope_key),
  INDEX idx_sync_download_state_items_user (user_id, item_kind, updated_at, scope_key),
  INDEX idx_sync_download_state_items_course_student (course_id, student_user_id, user_id)
);

CREATE TABLE sync_download_state2 (
  user_id BIGINT NOT NULL,
  state2 VARCHAR(191) NOT NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id)
);
