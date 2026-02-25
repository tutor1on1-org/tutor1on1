DROP TABLE IF EXISTS password_resets;

DROP INDEX uq_users_username ON users;

ALTER TABLE users
  DROP COLUMN username;
