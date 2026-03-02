CREATE TABLE progress_sync_chunks (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  course_id BIGINT NOT NULL,
  teacher_user_id BIGINT NOT NULL,
  student_user_id BIGINT NOT NULL,
  chapter_key VARCHAR(64) NOT NULL,
  item_count INT NOT NULL DEFAULT 0,
  updated_at DATETIME NOT NULL,
  envelope MEDIUMBLOB NOT NULL,
  envelope_hash VARCHAR(128) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_progress_sync_chunks (course_id, student_user_id, chapter_key),
  INDEX idx_progress_sync_chunks_student (student_user_id, updated_at, id),
  INDEX idx_progress_sync_chunks_teacher (teacher_user_id, updated_at, id),
  CONSTRAINT fk_progress_sync_chunks_course
    FOREIGN KEY (course_id) REFERENCES courses(id),
  CONSTRAINT fk_progress_sync_chunks_teacher_user
    FOREIGN KEY (teacher_user_id) REFERENCES users(id),
  CONSTRAINT fk_progress_sync_chunks_student_user
    FOREIGN KEY (student_user_id) REFERENCES users(id)
);
