ALTER TABLE session_text_sync
  ADD COLUMN content_hash VARCHAR(128) NULL AFTER envelope_hash;

ALTER TABLE progress_sync
  ADD COLUMN content_hash VARCHAR(128) NULL AFTER envelope_hash;

ALTER TABLE progress_sync_chunks
  ADD COLUMN content_hash VARCHAR(128) NULL AFTER envelope_hash;
