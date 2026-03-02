ALTER TABLE session_text_sync
  ADD COLUMN chapter_key VARCHAR(64) NOT NULL DEFAULT '' AFTER sender_user_id;

CREATE INDEX idx_session_text_student_course_chapter_updated
  ON session_text_sync (student_user_id, course_id, chapter_key, updated_at, id);
