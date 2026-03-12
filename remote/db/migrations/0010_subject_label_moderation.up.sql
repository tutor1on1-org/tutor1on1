CREATE TABLE admin_accounts (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  user_id BIGINT NOT NULL UNIQUE,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_admin_accounts_user
    FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE subject_labels (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  slug VARCHAR(64) NOT NULL UNIQUE,
  name VARCHAR(128) NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE teacher_subject_labels (
  teacher_id BIGINT NOT NULL,
  subject_label_id BIGINT NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (teacher_id, subject_label_id),
  CONSTRAINT fk_teacher_subject_labels_teacher
    FOREIGN KEY (teacher_id) REFERENCES teacher_accounts(id),
  CONSTRAINT fk_teacher_subject_labels_label
    FOREIGN KEY (subject_label_id) REFERENCES subject_labels(id)
);

CREATE TABLE course_subject_labels (
  course_id BIGINT NOT NULL,
  subject_label_id BIGINT NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (course_id, subject_label_id),
  CONSTRAINT fk_course_subject_labels_course
    FOREIGN KEY (course_id) REFERENCES courses(id),
  CONSTRAINT fk_course_subject_labels_label
    FOREIGN KEY (subject_label_id) REFERENCES subject_labels(id)
);

CREATE TABLE subject_admin_assignments (
  subject_label_id BIGINT NOT NULL,
  teacher_user_id BIGINT NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (subject_label_id, teacher_user_id),
  CONSTRAINT fk_subject_admin_assignments_label
    FOREIGN KEY (subject_label_id) REFERENCES subject_labels(id),
  CONSTRAINT fk_subject_admin_assignments_user
    FOREIGN KEY (teacher_user_id) REFERENCES users(id)
);

CREATE TABLE teacher_registration_requests (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  user_id BIGINT NOT NULL,
  teacher_id BIGINT NOT NULL UNIQUE,
  status VARCHAR(16) NOT NULL DEFAULT 'pending',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  resolved_at DATETIME NULL,
  resolved_by_user_id BIGINT NULL,
  CONSTRAINT fk_teacher_registration_requests_user
    FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT fk_teacher_registration_requests_teacher
    FOREIGN KEY (teacher_id) REFERENCES teacher_accounts(id),
  CONSTRAINT fk_teacher_registration_requests_resolved_by
    FOREIGN KEY (resolved_by_user_id) REFERENCES users(id)
);

CREATE TABLE teacher_registration_votes (
  request_id BIGINT NOT NULL,
  subject_admin_user_id BIGINT NOT NULL,
  decision VARCHAR(16) NOT NULL,
  note TEXT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (request_id, subject_admin_user_id),
  CONSTRAINT fk_teacher_registration_votes_request
    FOREIGN KEY (request_id) REFERENCES teacher_registration_requests(id),
  CONSTRAINT fk_teacher_registration_votes_user
    FOREIGN KEY (subject_admin_user_id) REFERENCES users(id)
);

CREATE TABLE course_upload_requests (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  course_id BIGINT NOT NULL UNIQUE,
  bundle_id BIGINT NOT NULL,
  bundle_version_id BIGINT NOT NULL,
  requested_visibility VARCHAR(16) NOT NULL DEFAULT 'public',
  status VARCHAR(16) NOT NULL DEFAULT 'pending',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  resolved_at DATETIME NULL,
  resolved_by_user_id BIGINT NULL,
  CONSTRAINT fk_course_upload_requests_course
    FOREIGN KEY (course_id) REFERENCES courses(id),
  CONSTRAINT fk_course_upload_requests_bundle
    FOREIGN KEY (bundle_id) REFERENCES bundles(id),
  CONSTRAINT fk_course_upload_requests_bundle_version
    FOREIGN KEY (bundle_version_id) REFERENCES bundle_versions(id),
  CONSTRAINT fk_course_upload_requests_resolved_by
    FOREIGN KEY (resolved_by_user_id) REFERENCES users(id)
);

CREATE TABLE course_upload_votes (
  request_id BIGINT NOT NULL,
  subject_admin_user_id BIGINT NOT NULL,
  decision VARCHAR(16) NOT NULL,
  note TEXT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (request_id, subject_admin_user_id),
  CONSTRAINT fk_course_upload_votes_request
    FOREIGN KEY (request_id) REFERENCES course_upload_requests(id),
  CONSTRAINT fk_course_upload_votes_user
    FOREIGN KEY (subject_admin_user_id) REFERENCES users(id)
);

ALTER TABLE course_catalog_entries
  ADD COLUMN approval_status VARCHAR(16) NOT NULL DEFAULT 'approved' AFTER visibility;

INSERT INTO subject_labels (slug, name, is_active)
VALUES
  ('math', 'Math', TRUE),
  ('english', 'English', TRUE),
  ('science', 'Science', TRUE),
  ('history', 'History', TRUE),
  ('languages', 'Languages', TRUE),
  ('arts', 'Arts', TRUE),
  ('others', 'Others', TRUE);

INSERT INTO teacher_subject_labels (teacher_id, subject_label_id)
SELECT t.id, sl.id
FROM teacher_accounts t
JOIN subject_labels sl ON sl.slug = 'others'
LEFT JOIN teacher_subject_labels tsl
  ON tsl.teacher_id = t.id AND tsl.subject_label_id = sl.id
WHERE tsl.teacher_id IS NULL;

INSERT INTO course_subject_labels (course_id, subject_label_id)
SELECT c.id, sl.id
FROM courses c
JOIN subject_labels sl ON sl.slug = 'others'
LEFT JOIN course_subject_labels csl
  ON csl.course_id = c.id AND csl.subject_label_id = sl.id
WHERE csl.course_id IS NULL;
