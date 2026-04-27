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
- Canonical public client release procedure: run `scripts/release_public.ps1`; it validates, stages/commits/pushes when needed, publishes `Tutor1on1.apk`, publishes `Tutor1on1.zip`, and refreshes GitHub Release assets. Website publishing is opt-in with `-PublishWebsite`. Use that script instead of ad-hoc release steps.
- After a sync-model pivot, treat `TODOS.md` as the roadmap source of truth and align or explicitly historical-mark the active reference docs (`README.md`, `PLANS.md`, `PUBLIC_CLIENT_README.md`, `LEGAL/*`, `WORKLOG.md`) in the same turn; do not leave retired architecture claims in active docs.
- Public web links should use `www.tutor1on1.org` for site pages and `api.tutor1on1.org/downloads/` for downloadable artifacts; do not publish raw IP URLs.
- Website localization keeps English at `/`, Simplified Chinese at `/zh/`, and other locales under `/<locale>/` static paths; keep detection, explicit-locale path handling, and dropdown switching centralized in `/site.js` instead of duplicating per-page logic.
- Public macOS downloads must stay off the website until there is a runnable Release build. When macOS is ready, publish only a signed `Developer ID Application` build with Hardened Runtime and notarization; do not publish raw `flutter build macos` output.
- Course KP ordering must use dotted numeric comparison, not plain string comparison; keep parser, UI, and persisted `orderIndex` ordering aligned.
- Approval email rule: backend moderation/enrollment request creation should notify the responsible approver by email, and approve/reject decisions should notify the applicant with a one-sentence email when SMTP is enabled.
- Exit and logout final sync must stay on the same `AppQuitFlow._runFinalSync` path, and forced final sync must wait for any active background sync before uploading local session artifacts.
- Marketplace course descriptions are live course metadata: update `courses.description` through a teacher-owned metadata endpoint and refresh course lists; catalog marketplace cards/search already consume `description`.
- API model lists must have one local source of truth: successful `Test API key` calls cache `/models` by normalized `baseUrl + apiKeyHash`, and all settings/session model pickers should read that cache before falling back to static provider defaults.
- Public website redesigns should make the product visible in the first viewport, keep direct Windows/Android downloads prominent, and derive release labels/download links from `/site.js` release config rather than hard-coding per page.
- Public legal website pages must not copy internal placeholder legal drafts verbatim; use the current public contact address, distinguish app code license, third-party licenses, and teacher-owned course content, and validate legal paths in `scripts/publish_website_static.ps1`.
- Website publish HTTP checks should retry non-200 responses explicitly after rsync, because nginx/static path visibility can briefly lag even when the file already exists on the remote host.
