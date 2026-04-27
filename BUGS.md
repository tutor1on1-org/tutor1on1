# BUGS
Last updated: 2026-04-27

## Active watch
- Student import race after bundle download (monitoring): fixed by awaiting archive extraction in client bundle service (`f77e7e0`); keep watching for recurrence in production-like flow.

## Scope note
- Current canonical sync model is zip-artifact manifest sync. Bug entries that explicitly target the retired row-level session/progress/enrollment sync model are kept only as historical root-cause references.

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

15. Windows temp bundle delete after enrollment sync
- Symptom: login enrollment sync fails at cleanup with `PathAccessException: Cannot delete file ... bundle_<course>_*.zip` on Windows.
- Root cause: archive package entries keep lazy `InputFileStream` clones for ZIP raw content; reading entries after the original stream was closed could reopen the temp ZIP and leave entry streams alive until the archive is cleared.
- Prevention: after every `ZipDecoder().decodeBuffer(InputFileStream(...))` path, call `archive.clearSync()` in `finally` after all entry reads finish, and never return lazy `ArchiveFile` objects beyond the archive lifetime. Treat temporary bundle cleanup failures as warnings, not sync failures, after the sync work has completed.

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

23. Student artifact uploads must preserve JSON-text fields as strings
- Symptom: session sync can fail with `Session sync failed: student artifact invalid` even though the local per-KP zip exists and its SHA-256 matches.
- Root cause: the client artifact builder decoded valid JSON text from session/message fields such as `control_state_json`, `evidence_state_json`, and `parsed_json` into nested objects before zipping; the server upload contract unmarshaled those payload fields into Go `string` fields, so object-shaped JSON caused upload-time parse failure.
- Prevention: keep those artifact payload fields as trimmed strings on the local upload/build path, and add regression coverage that rejects non-string JSON-text fields in the fake artifact API so the mismatch is caught before release.

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
- Prevention: keep one shared resolved-prompt path for runtime and Preview/Diff (`student-course override -> student-global override -> course override -> teacher default override -> bundled fallback`), expose the same scopes in UI and sync, reject invalid prompt templates on teacher save and sync apply, and when bundle-level conflicts can be caused by prompt metadata, label them as bundle conflicts and provide an explicit teacher-side "Pull Latest Server" action.

36. Legacy/current prompt bundle metadata created false teacher sync conflicts
- Symptom: teacher sync could still fail with `Teacher bundle sync conflict ... Pull latest server bundle` immediately after a successful pull from server.
- Root cause: semantic bundle hashing treated legacy prompt metadata representation (`_family_teacher/prompt_bundle.json`, `family_teacher_prompt_bundle_v1`) and current representation (`_tutor1on1/prompt_bundle.json`, `tutor1on1_prompt_bundle_v1`) as different, even when the prompt payload itself was semantically identical. Pulling a legacy server bundle therefore wrote one hash to sync state, while the client recomputed a different local hash on the next sync and raised a false conflict.
- Prevention: canonicalize supported prompt metadata entry paths and schema names before semantic hashing, and keep a regression test for `legacy server bundle -> pull -> second sync` so this mismatch cannot silently return.

37. Fresh-device progress sync can re-upload server data on the next normal sync
- Symptom: after a new device downloads progress from server, the next ordinary sync can upload the same progress back from scratch instead of staying download-only.
- Root cause: client progress import wrote only `progress_download` sync state. `progress_upload` state is device-local, so a fresh install kept an empty upload ledger and later treated equal-timestamp imported rows as unsynced local changes.
- Prevention: after importing server progress, stamp both `progress_download` and `progress_upload` state with the imported `updated_at`, and keep a regression test for `force pull -> next normal sync -> no progress upload`.

38. Large sync progress can look frozen even when work is still running
- Symptom: login-time or force-pull sync can appear stuck on one stage, and the blocking overlay may look unresponsive during large session/progress transfers.
- Root cause: the UI only showed coarse stage text or item counts, while some heavy build/import loops could still spend too long in one isolate slice before yielding back to the event loop.
- Prevention: report sync progress as counts plus transferred MB, force-paint stage-start updates once totals are known, and keep heavy session/progress build/import loops yielding so the overlay continues repainting during large sync runs.

39. Sync UI can mislabel enrollment transport failures as session DNS failures
- Symptom: student/teacher home screens can show errors like `Session sync failed: ClientException with SocketException: Failed host lookup...` even when the failing request was actually enrollment `course_bundle` sync and the raw transport text overstates the diagnosis.
- Root cause: the home UI wrapped every home-sync failure with one generic `Session sync failed` prefix, and artifact sync surfaced raw `http` / `SocketException` text directly to the user instead of separating stable UI wording from raw log detail.
- Prevention: keep business-layer stage labels in `HomeSyncCoordinator` (`Enrollment sync failed`, `Session sync failed`), normalize transport exceptions into neutral user messages such as `Could not contact ...`, and store the original transport detail only in logs/debug fields.

40. Teacher login course sync can spend minutes in redundant local bundle preparation
- Symptom: a teacher's login-time enrollment sync can feel extremely slow on Windows even when the network is healthy, especially when multiple remote courses are pulled on a fresh device.
- Root cause: after each downloaded teacher `course_bundle` was already validated, extracted, imported, and semantically verified, the client immediately prepared a fresh upload bundle again just to seed sync state; that forced extra bundle clone/hash I/O on the same hot path on top of the import work.
- Prevention: after a successful teacher download/import, mark sync state with the downloaded remote bundle hash and defer upload-bundle preparation until a later local-change or upload path actually needs it. Keep the semantic post-import materialization check, but do not eagerly build `sync_upload_bundle.zip` during login sync.

41. Startup loading scaffolds can crash before localizations are mounted
- Symptom: app startup can show a blank/white pre-login screen on Windows and Android, especially when cold-start initialization is slow enough to keep the bootstrap loading screen visible.
- Root cause: the bootstrap loading/error scaffolds built their AppBar close action with an outer `BuildContext` that sat above the temporary `MaterialApp`, so `AppLocalizations.of(context)!` was null and threw during the loading frame.
- Prevention: shared UI helpers used in bootstrap/loading/error shells must tolerate missing localizations and provide a safe fallback string. Keep a widget test that builds the startup shell before localizations are mounted and asserts no exception is thrown.

42. Remote course imports rebuilt course artifacts twice on the login hot path
- Symptom: teacher or student login sync could spend excessive time importing remote `course_bundle` artifacts, especially for large courses with many extracted files.
- Root cause: `applyCourseLoad()` already rebuilt cached course artifacts from the extracted folder, but the remote import path immediately called `storeImportedContentBundle()` and rebuilt the same derived artifacts again before computing parity hashes.
- Prevention: remote bundle import should materialize derived course artifacts at most once. When the downloaded canonical bundle just needs to seed cached upload/hash state, copy the bundle into cache and defer chapter/archive derivation instead of rebuilding the same artifact tree twice.

43. Teacher login blocked on full student artifact backfill
- Symptom: teacher login could remain under the sync overlay for many extra minutes after enrollments finished because thousands of `student_kp` artifacts were still being downloaded and applied before the home page became usable.
- Root cause: the blocking login path treated teacher `student_kp` backfill as a required pre-render stage even though the teacher home surface only needed enrollment/course state to render.
- Prevention: keep teacher login's blocking sync limited to the data required for the first home render, and move teacher `student_kp` backfill to an immediate background stage that reuses the same session sync implementation and failure handling.

44. Artifact batch download did one visible-artifact lookup per item before sending any bytes
- Symptom: teacher `student_kp` batch sync could spend an unreasonable amount of time before the first download progress update, even though the total payload size was only a few MB.
- Root cause: server `download-batch` looped over `ReadVisibleArtifact(user_id, artifact_id)` for every artifact and buffered the whole outer ZIP in memory before responding, turning one logical batch into thousands of DB round-trips and a long pre-first-byte stall.
- Prevention: resolve batch visibility with one bulk `artifact_state1_items` query, preserve request order from that result set, and return one stable ZIP response with a known length; do not keep the old per-artifact visibility lookup loop.

45. Desktop first-party API traffic inherited launcher proxy settings
- Symptom: on a desktop launched from a shell with ambient proxy vars, Dennis's `student_kp` sync could take tens of seconds or fail with TLS/handshake truncation even though the same 3.9 MB batch downloaded from the server in about a second when fetched directly on the host.
- Root cause: the app's first-party API clients (`AuthApiService`, `MarketplaceApiService`, `ArtifactSyncApiService`) used default `HttpClient` proxy discovery, so `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY` such as `http://10.211.55.2:7890` silently tunneled `api.tutor1on1.org` traffic through a slow local proxy.
- Prevention: build first-party API `HttpClient`s with `findProxy = (_) => 'DIRECT'` so app login/sync traffic does not inherit launcher-shell proxy env, and verify suspiciously slow downloads by comparing proxied vs `--noproxy '*'` timings on the same machine.

46. Login-time remote course import fully extracted large bundles on the hot path
- Symptom: Dennis teacher login could spend roughly three minutes in enrollment sync on a fresh machine even though only three course bundles were downloaded and the later `student_kp` sync was already down to a few seconds.
- Root cause: remote `course_bundle` import extracted the whole bundle to disk and rebuilt all lecture/question files before preview/import, so the `MATH` bundle's roughly 3900 small files dominated login. On this host that was amplified because `getApplicationDocumentsDirectory()` points at `C:\Mac\Home\Documents`, where small-file extraction is especially slow.
- Prevention: login/import from a lightweight scaffold (`contents.txt` / optional `context.txt`), cache the canonical bundle, and lazily read lecture/question text from the bundle when the scaffold folder lacks those files. Only full materialization for explicit teacher actions that need a writable source folder.

47. Student auth upsert must not erase teacher-owned local student bindings
- Symptom: after a student account logs in on the same machine, teacher home can show `No students` while `Course / Student / Tree` still lists the same students and their trees.
- Root cause: local auth upsert cleared `users.teacher_id` on every login, so authenticated student rows lost the teacher binding used by the teacher-side student list; when remote artifact `state2` still matched, teacher enrollment sync skipped remote changes and never re-derived that local ownership edge.
- Prevention: preserve an existing local student's `teacher_id` during auth upsert, and on teacher enrollment sync refresh / `state2` fast-path re-assert `student_course_assignments -> course_versions.teacher_id` ownership so shared-device student logins cannot strand teacher-side student rows.

48. Artifact cutover/repair must recover progress from session evidence when explicit progress rows are missing
- Symptom: after the server switched to canonical `student_kp` artifacts, some KPs kept session history but lost visible wins/progress on every device.
- Root cause: cutover/rebuild logic only copied legacy progress rows into artifact `progress` payloads and ignored session evidence for KPs that had no explicit progress row, so canonical artifacts were written incomplete.
- Prevention: backup/cutover repair must preserve explicit progress rows and derive missing per-KP progress from durable session evidence before rewriting canonical `student_kp` artifacts; rebuild `state1/state2` only after those repaired artifacts are stored.

49. Prompt metadata sync must validate before clear
- Symptom: a teacher's current prompt can fall back to default after sync even though history still contains older custom prompt rows, and repeated course sync can show duplicate history timestamps.
- Root cause: prompt metadata apply cleared active scope rows before validating downloaded prompt templates, then silently skipped invalid templates; repeated imports of the same teacher-scope prompt from multiple course bundles also inserted duplicate history rows because identical `(scope, content, created_at)` imports were not reused.
- Prevention: validate all prompt metadata before mutating local active rows, fail sync/upload loudly on invalid prompt contracts, and reuse an existing prompt history row when the imported scope/content/timestamp already matches.

50. Teacher fresh-device login can show no students after metadata-only student artifact sync
- Symptom: Dennis could log in on a fresh Android APK and see no teacher-home students or course/student/tree rows even though Windows still showed them.
- Root cause: teacher login wrote `student_kp` artifact hashes into the local manifest without downloading payloads, which kept login fast but did not create local student/course assignment scaffolds. Because the manifest `state2` then matched the server, later sync passes skipped the download path that used to create those scaffolds.
- Prevention: bootstrap teacher-home student/course assignment scaffolds from an explicit teacher active-enrollment API after course metadata is reconciled, including state2-match fast paths. Do not rely on full `student_kp` downloads or optional course-bundle prompt metadata to discover active students.

51. Secure-storage-only auth device keys can exhaust the device limit
- Symptom: the same physical device can appear as multiple registered account devices and quickly trigger the per-account device limit.
- Root cause: the client stored the auth `device_key` only in secure storage. If secure storage was reset or failed across a release/plugin incident, the next login generated a fresh random UUID, so the server counted the same installed app as a new device. The server compounded this by rejecting the 11th device instead of pruning old entries.
- Prevention: back up the non-sensitive `device_key` under application support and restore secure storage from that backup when needed. On the server, when a valid login arrives at the device cap, evict the least-recently-used registered device and revoke its refresh tokens before inserting the new session.

52. Auth device payload can silently fall back to legacy when embedded in an unexported Go type
- Symptom: a login request that sends a flat `device_key` payload can still create/update only the `legacy` device row, hiding the real client device identity from server-side account-device logic.
- Root cause: the auth request structs embedded an unexported `authDevicePayload` type. Fiber `BodyParser` did not populate those promoted fields from the flat JSON body, so `createAuthDeviceSession()` received empty device fields and `normalizeAppUserDeviceSessionInput()` used the `legacy` fallback.
- Prevention: embed an exported reusable auth-device payload type and keep a handler-level parse regression test that posts flat JSON with `device_key`, `device_name`, platform, timezone, and app version.

53. Course KP ordering can regress to lexicographic order
- Symptom: course nodes display or persist as `1.1, 1.10, 1.11, ..., 1.2` instead of logical dotted numeric order.
- Root cause: some course tree paths used plain string comparison or wrote `course_nodes.order_index` from parser map iteration, so multi-digit dotted ids sorted lexicographically.
- Prevention: route course KP ordering through the shared dotted numeric comparator for parser children, UI search/detail lists, and persisted `orderIndex`; keep regression tests with `1.1`, `1.2`, `1.10`, and `1.11`.

54. Teacher tree target student can be assigned too late
- Symptom: from a teacher course/student tree route, tapping a KP can show `No assigned student for this course.` while on-demand student artifact materialization is still pending.
- Root cause: `_teacherStudentId` was set only after awaiting `materializeTeacherArtifactsForView`, so the tap path could run with a null target student even though the route/assignment already identified one.
- Prevention: set the teacher-view target student from the route or assignment before awaiting artifact materialization, and keep a widget regression test where materialization remains pending during a KP tap.

55. App resume can surface transient DNS/socket failures as hard sync failures
- Symptom: Android APK can show `Session sync failed: Could not contact api.tutor1on1.org...` after switching apps, while logging in again later can continue normally.
- Root cause: the home screens kept their 60-second auto-sync timers active across Android lifecycle changes. On resume, a queued timer could immediately run teacher enrollment sync before the device DNS/network stack was ready, and successful later syncs did not clear the stale persistent error message.
- Prevention: stop home auto-sync timers while inactive/paused, restart them only after a short resumed delay, and clear old persistent sync errors after a successful sync. Keep the transport-level fresh-client retry as a secondary guard, not the primary lifecycle fix.

56. Prompt variables must have one registry
- Symptom: teachers could add `{{conversation_history}}` to a prompt and the runtime could render it, but the APK prompt editor rejected the same variable as unsupported and sometimes showed the validation error only after scrolling.
- Root cause: supported prompt variables were duplicated across runtime render values, validator allowlists/required lists, and prompt-editor description text, so the lists drifted.
- Prevention: keep prompt variable names, descriptions, allowed scopes, and required scopes in one registry consumed by runtime, validator, and UI help. Keep regression tests that compare runtime render keys and bundled prompt variables against that registry, and keep prompt-editor validation visible above the editor.

57. LLM streaming transport failures must retry with a fresh streamed request
- Symptom: Android APK student tutor chat can fail with `HandshakeException: Connection terminated during handshake` immediately after tapping `Learn` / `Review` or sending text, while normal network access still works and Windows may not reproduce it.
- Root cause: tutor chat always uses LLM streaming, but the streaming `client.send(request)` path did not share the non-streaming `_sendWithRetry` transport guard. A single transient TLS/socket/timeout failure during the initial streamed send escaped directly to the UI.
- Prevention: route streamed LLM sends through a retry helper that recreates the `http.Request` for the retry, because streamed requests cannot be reused after `send()`. Keep regression coverage that the first streamed send can throw `HandshakeException` and the second request succeeds.

58. Prompt scope rows must not mix append fragments with full overrides
- Symptom: Prompt Settings preview could show a full resolved prompt, while editing a course/student scope opened only an append fragment, making it unclear whether the teacher was editing the base prompt or adding a rule.
- Root cause: the prompt model had two meanings for `prompt_templates.content`: teacher default rows were full prompt overrides, but course/student rows were append fragments that were concatenated at runtime.
- Prevention: treat every active prompt-template row as a full prompt override. Unmodified child scopes should have no row and inherit dynamically from the nearest active parent override; resetting a scope clears its active row. Delete legacy append rows during the schema migration instead of trying to reinterpret them.

59. SQLite UNIQUE constraints do not deduplicate NULL fields
- Symptom: saving the same API config repeatedly could create duplicate rows when TTS/STT model fields were empty.
- Root cause: `api_configs` used a multi-column UNIQUE key that included nullable `tts_model` and `stt_model`; SQLite treats `NULL` values as distinct for UNIQUE checks.
- Prevention: enforce optional-field uniqueness with a normalized expression index using `coalesce(trim(...), '')`, deduplicate existing rows during migration, and make save UI report an existing config instead of always saying it saved.

60. Mutation APIs must not fail because a follow-up list refresh fails
- Symptom: setting course subject labels could show `Failed to update subject labels: course list failed` after the label update endpoint succeeded.
- Root cause: the client POST helper called `listTeacherCourses()` only to build its return value. Any unrelated course-list failure was reported as a failed label update.
- Prevention: mutation helpers should trust the mutation endpoint response and leave broad list refreshes to best-effort UI refresh paths. Keep tests that fail if `updateCourseSubjectLabels` performs a second course-list request.

61. Courses without bundles must not resolve hashes against the storage root
- Symptom: after creating/loading a teacher course such as `Liu_math` but before uploading a bundle, teacher course list and enrollment sync could fail with `course list failed`.
- Root cause: latest-bundle hash resolution ran even when there was no `bundle_versions` row. The empty `oss_path` resolved to the storage root directory, and hash computation failed on the directory.
- Prevention: skip stored bundle hash resolution when `bundle_version_id <= 0` or `oss_path` is empty. Keep a regression test with a real storage service and no bundle version.
