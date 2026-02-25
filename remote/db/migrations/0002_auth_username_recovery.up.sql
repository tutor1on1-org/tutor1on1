ALTER TABLE users
  ADD COLUMN username VARCHAR(64) NULL AFTER id;

UPDATE users
SET username = email
WHERE username IS NULL;

ALTER TABLE users
  MODIFY username VARCHAR(64) NOT NULL;

CREATE UNIQUE INDEX uq_users_username ON users(username);

CREATE TABLE password_resets (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  user_id BIGINT NOT NULL,
  token_hash VARCHAR(128) NOT NULL UNIQUE,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at DATETIME NOT NULL,
  used_at DATETIME NULL,
  CONSTRAINT fk_password_resets_user
    FOREIGN KEY (user_id) REFERENCES users(id)
);
