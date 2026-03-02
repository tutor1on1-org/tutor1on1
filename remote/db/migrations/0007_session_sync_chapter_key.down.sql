DROP INDEX idx_session_text_student_course_chapter_updated ON session_text_sync;

ALTER TABLE session_text_sync
  DROP COLUMN chapter_key;
