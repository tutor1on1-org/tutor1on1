DROP TABLE IF EXISTS teacher_study_mode_schedules;
DROP TABLE IF EXISTS teacher_study_mode_overrides;
DROP TABLE IF EXISTS app_user_devices;

ALTER TABLE refresh_tokens
  DROP COLUMN device_session_nonce,
  DROP COLUMN device_key;

ALTER TABLE teacher_accounts
  DROP COLUMN control_pin_hash;
