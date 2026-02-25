# Plans - Remote Teacher Hosting + Student Marketplace (Consolidated)

Date: 2026-02-25

## Goal
Enable teachers to host course data remotely (courses, questions, prompts, assets) with full control over visibility and updates. Students can browse a marketplace of public teachers/courses, request enrollment, and become a student of the teacher upon approval. Student sessions and progress are uploaded so teachers can view progress.

## Key Decisions (MVP)
- Hosting: AliCloud Hong Kong (no ICP requirement).
- Access: HTTPS only, no raw public IP usage.
- Upload/Download: manual triggers in app (teacher upload bundle; students download on demand).
- Content privacy: End-to-end encrypted (E2EE) for session content. Server stores only minimal metadata.
- Course distribution: OSS private bucket + signed URLs.
- Teacher approval required before student downloads.

## Architecture (High-Level)
- ECS VM for API service + reverse proxy with TLS.
- RDS (MySQL or PostgreSQL) for metadata, enrollments, and sync cursors.
- OSS for bundles/assets.
- Optional CDN/ESA later for download acceleration.

## Data Flow Summary
1) Teacher publishes course -> uploads bundle to OSS -> metadata stored in RDS.
2) Student browses marketplace -> requests enrollment.
3) Teacher approves -> student can download bundle via signed URL.
4) Student session/progress is encrypted and uploaded as events -> teacher can decrypt and view.

## Course Bundle Format
- Zip archive containing:
  - manifest.json (bundle version, hashes, course_id, created_at)
  - course.sqlite (read-only course DB)
  - assets/ (optional)

## E2EE Sync (MVP)
- Each session/progress update is an encrypted event.
- Server stores:
  - event_id, sender_user_id, sender_device_id, recipient_user_id
  - event_type (UPSERT/DELETE), course_id, conversation_id
  - created_at, payload_size
- Encrypted payload contains message text, summary, progress details.
- Teacher is a recipient and can decrypt to view progress.
- Retention: 365 days for encrypted events; delete on user request with tombstones.

## Server Data Model (Draft)
- TeacherAccount: id, display_name, bio, avatar_url, contact, status
- TeacherDataBundle: id, teacher_id, version, hash, created_at, oss_path
- CourseCatalogEntry: id, teacher_id, course_version_id, subject, grade, description, visibility
- EnrollmentRequest: id, student_id, teacher_id, course_catalog_id, status, message
- Enrollment: id, student_id, teacher_id, course_version_id, assigned_at, active
- Event: id, sender_user_id, recipient_user_id, event_type, course_id, conversation_id, created_at, payload_size, ciphertext
- AckState: recipient_user_id, sender_device_id, ack_seq

## Client Data Model (Local)
- RemoteTeacherProfiles: id, display_name, bio, avatar_url, last_synced_at
- RemoteCourseCatalog: id, teacher_id, subject, grade, description, visibility
- EnrollmentRequests: id, course_catalog_id, status, message
- SyncState: last_pull_at, last_push_at, last_error, bundle_version

## API Surface (Draft)
- Auth
  - POST /auth/login
  - POST /auth/refresh
- Teacher
  - GET /teachers/me
  - PATCH /teachers/me
- Bundles
  - POST /teacher/bundles
  - GET /teacher/bundles/latest
  - GET /teacher/bundles/:version
- Catalog
  - GET /catalog/teachers
  - GET /catalog/courses?teacher_id=&subject=&grade=&q=
- Enrollment
  - POST /enrollments/requests
  - GET /enrollments/requests (teacher view)
  - PATCH /enrollments/requests/:id
  - GET /enrollments (student view)
- Sync (E2EE)
  - POST /sync/events
  - GET /sync/events?since_seq=
  - POST /sync/ack

## UI/UX Flow
- Teacher
  - Profile + publish/unpublish courses
  - Manual upload bundle
  - Enrollment inbox
  - Student progress view (decrypts E2EE content)
- Student
  - Marketplace browse/search
  - Enrollment request + status
  - Download after approval

## Milestones
1) Foundations: server skeleton, auth, OSS, RDS.
2) Teacher upload/download: bundle export/import, signed URLs.
3) Marketplace browse (read-only).
4) Enrollment workflow (approve/reject).
5) E2EE sync + teacher progress view.
6) Hardening: retries, logging, admin tools.

## Open Questions
- E2EE key management (device keys, teacher sharing).
- Bundle size limits and incremental updates.
- Rate limits and pagination.

