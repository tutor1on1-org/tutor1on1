# family_teacher Docs Index

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
- `skills/windows_release_publish/SKILL.md` - build Windows release, package `family_teacher.zip`, upload to server, remove old versioned ZIP artifacts, and verify public download URL/hash.

## Experience updates
- Canonical experience log moved to `LESSONS.md` to keep AGENTS concise and always-injected context small.
- App-change handoff discipline is defined in `WORKFLOW.md` and `LESSONS.md`: self-review, build, validate, update memory, push, and publish unless the user explicitly skips a step.
