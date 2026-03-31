ALTER TABLE progress_sync_chunks
  DROP COLUMN content_hash;

ALTER TABLE progress_sync
  DROP COLUMN content_hash;

ALTER TABLE session_text_sync
  DROP COLUMN content_hash;
