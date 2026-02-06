# family_teacher

## Overview
Flutter app for a "family teacher" MVP with LLM-backed tutoring, skill trees, and student progress tracking. The app is role-based and persists learning state locally.

## Roles And UX
- Admin: manage teacher accounts.
- Teacher: create students, load courses, assign courses, manage prompt templates, review logs.
- Student: view assigned courses, browse the skill tree, start or continue tutoring sessions, review summaries.

## Core Functionality
- Course ingestion from a folder containing `contents.txt` or `context.txt`, parsed into a skill tree with knowledge point IDs and titles.
- Lecture and question bank files per knowledge point, appended to prompts when needed.
- Tutoring sessions with chat history, learn/review actions, and summary updates.
- Prompt templates layered by system prompt plus optional teacher, course, and student overrides.
- LLM call logging and replay modes to support debugging and deterministic runs.
- Optional STT/TTS with audio logging and playback controls.

## App And LLM Logical Flow
The app is a deterministic orchestration layer. It prepares context, renders prompts, and persists state. The LLM provides the instructional content and structured outputs that drive mastery updates.

1. App startup initializes `AppServices`, loads settings, and opens the Drift database.
2. The user authenticates and lands on a role-specific home page.
3. Teachers load course folders and assign courses. Students open a course and pick a knowledge point from the skill tree.
4. Starting a session stores the user message, builds conversation history, and selects a prompt (`learn`, `review`, or `summarize`) with optional prompt template overrides.
5. `SessionService` renders the prompt, appends lecture or question bank content when applicable, trims history to fit token limits, and calls `LlmService`.
6. `LlmService` selects provider and model from settings (or a per-session override), executes the request or replays a recorded response, and logs the call.
7. Responses are stored as chat messages. Streaming updates the assistant message incrementally and can drive TTS playback.
8. Summary actions validate JSON against a schema, persist the summary, and update per-knowledge-point progress, which feeds future question difficulty.

## Data And Storage
Local persistence via Drift/SQLite in the app documents directory.
- Users, roles, and assignments.
- Course versions, skill tree nodes, and edges.
- Chat sessions, chat messages, and session summaries.
- Progress entries with lit percent and question level.
- LLM call logs, settings, API configs, and prompt templates.

## Prompt And LLM Infrastructure
- System prompts are loaded from `assets/prompts/<name>.txt` and merged with optional append templates.
- Prompt variables are rendered via simple `{{variable}}` substitution.
- JSON schema validation is applied to summarization responses.
- LLM modes include live, live-with-recording, and replay.

## Platform Notes
- Desktop-specific behavior is guarded by `Platform.isWindows`, but desktop deps remain in `pubspec.yaml`.
- Android scaffold exists; build validation is required to confirm compatibility.

## Project References
- Known issues and build failures: `BUGS.md`.
- Architecture TODOs and prompt-driven requirements: `TODOS.md`.
- Prompt system architecture reference: `assets/prompts/codex_architecture.md`.
