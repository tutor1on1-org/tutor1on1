# Tutor1on1 Docs Index

`AGENTS.md` is the entry point only. Only keep it as a reference to the other documents:

- `README.md` - project description, logical flow, architecture, and final aim.
- `WORKFLOW.md` - standard way to execute work from diagnosis to release.
- `SCRIPTS.md` - commands for setup, tests, validation, and builds.
- `BUGS.md` - durable lessons learned and active bug watch items.
- `TODOS.md` - prioritized backlog.
- `LOGBOOK.md` - historical operations timeline.
- `WORKLOG.md` - active remote runbook and host details.
- `PLANS.md` - phased roadmap.
- `DONEs.md` - recent completed items.
- `.env.example` - sanitized local secrets template (`.env` is local and untracked).
- `BACKUP_DRILL.md` - backup restore verification drill and incident checklist.
- `LESSONS.md` - durable cross-session lessons and operating rules.

## Local skills
- `skills/windows_release_publish/SKILL.md` - build Windows release, package `Tutor1on1.zip`, upload to server, remove old versioned ZIP artifacts, and verify public download URL/hash.

## Experience updates
- Canonical experience log moved to `LESSONS.md` to keep AGENTS concise and always-injected context small.
- Sync policy reminder: no fallback during sync/error recovery, and the server copy is the only canonical version. If local sync data disagrees, wipe local state and rebuild from the server instead of trying to preserve both copies.
- App-change handoff discipline is defined in `WORKFLOW.md` and `LESSONS.md`: self-battle, build, validate, update memory, push, and publish/upload the remote release unless the user explicitly skips a step.
- Canonical public client release procedure: run `scripts/release_public.ps1`; it validates, stages/commits/pushes when needed, publishes `Tutor1on1.apk`, publishes `Tutor1on1.zip`, then syncs the website. Use that script instead of ad-hoc release steps.
- After a sync-model pivot, treat `TODOS.md` as the roadmap source of truth and align or explicitly historical-mark the active reference docs (`README.md`, `PLANS.md`, `PUBLIC_CLIENT_README.md`, `LEGAL/*`, `WORKLOG.md`) in the same turn; do not leave retired architecture claims in active docs.
- Public web links should use `www.tutor1on1.org` for site pages and `api.tutor1on1.org/downloads/` for downloadable artifacts; do not publish raw IP URLs.
- Website localization keeps English at `/`, Simplified Chinese at `/zh/`, and other locales under `/<locale>/` static paths; keep detection, explicit-locale path handling, and dropdown switching centralized in `/site.js` instead of duplicating per-page logic.
- Public macOS downloads must stay off the website until there is a runnable Release build. When macOS is ready, publish only a signed `Developer ID Application` build with Hardened Runtime and notarization; do not publish raw `flutter build macos` output.
- Course KP ordering must use dotted numeric comparison, not plain string comparison; keep parser, UI, and persisted `orderIndex` ordering aligned.
