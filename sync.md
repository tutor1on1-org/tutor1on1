# Sync Contract

This file defines the expected sync behavior for Tutor1on1 and the design
requirements that all sync changes must follow.

## Goals

- Keep cross-device/server sync correct, deterministic, and explainable.
- Make login-time sync fast enough that first-use and relogin do not feel hung.
- Keep teacher and student sync behavior shared wherever the rules are meant to
  match.
- Separate canonical sync equality from local derived/cache state.

## Canonical model

- Zip-artifact manifest sync is the only active sync model.
- Canonical equality is the persisted artifact manifest only:
  - `state1 = sorted artifact list`
  - `state2 = hash(state1)`
- Row-level session/progress/enrollment payload sync is retired and must not be
  reintroduced as the source of truth.

## Shared flow requirements

- Teacher and student sync must pass through one shared
  `state2 -> state1 -> diff -> transfer changed artifacts -> parity verify`
  flow whenever the semantics are meant to match.
- Role-specific differences must be limited to:
  - which artifacts are visible,
  - which local changes are uploadable,
  - role-specific side effects after import.
- Do not keep near-duplicate teacher/student compare/download flows when one
  shared path can express the rule.

## Login-time behavior

- Startup before login must never depend on sync data being present or valid.
- Pre-login screens must stay usable even on a fresh device with no local cache.
- Login must not perform heavy bundle rebuild/hash work before the user can see
  progress.
- The first blocking sync after login must:
  - show deterministic stage progress,
  - prevent conflicting actions while running,
  - finish in bounded time for a normal teacher/student account.

## Expected teacher sync behavior

- Teacher login sync checks remote `course_bundle` manifest state, downloads only
  changed remote bundles, imports them, and records synced state.
- Teacher login must not block the first teacher home render on a full
  `student_kp` backfill when that data is not required to render the home
  surface.
- A clean teacher login must not eagerly prepare a fresh upload bundle for every
  downloaded course just to seed sync state.
- Teacher upload preparation is deferred until there is an actual local change
  or upload path that needs it.
- Teacher `student_kp` sync may continue immediately in background after the
  blocking login path finishes, but it must reuse the same session sync logic
  and failure handling as the normal session sync stage.
- Teacher sync conflicts must describe bundle truth, not only course text.

## Expected student sync behavior

- Student login sync downloads only missing/stale `course_bundle` and
  `student_kp` artifacts.
- Fresh-device downloads must stamp enough local sync state that the next normal
  sync stays clean and does not re-upload server data.
- Student artifact imports must not race with local artifact refresh/rebuild.

## Performance requirements

- Normal sync read paths must not rescan business rows or rebuild bundles on the
  hot path.
- Large decode/hash/ZIP work must not monopolize the UI isolate during login or
  timer sync.
- Artifact downloads/imports must checkpoint in batches instead of rewriting
  manifests/state per item.
- Batch transport must be used when many `student_kp` artifacts are needed.
- A clean second sync should be near-no-op after the `state2` check.

## UX and failure requirements

- Sync errors shown to users must be stable business-layer messages.
- Raw transport/protocol details belong in logs, not primary user messages.
- Startup/loading/error shells must not assume localized context is already
  mounted.
- Sync progress must report real stage transitions and, where useful, counts or
  bytes.

## Data ownership rules

- Sync state is not a cache for arbitrary derived values.
- Local caches/artifacts may be deleted and rebuilt without changing canonical
  server truth.
- Placeholder or weak local links must never be trusted as if they were strong
  remote identity/bundle matches.

## Recovery rules

- Deleting local DB/cache must produce a clean boot and a usable pre-login UI.
- Force-pull flows must reuse shared logic rather than special-case recovery
  paths per page.
- If a fix relies on deleting local state to hide a symptom, that is not a root
  fix.

## Review checklist for sync changes

- Does this change preserve the `state2 -> state1 -> diff -> transfer ->
  parity` contract?
- Does it keep teacher/student behavior shared where the semantics match?
- Does it avoid hidden bundle rebuild/hash work on login/read hot paths?
- Does a fresh-device second sync stay clean?
- Does the user see stable progress and stable error wording?
