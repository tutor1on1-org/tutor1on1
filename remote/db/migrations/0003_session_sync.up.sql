CREATE TABLE user_keys (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  user_id BIGINT NOT NULL UNIQUE,
  public_key TEXT NOT NULL,
  enc_private_key MEDIUMTEXT NOT NULL,
  kdf_salt VARCHAR(128) NOT NULL,
  kdf_iterations INT NOT NULL,
  kdf_algorithm VARCHAR(64) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_user_keys_user
    FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE session_text_sync (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  session_sync_id VARCHAR(64) NOT NULL UNIQUE,
  course_id BIGINT NOT NULL,
  teacher_user_id BIGINT NOT NULL,
  student_user_id BIGINT NOT NULL,
  sender_user_id BIGINT NOT NULL,
  updated_at DATETIME NOT NULL,
  payload_size INT NOT NULL,
  envelope MEDIUMBLOB NOT NULL,
  envelope_hash VARCHAR(128) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_session_text_teacher (teacher_user_id, updated_at),
  INDEX idx_session_text_student (student_user_id, updated_at),
  CONSTRAINT fk_session_text_course
    FOREIGN KEY (course_id) REFERENCES courses(id),
  CONSTRAINT fk_session_text_teacher_user
    FOREIGN KEY (teacher_user_id) REFERENCES users(id),
  CONSTRAINT fk_session_text_student_user
    FOREIGN KEY (student_user_id) REFERENCES users(id),
  CONSTRAINT fk_session_text_sender_user
    FOREIGN KEY (sender_user_id) REFERENCES users(id)
);
