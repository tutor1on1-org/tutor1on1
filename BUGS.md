# BUGS
Last updated: 2026-03-23

## Active watch
- Student import race after bundle download (monitoring): fixed by awaiting archive extraction in client bundle service (`f77e7e0`); keep watching for recurrence in production-like flow.

## Lessons learned (do not repeat)
1. Archive extraction race
- Symptom: intermittent `Missing file: ...contents.txt (or ...context.txt)` right after download.
- Root cause: `extractArchiveToDisk(...)` is async and was called without `await`.
- Prevention: always await extraction before any import/validation step.

2. Drift migration sequencing
- Symptom: duplicate-column failures during upgrades.
- Root cause: `addColumn` executed even when table was created mid-upgrade.
- Prevention: guard `addColumn` with `from >= <tableCreateVersion>` when table creation is conditional.

3. Bundle validity drift between client and server
- Symptom: invalid bundles can appear as latest downloadable versions.
- Root cause: relying on client-only validation.
- Prevention: enforce required bundle files and lecture-reference checks on server upload path too.

4. Tutor output parsing failures
- Symptom: invalid LLM response rendered as unusable content.
- Root cause: non-JSON or missing required fields.
- Prevention: require valid structured JSON and `teacher_message`; surface parse errors explicitly.

5. Authenticated download 403 on server
- Symptom: API approved download but Nginx denied file read.
- Root cause: Nginx worker lacked storage read/traverse permission.
- Prevention: ensure `nginx` can traverse/read `STORAGE_ROOT` (group membership and permissions).

6. Remote shell automation instability
- Symptom: non-interactive SSH commands fail intermittently.
- Root cause: missing `PATH` entries in some ECS sessions.
- Prevention: use absolute tool paths in automation scripts.

7. Bundle ZIP lazy-read stream lifecycle
- Symptom: student download/import fails with `FormatException: Filter error, bad data` on valid bundles (more visible on larger bundles).
- Root cause: `InputFileStream` was closed immediately after `ZipDecoder().decodeBuffer(...)`; archive entries are lazy-read later during validation/extraction, so reads occurred on a closed file handle.
- Prevention: keep `InputFileStream` open for the full lifetime of archive entry access and close in `finally` only after extraction/metadata/validation completes. Add regression test with a >1 MB zip to catch premature stream closure.

8. Student course duplication on re-download
- Symptom: student sees version-like duplicate course names and progress appears split across versions after downloading updates.
- Root cause: manual marketplace download imported as a fresh local course using extracted folder basename (timestamp/version-like), replacing remote link and orphaning old local progress.
- Prevention: resolve existing `remoteCourseId -> courseVersionId`, then import with `override` mode and explicit server `course_subject` as course name.

9. Session sync rate-limit bursts
- Symptom: `Session sync failed: rate limit exceeded` during login/startup sync.
- Root cause: progress sync uploaded one request per progress row; large local progress sets exceeded sync API rate limits.
- Prevention: upload progress entries in a single batch request (`/api/progress/sync/upload-batch`) and process server-side in one transaction.

10. Teacher catalog shrink after quit approvals
- Symptom: teacher local course list drops courses after student quit approval/deletion events, while marketplace still has them.
- Root cause: teacher-side deletion-event replay removed student data and then deleted the whole local course when assignment count reached zero.
- Prevention: for teacher replay, never delete course definitions from assignment count checks; only remove the specific student-course data.

11. Suffix-duplicate local courses from sync fallback
- Symptom: local lists show `{name}_{version_id}` duplicates and stale unlinked rows; clicking versions can fail with "No remote bundle found".
- Root cause: when `remoteCourseId` mapping was missing, sync/import created fresh placeholder courses using suffix-tainted subject names instead of reconciling by normalized name.
- Prevention: reconcile by normalized subject (strip trailing `_<timestamp>`), relink to remote course, and migrate stale student data to canonical course IDs before deleting duplicates.

12. Local plugin override interface drift
- Symptom: `flutter build windows --release` fails with override signature errors in `packages/record_linux` after dependency resolution updates.
- Root cause: local path override implemented an outdated platform-interface method signature (`hasPermission(String)`), while `record_platform_interface` required `hasPermission(String, {bool request = true})`.
- Prevention: keep all local package overrides in lockstep with platform-interface method signatures whenever dependencies are refreshed; verify with release build gate.

13. Windows secure-storage sync state contention
- Symptom: session sync becomes very slow and can fail with `PathAccessException ... flutter_secure_storage.dat ... used by another process`.
- Root cause: thousands of per-item sync states were stored in `flutter_secure_storage`; on Windows the plugin reads/decrypts and rewrites the whole encrypted file for each key operation, which creates heavy local I/O and file-lock races under large sync sets.
- Prevention: keep secure storage for low-cardinality secrets only, store high-cardinality sync metadata/state in SQLite, and use manifest+fetch sync so normal download sync does not depend on per-row cursor chatter.

14. Duplicate local users for one remote account
- Symptom: session sync fails with `Bad state: Too many elements` while resolving a user by remote id.
- Root cause: local auth persisted users by username only, while sync placeholder flows could also create local users keyed by the same `remoteUserId`; because local `users.remoteUserId` was not unique, multiple rows could exist for one remote account and `findUserByRemoteId(...).getSingleOrNull()` exploded.
- Prevention: enforce uniqueness for non-null `users.remoteUserId`, reconcile auth logins by remote id before username-only create/update, and run a local cleanup pass that merges pre-existing duplicate users before adding the unique index.

15. Windows packaged STT recording fails at start with AAC encoder
- Symptom: packaged Windows app shows `Recording start failed.` when voice input begins.
- Root cause: the app requested `AudioEncoder.aacLc` from `record_windows`; encoder support may appear present, but the Windows sink-writer start path for AAC can still fail in packaged environments, while the plugin's WAV/PCM path is the stable capture path.
- Prevention: use `AudioEncoder.wav` for Windows recording, keep desktop STT capture separate from later MP3 export/transcode, and regression-test the platform encoder selection.

16. Progress sync must be monotonic across devices
- Symptom: a fresh sync can show a weaker progress state, or a chapter chunk can silently lose earlier stronger KP progress after only one sibling KP changes.
- Root cause: progress download/import used overwrite semantics, and chapter chunk upload was built from only recently changed KPs even though the server stores one full snapshot per `(course, student, chapter)`; that allowed weaker or partial chapter state to replace stronger existing state.
- Prevention: during sync import, keep the stronger of local and incoming progress; when uploading chapter chunks, send the full current chapter snapshot, not only the changed subset; and reject weaker incoming row updates on the legacy server row path.

17. Skill tree display must use one canonical display color path
- Symptom: a leaf in the tree can stay grey while the selected KP row/summary indicates the node is passed.
- Root cause: the tree leaf used a binary grey/green rule while the detail row used a separate ratio-based color path, so the same KP could render in two different colors even when both views were looking at the same resolved display state.
- Prevention: define one canonical display-percent resolver, feed it into one shared color-mapping helper, and make both the graph leaf and detail row call that same helper.

18. Tutor review flow must not auto-advance to New before the current turn is finished
- Symptom: sending an answer in review mode can immediately show `Switched to New` before the next LLM reply arrives.
- Root cause: the page-level pre-send resolver used stricter "active review" rules than the session service, requiring a persisted `question` object instead of following the canonical `turn_state`; that let the UI auto-reset to New while the current review turn was still logically unfinished.
- Prevention: derive tutor turn activity from one shared helper based on action + `turn_state`, and use that same helper for both assistant suggestion UI and pre-send prompt resolution.

19. STT start must detach the draft editor from active IME composition
- Symptom: starting mic recording while a draft answer is already being edited can crash the session page.
- Root cause: recording started while the text field still owned focus and an active composing range, then the STT flow later rewrote the same controller value; desktop IME/input state can break on that transition.
- Prevention: normalize the draft input before STT start by clearing the composing range, collapsing selection to the append point, and unfocusing the editor until recording/transcription completes.

20. Message replay must follow the selected message branch, not the current page mode
- Symptom: refreshing an old assistant answer or editing the last student answer can replay the wrong tutor prompt family after the session mode chip has changed.
- Root cause: replay/edit resolution looked at the page-global `_mode` and `_step` instead of the target message's own `action`, so a learn message could be regenerated with review prompts, or vice versa.
- Prevention: resolve replay/edit prompt names from the selected message action plus that action branch's active-turn state, and keep that logic separate from the page-global send path.

21. Composer growth must keep the latest chat content visible
- Symptom: pressing `Shift+Enter` to add a new line can expand the input box upward and cover the newest conversation content until the user scrolls manually.
- Root cause: the session page auto-scrolled when the message list changed, but not when the composer itself grew taller.
- Prevention: when the composer line count increases, schedule a scroll-to-bottom after layout so the latest messages stay visible above the input area.

22. Server sync writes must reject stale timestamps for session and chapter snapshots
- Symptom: two devices can race and an older session/chapter snapshot upload can overwrite newer remote state because the server accepts blind last-writer-wins updates.
- Root cause: `session_text_sync` and `progress_sync_chunks` upserts replaced existing rows without comparing `updated_at`.
- Prevention: on the server, lock the existing row, and only update when incoming `updated_at` is strictly newer; stale uploads should be skipped silently so clients stay simple.

23. Tutor control/evidence must not be reconstructed from degraded chat history
- Symptom: review answers can auto-switch to `New Learn` before the LLM reply arrives, and summary can claim "no new evidence" even after a correct answer on another device or after sync/import.
- Root cause: the app inferred control flow (`new/continue`, mode, finished-turn choices) and evidence state by scanning `chat_messages` fields like `action`, `parsed_json`, `turn_state`, and review payload history; sync/import could strip or degrade those message fields, so the app silently rewrote the user's visible state and injected fake-zero summary evidence.
- Prevention: keep tutor control state and evidence state as explicit session-level durable contracts, sync them separately from chat history, make prompts return one canonical `control` object, and let visible labels map directly to prompt names without hidden history-based rewrites.

24. Summary must use the shared structured tutor payload pipeline
- Symptom: pressing `Summary` can show `Summary saved (unparsed)` even though the reply should have produced a normal pass/fail result.
- Root cause: `startSummarize()` was still manually reparsing raw `responseText` and treating malformed structured output as a successful but "unparsed" summary, instead of going through the same validated/retryable structured payload resolver used by `learn_*` and `review_*`.
- Prevention: make `summary` use `_resolveStructuredPayload(...)` and the parsed payload returned by the validator/retry pipeline; malformed summary JSON should retry or fail, not silently save as a pseudo-success.

25. Summary cache must not claim success without a concrete mastery result
- Symptom: pressing `Summary` can still show `Summary saved (unparsed)` in a current build, even after the structured summary parser was unified.
- Root cause: `startSummarize()` had a cached-summary early return that reused old summary text when no new graded review evidence existed, but that cache path derived mastery only from `progress.questionLevel`; when cached text existed without a stored level/percent, it returned `success=true` with `litPercent=null`, which reactivated the UI's unparsed-success branch.
- Prevention: keep one postcondition for summary success. Cache is only an optimization layer; it may reuse an existing summary only when it can also return a concrete mastery result (`litPercent`/pass-fail). Otherwise it must fall through to the normal LLM summary path.

26. Review question ownership must not be split across visible text and hidden structured fields
- Symptom: `review_init` can return `teacher_message` like `Try this one:` while putting the actual question only in a separate `question.text` field, so the student sees no usable question.
- Root cause: the review prompt/schema allowed two plausible question carriers (`teacher_message` and `question.text`) without declaring one canonical student-visible owner, so the LLM chose the cheaper split response.
- Prevention: keep the full student-visible review question in `teacher_message` and avoid parallel hidden question payloads unless the contract clearly defines them as derived/internal only.

27. Summary evidence can silently stay at zero after a finished review
- Symptom: pressing `Summary` after a graded review can act like there is no new evidence, reuse stale cache, or leave mastery at `0` even though the last review turn was finished and graded.
- Root cause: evidence accounting still looked at legacy `turn_state == FINISHED` instead of the canonical structured `control.turn_finished`, so newer review payloads never incremented `graded_review_count`.
- Prevention: derive review evidence updates from the same canonical control object used by the rest of the tutor flow, and keep a regression test that a finished graded review increments `graded_review_count`.

28. Student devices can show placeholder remote teacher names in logs/UI
- Symptom: LLM logs or course ownership can show `remote_teacher_<id>` instead of the real teacher name, even when the server already knows the teacher name.
- Root cause: student enrollment sync created remote teacher placeholder users from `teacher_id` only and never renamed them when `teacher_name` became available.
- Prevention: pass `teacher_name` into remote teacher resolution and upgrade placeholder usernames to the real server teacher name whenever the local record is still placeholder-only.

29. Android release login can appear dead before the auth request starts
- Symptom: tapping login/register on Android release can produce no visible response for teacher/student auth flows.
- Root cause: the new device-bound auth path read platform device metadata before calling the API, and uncaught errors from hostname/device-identity lookup escaped the async button handler instead of becoming a user-visible auth failure.
- Prevention: treat platform hostname lookup as best-effort only, fallback to a safe device name/fingerprint seed when it fails, and catch/surface any pre-request device/storage errors in `AuthController` so the UI reports the failure instead of looking unresponsive.

30. Fragment seam repair must distinguish natural-language streams from structured JSON tutor payloads
- Symptom: streamed `think` text can show doubled spaces such as `step  next`, and structured tutor replies can lose real spaces, often most visibly around number-adjacent seams such as `Lesson2` or `2examples`. A bad hotfix can also overcorrect and create bogus spaces inside split words such as `Gal ilean`.
- Root cause: the shared extractor normalized fragments with `trim()`, so whitespace-only chunks from the provider were discarded before structured JSON reassembly. Numeric boundaries exposed this more often because models commonly emit the separating space as its own fragment near numbers. The later hotfix misdiagnosed the loss as a seam-repair problem and guessed spaces from alphanumeric boundaries, which corrupted valid mid-word token splits.
- Prevention: preserve raw provider fragments, including whitespace-only chunks, in the shared LLM response path. Keep one shared structured JSON joiner for all tutor returns, and limit seam normalization to collapsing duplicated explicit boundary whitespace already present in adjacent fragments. Never infer missing spaces from letter/digit boundaries alone.

31. Teacher-enforced study mode drifted out of the real enforcement path
- Symptom: clicking the global `X` during a student session could show `teacher account not found`, and students could also bypass enforcement through logout/current-device deletion when teacher study mode was active.
- Root cause: teacher-enforced study mode was mixed with a persistent local settings toggle and a page-specific quit policy; the app tried to prove the teacher PIN from local state or a cached `control_pin_hash` on the student device instead of from one shared live enforcement path.
- Prevention: keep teacher-enforced study mode as student-only runtime state driven by the heartbeat decision, gate quit/logout/current-device deletion through one shared confirmation flow, and verify the control PIN against the server instead of caching the hash on the student device.

32. Student login sync can bind a remote course to the wrong local course
- Symptom: student relogin can fail course sync with `Bad state: Node names are immutable for existing IDs...` even when no teacher uploaded a new course.
- Root cause: client sync treated a subject-matched local course as if it were the same remote course, persisted that weak link, and later tried to in-place override it with the real server bundle. The immutability guard then correctly rejected mismatched node text under the same KP ids.
- Prevention: never trust a student `remoteCourseId` link without stored bundle identity for that same remote course (`installed bundle version` or synced bundle hash). If the link is weak, import the server bundle as a fresh local course, migrate the student's sessions/progress, and then rebind the remote course to the new local copy.

33. Student session footer progress can disappear even when the data is present
- Symptom: the model dropdown still renders on the student tutor page, but the new `easy/medium/hard/percent` badge is missing.
- Root cause: the badge was inserted into an already-tight desktop footer strip without reworking the row constraints, so the footer overflowed horizontally and the badge could be clipped out of view in release builds.
- Prevention: keep the badge pinned on the left and make the rest of the tutor footer horizontally scrollable instead of relying on one tight fixed row; add a widget test that renders the real footer at a constrained width and asserts the badge and model selector both remain visible.

34. Teacher PIN quit prompts can stick after study mode is no longer active
- Symptom: closing the app, logging out, or deleting the current device can still ask for the teacher PIN even though study mode is no longer active.
- Root cause: `StudyModeController` kept stale enforced state when the same student account re-synced, and quit gating trusted that cached runtime state without first refreshing or clearing it.
- Prevention: same-student auth sync must clear stale enforced state, and the shared quit flow must refresh current study-mode state before deciding whether a teacher PIN is required.

35. Teacher prompt settings diverged from live tutor prompt resolution
- Symptom: teacher/student prompt scopes for `learn` and `review` could appear blank in Preview, teacher edits did not affect runtime, and synced prompt metadata could silently carry malformed placeholders that later broke variable injection expectations.
- Root cause: runtime still treated `learn`/`review` as bundled-only prompts, Prompt Settings preview/diff rendered append-only fragments instead of the resolved prompt, student-global scope was missing from the resolution chain, and prompt validation did not block malformed or non-English placeholder identifiers.
- Prevention: keep one shared resolved-prompt path for runtime and Preview/Diff (`bundled fallback -> teacher default -> course -> student-global -> student-course`), expose the same scopes in UI and sync, reject invalid prompt templates on teacher save and sync apply, and when bundle-level conflicts can be caused by prompt metadata, label them as bundle conflicts and provide an explicit teacher-side "Pull Latest Server" action.

36. Legacy/current prompt bundle metadata created false teacher sync conflicts
- Symptom: teacher sync could still fail with `Teacher bundle sync conflict ... Pull latest server bundle` immediately after a successful pull from server.
- Root cause: semantic bundle hashing treated legacy prompt metadata representation (`_family_teacher/prompt_bundle.json`, `family_teacher_prompt_bundle_v1`) and current representation (`_tutor1on1/prompt_bundle.json`, `tutor1on1_prompt_bundle_v1`) as different, even when the prompt payload itself was semantically identical. Pulling a legacy server bundle therefore wrote one hash to sync state, while the client recomputed a different local hash on the next sync and raised a false conflict.
- Prevention: canonicalize supported prompt metadata entry paths and schema names before semantic hashing, and keep a regression test for `legacy server bundle -> pull -> second sync` so this mismatch cannot silently return.
