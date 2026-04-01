# TODOS
Last updated: 2026-04-01

## P0 Reliability
### Zip Artifact Sync Cutover
Purpose: Replace the current row-level sync system with a single zip-artifact sync model that has one source of truth, no fallback, no silent overwrite, and no backward compatibility path.
Desired outcome: The server and client only track the same set of zip artifacts. `state1` is the canonical sorted `[(artifact_id, sha256)]` manifest, `state2` is `hash(state1)`, and sync is always `compare state2 -> fetch state1 -> diff by artifact_id -> transfer changed zips only -> parity verify`.
Cutover rule: Back up server data first, then delete old tables and old sync logic entirely. The backup is the only fallback. Do not leave any legacy table, fallback hash path, compatibility flag, or hidden recovery branch in the runtime code.

#### State Generation Rules
Purpose: Keep `state2` cheap and reliable by generating it only from the persisted artifact manifest, never by scanning business data or rebuilding folders on the hot path.
- Server conversion builds the first full canonical `state1` from the server artifact store, then generates and persists `state2`.
- Server recomputes `state1/state2` immediately after every successful server-side artifact mutation: upload success, explicit delete, or a confirmed "overwrite server with local" conflict decision.
- Server does not recompute `state1/state2` during login, download, or sync read calls. Sync reads only the already-persisted manifest and aggregate.
- Client builds the first local `state1/state2` immediately after the initial full download from the new authoritative server manifest.
- Client recomputes local `state1/state2` immediately after every successful local artifact mutation: local zip create/replace, downloaded zip applied, confirmed overwrite upload success, or explicit local delete.
- Client login does not rescan business rows or rebuild bundles. Login only reads the persisted local `state2` and compares it to the server `state2`.
- If out-of-band zip edits are allowed, they must go through an explicit local artifact reindex action. Do not hide a full filesystem/business-data rescan inside normal sync.

#### Implementation Steps
Purpose: Execute the cutover in a strict order that prevents old and new sync models from coexisting.
- Freeze the sync scope to zip artifacts only. Delete the assumption that business rows, folder trees, or derived payloads can participate in canonical sync equality.
- Define a stable `artifact_id` for every syncable zip and store the zip byte `sha256` plus `last_modified`. Use `last_modified` only for conflict decisions, not for `state2`.
- Add the new server artifact manifest tables and make them the only source for `state1/state2`.
- Add new server APIs for `get_state2`, `get_state1`, `download_artifacts(diff_ids)`, and `upload_artifacts(diff_ids)`.
- Make server upload store the uploaded zip as the canonical artifact without rebuilding, repacking, or rewriting metadata after upload.
- Make server upload return conflict details when the same `artifact_id` changed on both sides so the client must ask the user whether to keep the server version, overwrite the server, or defer.
- Write the one-time server conversion script that converts existing server zip assets into the new artifact manifest and generates the first authoritative `state1/state2`.
- Take a verified production backup before conversion, run conversion once, then delete old sync tables and old sync endpoints instead of leaving them dormant.
- Remove old server code paths for session/progress/enrollment sync, fallback hash generation, manifest drift repair, folder rebuild sync, and any other runtime compatibility branch.
- Add the new client artifact store and make it the only local source for `state1/state2`.
- On first launch of the new client version, wipe old local sync state and old row-level sync data, treat the client as brand new, and pull the authoritative server artifact set.
- Implement the shared client sync flow as `compare state2 -> fetch state1 -> diff by artifact_id -> transfer changed zips only -> recompute local zip hash -> require parity`.
- On download, verify the downloaded zip byte hash equals the server-declared hash before replacing the local artifact and before updating local `state1/state2`.
- On upload, verify the local zip byte hash before upload, upload only changed artifacts, then replace local manifest values with the authoritative server response.
- Add explicit conflict UI for both download and upload conflicts with the options "keep server", "overwrite server with local", and "defer". Never perform a silent overwrite.
- Add explicit delete handling as part of artifact diffing. Missing artifacts are sync changes and must never be silently restored or silently deleted.
- Delete old client services, background tasks, fallback state tables, and tests that exist only for the old row-level sync model.

#### Acceptance Gates
Purpose: Refuse release until the artifact sync model is proven by real behavior, not by theory.
- First-login cutover test: a new client version against the converted server performs the expected initial full download and establishes local `state1/state2`.
- Fast-path test: login -> sync -> logout -> login must produce zero uploads and zero downloads on the second login.
- Server-change test: if exactly one server zip changes, the client downloads exactly one zip.
- Client-change test: if exactly one local zip changes, the client uploads exactly one zip.
- Conflict test: if the same `artifact_id` changes on both sides, sync must block on user choice and must not mark `state2` as clean before the decision.
- Upload-conflict test: choosing "overwrite server with local" must update only that artifact, refresh the server manifest, and produce a clean second sync.
- Production signoff: after deployment, verify with a real account that the second login sync transfers zero artifacts. Any "success" log with repeated transfers is a release failure.

## P1 Product completion
- None currently.

## P2 Security and operations
- None currently.

## P3 Quality engineering
- None currently.
