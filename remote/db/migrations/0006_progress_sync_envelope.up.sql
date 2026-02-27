ALTER TABLE progress_sync
  ADD COLUMN envelope MEDIUMBLOB NULL AFTER updated_at,
  ADD COLUMN envelope_hash VARCHAR(128) NULL AFTER envelope;
