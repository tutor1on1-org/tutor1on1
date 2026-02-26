# family_teacher

## Overview
Family Teacher is a Flutter desktop app with a Go remote backend for teacher-managed courses and LLM tutoring.

## Current roles
- Teacher: manage local course versions, upload course bundles to marketplace, review enrollment requests, review student progress.
- Student: browse public marketplace, apply for enrollment, download approved courses, learn/review with tutor sessions.

## Key flows
1. Teacher loads/reloads a course version locally.
2. Teacher uploads bundle to marketplace (bundle version tracked by `version_id`).
3. Student requests enrollment for a public course.
4. Teacher approves request.
5. Student downloads approved bundle and imports it locally.
6. Student session text/progress syncs via E2EE events; teacher can view synced progress.

## Core code areas
- `lib/`: Flutter app (UI, services, Drift DB, auth/session logic).
- `remote/`: Go API (auth, catalog, enrollment, bundle upload/download, sync).
- `assets/`: prompts, schemas, course assets.

## Supporting docs
- `AGENTS.md`: active memory and guardrails.
- `TODOS.md`: prioritized next tasks.
- `PLANS.md`: roadmap.
- `WORKLOG.md`: operational runbook.
- `LOGBOOK.md`: historical archive.
