# TODOS
Last updated: 2026-04-01

## P0 Reliability
### Hard Cutover To Artifact-Manifest Sync
Purpose: Replace the current hybrid runtime with a single zip-artifact sync stack. The current system is hybrid because runtime sync still mixes artifact ideas with old row-level session/progress/enrollment logic. The target system is a hard cutover: one artifact-manifest model, one sync path, no compatibility runtime, no dual stack, no hidden fallback, and no silent overwrite.
Cutover rule: Back up production first, convert the authoritative server data once, then delete old tables and old runtime logic entirely. The backup is the only fallback. After cutover, only promoted canonical artifacts and the business records needed to address them remain in runtime use. Retired row-level sync data remains only in backup/restore assets and is no longer a runtime data source.

#### Canonical Model
Purpose: Make sync equality mechanical and auditable instead of interpretation-based.
- Each syncable zip has one stable `artifact_id`.
- Each artifact stores only zip byte `sha256` and `last_modified` as its sync metadata.
- `state1` is the canonical sorted manifest `[(artifact_id, sha256)]`.
- `state2` is `hash(state1)` and is generated only from the canonical manifest.
- `last_modified` is used only for conflict presentation or user context, not for `state2`.
- Missing artifacts are sync changes. They must not be silently restored and must not be silently deleted.
- Conflicts are allowed only at the artifact level. The only valid conflict choices are `keep server`, `overwrite server with local`, and `defer`.

#### V1 Artifact Inventory
Purpose: Remove implementation guesswork by defining exactly which zip files are syncable in the first hard-cutover release.
- The v1 syncable artifact classes are published course bundle zip files and student per-kp zip files.
- Course bundle artifacts are stored by the server bundle storage path `bundles/<bundle_id>/<version>.zip`.
- Student mutable artifacts are per-kp zip files. Each artifact is scoped to one `student + course + kp_key` tuple and is not aggregated by chapter.
- Each student per-kp artifact carries all sessions for that `kp_key` plus the canonical progress state for that same `kp_key`.
- Prompt metadata is part of the course bundle zip and is not a separate sync artifact.
- Local chapter zip files, extracted course folders, temporary upload bundles, and any other rebuild/cache outputs are derived local artifacts and are not syncable artifacts.
- Student and teacher manifests are different filtered views over the same canonical server artifact set.
- Enrollment/publication records may decide which bundle artifacts appear in a user's manifest, and session ownership records may decide which per-kp student artifacts appear in a user's manifest, but those business records are not themselves sync artifacts.
- Teacher uploads course bundle artifacts. Students upload their own per-kp session/progress artifacts. Conflict resolution is artifact-class-specific but is always explicit.

#### Remote Data Fate
Purpose: State exactly which existing remote data survives as part of the new runtime and which data is retired into backup only.
- Promote existing server course bundle zip assets, plus convert existing row-level student session/progress data into canonical per-kp student artifacts in the new artifact-manifest runtime.
- Retire old row-level sync data to backup only, including `session_text_sync`, `progress_sync`, `progress_sync_chunks`, `progress_sync_audit`, `sync_download_state_items`, `sync_download_state2`, `teacher_course_sync_state1_items`, `teacher_course_sync_state2`, `student_enrollment_sync_state1_items`, and `student_enrollment_sync_state2`.
- Retire old row-level sync APIs, old row-level cursors, old secure-storage compatibility records, old sync item-state metadata, and old read-time backfill/rebuild logic to backup/history only.

#### State Generation Rules
Purpose: Keep `state2` cheap and reliable by updating it only when the artifact set changes, never by rescanning business rows or rebuilding folders on read.
- Server conversion generates the first full authoritative `state1`, then persists authoritative `state2`.
- Server recomputes `state1/state2` immediately after every successful server-side artifact mutation: accepted upload, explicit delete, or confirmed `overwrite server with local`.
- Server sync read calls do not rebuild state. They only read the persisted artifact manifest and aggregate.
- Client generates the first local `state1/state2` immediately after the initial full pull from the converted authoritative server artifact set.
- Client recomputes local `state1/state2` immediately after every successful local artifact mutation: local zip create/replace, downloaded artifact applied, confirmed overwrite upload success, or explicit local delete.
- Client login does not rescan business tables, session rows, progress rows, or folders. Login only reads local persisted `state2` and compares it with server `state2`.
- If out-of-band zip edits are supported, they must use an explicit artifact reindex action. Normal sync must not hide a filesystem scan.

#### Shared Sync Path
Purpose: Ensure teacher and student use one sync engine instead of keeping two approximate compare/download implementations alive.
- Teacher and student must use the same artifact-manifest sync pipeline: `compare state2 -> fetch state1 -> diff by artifact_id -> transfer changed artifacts -> verify hash parity`.
- Teacher and student are allowed to differ only in data sources, permissions, artifact classes, or post-transfer side effects. In v1, teacher upload targets course bundle artifacts and student upload targets per-kp student artifacts.
- Teacher and student must not keep separate row-level equality logic, separate fallback logic, or separate compare/download topology.

#### Mandatory Deletion Scope
Purpose: Prevent the old hybrid runtime from surviving inside the new system.
- Delete old client sync services for row-level session/progress/enrollment compare/download flows.
- Delete old server APIs for row-level sync rather than merely disabling them.
- Delete old server tables that exist only for the retired row-level sync model after production backup and successful conversion.
- Delete old local metadata, item-state tables, cursors, secure-storage compatibility records, and background task state used only by the retired sync model.
- Delete old tests that only validate the retired row-level sync model. Replace them with artifact-sync tests instead of patching them.
- Delete fallback hash paths, weak hash paths, envelope-derived hash paths, legacy backfill readers, legacy ETag readers, and legacy cursor readers.
- Delete read-time rebuild logic. Sync reads may only read persisted artifact manifest/state data.
- Delete folder-based or business-row-based artifact reconstruction from the normal sync path.

#### Executable Cutover Checklist
Purpose: Convert the plan from broad direction into a strict implementation order.
- Step 1: Freeze the sync scope to zip artifacts only and reject any new work that extends row-level sync.
- Step 2: Define the stable `artifact_id` scheme and canonical manifest serialization order.
- Step 3: Create the new server artifact tables and make them the only authoritative runtime source for `state1/state2`.
- Step 4: Create the new server APIs: `get_state2`, `get_state1`, `download_artifacts(diff_ids)`, and `upload_artifacts(diff_ids)`.
- Step 5: Make server upload persist the uploaded zip as the canonical artifact directly, without repacking, metadata rewriting, or business-row rebuild.
- Step 6: Make server upload return explicit artifact-level conflicts and never auto-resolve by timestamp.
- Step 7: Write the one-time server conversion script that imports existing server course bundle zip assets and converts existing row-level student session/progress data into per-kp student artifacts before generating the first authoritative `state1/state2`.
- Step 8: Verify the production backup, run the conversion once, validate the converted manifest, and keep the backup as the only restore path.
- Step 9: Delete old server sync code paths, old server sync APIs, and old sync-only tables instead of leaving them dormant.
- Step 10: Add the new client artifact store and make it the only local runtime source for `state1/state2`.
- Step 11: On the first launch of the new client version, wipe old local sync state and old row-level local data, treat the client as a brand-new node, and pull the full authoritative server artifact set.
- Step 12: Implement the shared client sync pipeline once and route both teacher and student through it.
- Step 13: On download, verify the downloaded zip byte hash before replacing the local artifact and before updating local `state1/state2`.
- Step 14: On upload, verify the local zip byte hash before upload, upload only changed artifacts, then refresh the local manifest from the authoritative server response.
- Step 15: Implement explicit conflict UI for both download and upload conflicts with `keep server`, `overwrite server with local`, and `defer`.
- Step 16: Implement explicit delete propagation as artifact diff, not as silent restore or silent delete.
- Step 17: Delete old client services, background tasks, metadata caches, migration reads, and tests that exist only for the retired hybrid runtime.

#### Migration Rules
Purpose: Make the new client/server cutover behavior explicit and non-ambiguous.
- The first new-version client startup clears old local sync state and old local row-level sync data before building the new local artifact manifest.
- The first new-version client startup pulls the full authoritative server artifact set and establishes the first local `state1/state2`.
- Hard cutover allows dropping old unsynced local row-level data. The new runtime does not attempt to migrate or preserve local-only row-level sync data.
- If pre-cutover export or backup is required for local-only data, it must happen before release or before first startup of the new version. It must not be implemented as a runtime compatibility layer.
- Old remote data is preserved only in production backup artifacts and restore procedures. It is not read by the new runtime after cutover.
- Interrupted rollout must be treated as an ops event: either complete the cutover or restore from backup. Do not run old and new sync together.

#### Acceptance And Ops Gates
Purpose: Refuse release until the hard cutover is proven by real artifact behavior and operational safety.
- Gate 1: Cutover test proves a new-version client can perform the expected initial full artifact download from the converted server.
- Gate 2: Fast-path test proves `login -> sync -> logout -> login` performs zero uploads and zero downloads on the second login.
- Gate 3: Single-change download test proves one changed server artifact transfers exactly one artifact.
- Gate 4: Single-change upload test proves one changed local artifact transfers exactly one artifact.
- Gate 4a: Student upload gate proves a single changed `student + course + kp_key` scope transfers exactly one per-kp artifact and does not aggregate by chapter.
- Gate 5: Conflict gate proves artifact conflicts block on user choice and do not mark sync clean before the decision.
- Gate 6: Delete gate proves artifact deletion propagates correctly without silent restore or silent delete.
- Gate 7: Migration gate proves production backup verification, conversion success, restore drill, and interrupted-rollout handling.
- Gate 8: Production signoff proves a real account hits zero artifact transfer on the second login after cutover.
- Gate 9: Negative gate proves release artifacts no longer expose old row-level sync APIs, old backfill readers, old runtime compatibility paths, or old row-level compare/download code paths.

#### Do Not Do
Purpose: Keep the implementation from drifting back into hybrid behavior.
- Do not keep dormant old APIs, old tables, or old runtime compatibility flags "just in case".
- Do not keep any row-level equality logic in the runtime sync path.
- Do not keep read-time backfill, read-time rebuild, or read-time state repair inside normal sync.
- Do not auto-resolve conflicts by timestamp, silent overwrite, or silent skip.
- Do not rebuild zip artifacts from folders or business rows inside the sync hot path.

## P1 Product completion
- None currently.

## P2 Security and operations
- None currently.

## P3 Quality engineering
- None currently.
