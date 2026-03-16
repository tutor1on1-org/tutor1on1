# Validation Run

## 2026-03-16 Albert simple flow

- Branch: `simple`
- User: `albert`
- Password used for log crypto + live validation: `1234`
- Course: `UK_MATH_7-13`
- KP: `1.1.1.1`
- Expected result: `lit = false`

### Scenario

1. Start a fresh temp session from a copied DB.
2. Run `learn`.
3. Run `learn` again.
4. Run `review`.
5. Send `I don't understand`.
6. Press summarize.

### Command

```powershell
flutter test integration_test\live_albert_simple_flow_test.dart -d windows
```

### Result

- Passed.
- Final assistant summary: `For this knowledge point, there have been 0 review attempts and 0 correct answers so far. No mastery has been demonstrated yet.`
- Final `lit`: `false`
- Final evidence counters: `review_correct_total=0`, `review_attempt_total=0`

### Issues found and fixed during validation

- Live `learn` was using legacy DB prompt overrides instead of the new bundled simplified prompt. Fixed by making `learn` / `review` / `summary` bundled-only in `PromptRepository`.
- OpenAI live calls could still drift into prose. Fixed by sending `response_format=json_schema` for structured prompts on the official OpenAI endpoint.
- `summary` reused old `progress_entries` cache and could return a stale `lit=true` from another session. Fixed by caching only the current session summary and computing `lit` from current session evidence.

### Real DB safety check

- Live DB path: `C:\Mac\Home\Documents\family_teacher.db`
- `chat_sessions` before run: `36`
- `chat_sessions` after run: `36`
- `chat_messages` before run: `417`
- `chat_messages` after run: `417`
- Conclusion: validation used only the temp copied DB and did not add rows to the real usage sessions.

## 2026-03-16 Albert role-play pass flow

- Branch: `simple`
- User: `albert`
- Password used for log crypto + live validation: `1234`
- Course: `UK_MATH_7-13`
- KP: `1.1.1.1`
- Expected result: `lit = true`

### Scenario

1. Start a fresh temp session from a copied DB.
2. Send `Can you teach this simply first?`
3. Press `review`.
4. Use a separate live structured `student_roleplay` call to answer the teacher's live review question.
5. Continue until two review questions close as correct.
6. Press summarize.

### Command

```powershell
flutter test integration_test\live_albert_simple_flow_test.dart -d windows
```

### Result

- Passed.
- Review question 1: `Which number is greater: -3 or 2?`
- Student reply 1: `2`
- Review question 2: `Order these numbers from least to greatest: -4, |-2|, 1, -|3|.`
- Student reply 2: `-4, -3, 1, 2`
- Final assistant summary: `You’ve correctly completed 2 out of 2 review attempts for this knowledge point, including the latest medium-level item. That shows solid current mastery so far.`
- Final `lit`: `true`
- Final evidence counters: `review_correct_total=2`, `review_attempt_total=2`

### Extra issue found and fixed during validation

- Live runs could fail before any tutor logic due to transient TLS `HandshakeException`. Fixed by retrying handshake failures in the shared LLM transport path.

### Real DB safety check

- Live DB path: `C:\Mac\Home\Documents\family_teacher.db`
- `chat_sessions` before run: `36`
- `chat_sessions` after run: `36`
- `chat_messages` before run: `417`
- `chat_messages` after run: `417`
- Conclusion: validation used only the temp copied DB and did not add rows to the real usage sessions.

## 2026-03-16 Albert 10-call prompt quality review

- Branch: `simple`
- User: `albert`
- Course: `UK_MATH_7-13`
- KP: `1.1.1.1`
- Goal: review 10 live tutor calls for response quality and prompt weaknesses.

### Command

```powershell
flutter test integration_test\live_albert_simple_flow_test.dart -d windows --plain-name "Albert prompt quality review flow prints 10 tutor calls"
```

### Outcome

- Passed.
- Produced exactly 10 tutor calls on a temp copied DB.
- Best outputs: clear learn explanations, useful hinting, correct graded review feedback, honest summary.
- Main quality issue found: one live review turn returned `teacher_message="Try this."` while the actual question lived only in `question_text`. That is unacceptable because the student only sees `teacher_message`.
- Secondary quality issue found: learn turns still sometimes emit markdown/LaTeX-style formatting like `\(` `\)` and bold markers, which is noisier than needed for a child-facing teacher message.

### Real DB safety check

- `chat_sessions` before run: `36`
- `chat_sessions` after run: `36`
- `chat_messages` before run: `417`
- `chat_messages` after run: `417`

## 2026-03-16 Simplified no-summary tutor pipeline validation

- Branch: `simple`
- User: `albert`
- Password used for log crypto + live validation: `1234`
- Course: `UK_MATH_7-13`
- KP: `1.1.1.1`
- Runtime contract under test:
  - `learn` => `{text,difficulty,mistakes,next_action}`
  - `review` => `{text,difficulty,mistakes,next_action,finished}`
  - no active `summary` prompt
  - app computes `summary_lit` locally from finished review count

### Commands

```powershell
flutter analyze
flutter test
flutter test integration_test\live_albert_simple_flow_test.dart -d windows
```

### Result

- Passed.
- `flutter analyze`: passed.
- `flutter test`: passed.
- Live Albert integration on a temp copied DB: passed.
- Fail-flow check:
  - sequence: `learn`, `learn`, `review`, `review("I don't understand")`
  - result: `summary_lit=false`, `review_correct_total=0`, `review_attempt_total=0`
- Pass-flow check:
  - role-played Albert answered two review items correctly
  - result: `summary_lit=true`, `review_correct_total=2`, `review_attempt_total=2`
- Quality-flow check:
  - produced exactly 10 assistant tutor turns using only `learn`/`review`
  - no summarize action used

### Notes

- The live tutor still sometimes emits formatting/control-noise in `text` (for example odd inline control characters around styled math). This did not break the new wiring, but it is still a prompt or output-sanitization quality issue.

### Real DB safety check

- Live DB path: `C:\Mac\Home\Documents\family_teacher.db`
- Validation copied that DB into a temp directory before running.
- Real usage DB was not used for the live runs, so no actual student sessions were modified.

## 2026-03-16 Weighted KP-pass rule validation

- Branch: `simple`
- User: `albert`
- Course: `UK_MATH_7-13`
- KP: `1.1.1.1`
- New rule:
  - easy weight = `0.25`
  - medium weight = `0.5`
  - hard weight = `1`
  - pass threshold = `1`
- Lit source: app-controlled from persistent passed counts, not a fixed `2 correct` rule.

### Commands

```powershell
flutter analyze
flutter test
flutter test integration_test\live_albert_simple_flow_test.dart -d windows
```

### Result

- Passed.
- `flutter analyze`: passed.
- `flutter test`: passed.
- Live Albert integration: passed.

### Observed behavior

- Fail-flow check still behaved correctly:
  - sequence: `learn`, `learn`, `review`, `review("I don't understand")`
  - result: `summary_lit=false`, `review_correct_total=0`, `review_attempt_total=0`
- Role-play pass-flow changed in the expected way under weighted lit:
  - Albert needed 3 successful review completions, not 2
  - observed path: `easy` correct, then `medium` correct, then `hard` correct
  - result: `summary_lit=true`, `review_correct_total=3`, `review_attempt_total=3`
- This confirms the weighted threshold is driving pass/fail now.

### Misses / improvements found in live transcript

- Learn text still sometimes contains formatting/control-noise in visible output, including odd control characters and markdown/LaTeX wrappers.
- The tutor often starts with `medium` on learn even when the first review starts at `easy`; that difficulty estimate may be reasonable internally, but the student-facing explanation style is still sometimes more formatted than needed.
- Review flow quality was otherwise coherent: one active question, usable hinting, and deterministic local passing after the hard item.

### Real DB safety check

- Validation used only a temp copy of `C:\Mac\Home\Documents\family_teacher.db`.
- Real usage DB was not modified.

## 2026-03-16 Albert prompt-quality mock run, 5 live iterations

- Branch: `simple`
- User: `albert`
- Course: `UK_MATH_7-13`
- KP: `1.1.1.1`
- Goal: improve the bundled simplified `learn` / `review` prompts by judging the live student-visible transcript after each rerun.

### Command used each iteration

```powershell
flutter test integration_test\live_albert_simple_flow_test.dart -d windows --plain-name "Albert prompt quality review flow prints 10 learn/review tutor calls"
```

### Iteration notes

- Iteration 1:
  - Changed prompts to prefer simple visible text and avoid escaped LaTeX wrappers / decorative formatting / filler question labels.
  - Result: output became cleaner, but hard review drifted into overly algebraic setup.
- Iteration 2:
  - Tightened `review` to stay tightly on the KP and prefer concrete numbers; tightened `learn` so `mistakes` stays empty unless the student clearly showed a mistake.
  - Result: hard review stayed closer to the KP and learn stopped inventing mistake tags in this flow.
- Iteration 3:
  - Tightened `learn` length and reduced repeated explanation structure; tightened `review` to keep easy single-step and medium/hard concise.
  - Result: transcript became shorter and easier to read, but hard-review hints still repeated too much of the original question.
- Iteration 4:
  - Changed `review` hint rule to avoid repeating the whole question verbatim and to end with one short direct ask.
  - Result: better, but hard-review hints still carried too much of the original multi-part task.
- Iteration 5:
  - Changed `review` hints on multi-part questions to ask only for the next unresolved part and limited hard questions to one simplification step before the student answers.
  - Result: main visible issue fixed. Final hard-review hint narrowed cleanly to `Start with C: |-5| = 5. What is C?`

### Final observed transcript quality

- Learn:
  - clearer and shorter than the starting point
  - still sometimes estimates `difficulty=medium` for early conceptual explanation turns
  - second learn turn recommended `next_action=review`, which better matches the student flow after a clear explanation
- Review:
  - easy and medium items were concise and directly answerable
  - the final hard item stayed on-KP and the hint reduced to one immediate sub-step instead of reissuing the whole task
- Remaining quality gaps:
  - some learn turns are still slightly denser than ideal for a confused student
  - tutor output still occasionally uses punctuation/styling that is a bit more polished than necessary, but no longer blocks understanding

### Result

- Passed.
- All 5 live prompt-iteration reruns passed.
- Final transcript quality improved on the exact visible failure modes found during the loop.
- Validation used only a temp copy of the live DB; real usage data was not modified.

## 2026-03-16 Retry-log retention and prompt hardening

- Branch: `simple`
- Goal:
  - keep all LLM retry attempts visible in `llm_calls`
  - reduce malformed structured-output retries by shortening `learn` / `review` prompts and adding exact JSON examples

### Root-cause evidence

- A real student run at `2026-03-16 23:12:05` retried because the model emitted `mist akes` instead of `mistakes`.
- The JSONL metadata log showed both attempts, but the LLM logs page only showed the final accepted one because `llm_calls.call_hash` was unique and inserts used replace semantics.

### Commands

```powershell
dart run build_runner build --delete-conflicting-outputs
flutter test test\llm_call_repository_test.dart test\session_service_test.dart test\migration_test.dart
flutter analyze
flutter test integration_test\live_albert_simple_flow_test.dart -d windows --plain-name "Albert prompt quality review flow prints 10 learn/review tutor calls"
flutter build windows
```

### Result

- Passed.
- Migration/repository tests passed.
- `flutter analyze`: passed.
- Live Albert quality flow: passed.
- Windows release build: passed.

### Observed behavior

- After the prompt rewrite, the 10-call live Albert quality flow completed without the malformed-key retry pattern seen in the earlier `mist akes` failure.
- The new prompt bodies are much shorter and now include exact JSON examples for the model to copy literally.
- `llm_calls` is now append-only across retries, and replay lookup reads the latest row for a given `call_hash`.

## 2026-03-16 Post-stream busy diagnosis and KP-passed dialog

- Branch: `simple`
- User report:
  - visible tutor text had already finished streaming
  - GUI still showed busy/waiting for about 10 seconds
  - app should show a non-fading congratulations message when the KP is passed

### Root-cause evidence

- For the latest affected live call on student session `83` / KP `2.3.5.1`, the logs show:
  - `23:35:12.694` first `review` LLM attempt finished
  - that first attempt failed structured validation because the model emitted `mist akes` instead of `mistakes`
  - `23:35:12.702` app logged `APP retry`
  - `23:35:30.569` second `review` LLM attempt finished successfully
  - `23:35:30.720` app persisted the accepted result
- This means the visible stream from the first attempt ended, but `_sending` stayed true while the app waited for the retry attempt to finish. The delay was retry time, not a stuck spinner after successful completion.

### Commands

```powershell
flutter test test\session_service_test.dart test\llm_call_repository_test.dart
flutter gen-l10n
flutter analyze
flutter build windows
```

### Result

- Passed.
- `flutter test`: passed.
- `flutter analyze`: passed.
- Windows release build: passed.

### UI change

- When the session flips to passed, the tutor page now shows a non-auto-fading dialog with the current session's:
  - easy correct count
  - medium correct count
  - hard correct count
