## Input Assembly Changes
- INIT calls must include full context: `lesson_content`, `types`, `error_book_summary`, `practice_history_summary`, and for `REVIEW_INIT` a `presented_questions` pool.
- CONT calls must include only `recent_dialogue` (since last INIT) and `prev_json` from the prior turn.
- Current implementation sends full session history and does not pass `prev_json` or the new context fields.

## State And Persistence
- Persist `prev_json` per session/segment and use it to select INIT vs CONT on subsequent turns.
- Track and enforce `turn_state` (`UNFINISHED` vs `FINISHED`) so UNFINISHED turns do not apply grading or mastery updates.

## Review Flow Alignment
- Provide a candidate question pool and allow the model to select one question; persist the selected question and include it in the teacher message.
- Store per-question attempt records when grading exists (question text, student answer, correctness, hint level, etc.).
- Apply `error_book_update` only when FINISHED and grading exists.

## Summary Flow Alignment
- Parse SUMMARY JSON fields (`mastery_level`, `next_step`, etc.) and route app behavior based on `next_step` (RELEARN / CONTINUE_REVIEW / MOVE_ON).
- Align summary persistence with the new schema instead of relying on ad-hoc parsing of text.

## Data Model Extensions
- Add per-knowledge-point `types` (including `OTHER`) and an `error_book` aggregated by `(type_id, mistake_tag)` with counts and timestamps.
- Add per-session rolling evidence fields (`a`, `c`, `h`, `t`, `mt`).
- Add program-produced `practice_history_summary` stored per session or per knowledge point.

## Validation And Determinism
- Enforce strict JSON validation by prompt-specific allowed keys and retry invalid responses using the same prompt.
- Log prompt version plus input hash for deterministic replay and auditability.

## Manual TODOs
- Done (2026-02-06): Added structured-output persistence fields for tutor turns in `chat_messages` (`raw_content`, `parsed_json`) and wired migration.
- Done (2026-02-06): Tutor/review structured JSON is parsed and the UI now stores/displays only formatted teacher text (`teacher_message`) instead of raw JSON payloads.
