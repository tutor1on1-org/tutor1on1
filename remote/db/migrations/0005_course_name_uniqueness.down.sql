ALTER TABLE courses
  DROP INDEX uq_courses_teacher_name_key;

ALTER TABLE courses
  DROP COLUMN course_name_key;
