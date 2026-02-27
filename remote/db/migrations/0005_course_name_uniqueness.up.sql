CREATE TEMPORARY TABLE tmp_duplicate_courses (
  course_id BIGINT PRIMARY KEY
);

INSERT INTO tmp_duplicate_courses (course_id)
SELECT c.id
FROM courses c
JOIN (
  SELECT teacher_id, LOWER(TRIM(subject)) AS course_name_key, MAX(id) AS keep_id
  FROM courses
  GROUP BY teacher_id, LOWER(TRIM(subject))
  HAVING COUNT(*) > 1
) d
  ON d.teacher_id = c.teacher_id
 AND d.course_name_key = LOWER(TRIM(c.subject))
WHERE c.id <> d.keep_id;

DELETE FROM session_text_sync
WHERE course_id IN (SELECT course_id FROM tmp_duplicate_courses);

DELETE FROM progress_sync
WHERE course_id IN (SELECT course_id FROM tmp_duplicate_courses);

DELETE FROM enrollment_deletion_events
WHERE course_id IN (SELECT course_id FROM tmp_duplicate_courses);

DELETE FROM course_quit_requests
WHERE course_id IN (SELECT course_id FROM tmp_duplicate_courses);

DELETE FROM e2ee_events
WHERE course_id IN (SELECT course_id FROM tmp_duplicate_courses);

DELETE FROM marketplace_reports
WHERE course_id IN (SELECT course_id FROM tmp_duplicate_courses);

DELETE FROM enrollment_requests
WHERE course_id IN (SELECT course_id FROM tmp_duplicate_courses);

DELETE FROM enrollments
WHERE course_id IN (SELECT course_id FROM tmp_duplicate_courses);

DELETE ce
FROM course_catalog_entries ce
JOIN tmp_duplicate_courses d ON d.course_id = ce.course_id;

DELETE bv
FROM bundle_versions bv
JOIN bundles b ON b.id = bv.bundle_id
JOIN tmp_duplicate_courses d ON d.course_id = b.course_id;

DELETE b
FROM bundles b
JOIN tmp_duplicate_courses d ON d.course_id = b.course_id;

DELETE c
FROM courses c
JOIN tmp_duplicate_courses d ON d.course_id = c.id;

DROP TEMPORARY TABLE tmp_duplicate_courses;

ALTER TABLE courses
  ADD COLUMN course_name_key VARCHAR(191) NULL AFTER subject;

UPDATE courses
SET course_name_key = LOWER(TRIM(subject))
WHERE course_name_key IS NULL OR course_name_key = '';

ALTER TABLE courses
  MODIFY course_name_key VARCHAR(191) NOT NULL;

ALTER TABLE courses
  ADD UNIQUE KEY uq_courses_teacher_name_key (teacher_id, course_name_key);
