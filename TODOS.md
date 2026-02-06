# TODOs
Derived from `assets/prompts/codex_architecture.md` and compared against current behavior (`learn` / `review` / `summarize` prompts with full-history inputs).

## Prompt Names And Selection
- Replace single `learn` / `review` prompts with `LEARN_INIT`, `LEARN_CONT`, `REVIEW_INIT`, `REVIEW_CONT` and route calls by `prev_json.turn_state` and segment boundaries.
- Add a distinct `SUMMARY` prompt in the flow (not just the manual summarize action) and decide whether to rename `summarize` usage or map it to `SUMMARY`.

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
- Done (2026-02-06): Checked for additional data-model/logical-flow gaps; all newly identified gaps are already covered by the existing TODO sections above (no extra manual-only items to add).
- Done (2026-02-06): Runtime now uses the new prompts (`learn_init`/`learn_cont`, `review_init`/`review_cont`, `summary`) while keeping backward compatibility for legacy logs/diagnostics.
