Codex TODOs - Remote Teacher Hosting + Student Marketplace (MVP, HK)

Date: 2026-02-25
Hosting: AliCloud HK (single-node API), OSS (private) + CDN/ESA
Core constraints: minimal ops, minimal logging, E2EE content, plaintext metadata headers only

========================================
PHASE 0 - Decisions (blockers)
========================================
0.1 Choose DB engine: MySQL
0.2 Pick domain + TLS strategy (reverse proxy + HTTPS 443 only)
0.3 Pick CDN/ESA strategy for OSS downloads (signed URLs / private access)
0.4 Finalize retention constants:
    - Encrypted sync events retention: 365 days rolling
    - Offline delivery queue TTL: 7 days
    - DB backups: daily, rolling 30 days
    - Max encrypted payload size: 200KB
0.5 Confirm key product rules:
    - Enrollment approval is PER-COURSE (teacher must approve before download)
    - Deletions are irreversible and must propagate to all devices incl. teacher
    - No export feature
0.6 TURN strategy:
    - Use coturn + time-limited credentials
    - No persistent TURN logs
    - Ports plan (prefer TLS on 443 to maximize connectivity)

========================================
PHASE 1 - Server Foundations (API + Storage + Admin)
========================================
1.1 Create server repo, REST framework, config, migrations, env management
1.2 Auth & account management
    - Register/login/refresh/revoke
    - Password reset via email (anti-enumeration + rate limits)
    - Account deletion: immediate disable + cascade delete (subject to backup rotation)
1.3 Core DB schema + migrations
    - users, devices
    - teachers, teacher_profiles
    - courses, course_catalog_entries
    - bundles, bundle_versions
    - enrollment_requests (per-course), enrollments (per-course)
    - marketplace_reports
    - e2ee_events (headers + ciphertext pointer/blob)
    - ack_state (per recipient, per sender_device)
    - offline_queue (encrypted payloads, TTL)
1.4 OSS integration
    - Private buckets
    - Server issues short-lived signed URLs:
      - direct upload (PUT) for teacher bundles
      - direct download (GET) for students (only if approved)
1.5 Marketplace moderation minimal tooling
    - Report endpoint (marketplace only)
    - Minimal admin list page or CLI to review/disable listings and suspend accounts
1.6 Retention jobs (cron/worker)
    - Expire offline_queue after 7 days
    - Expire events older than 365 days (and keep tombstones within retention)
1.7 Reverse proxy + security baseline
    - HTTPS 443 only
    - basic rate limits (login/reset/catalog/event APIs)
    - minimal logs (no request bodies; no secrets)

========================================
PHASE 2 - Course Bundles (Teacher upload / publish, Student download)
========================================
2.1 Define bundle format (v1)
    - bundle.zip:
      - manifest.json (course_id, bundle_version, hash, created_at, schema_version)
      - course.sqlite (read-only course DB)
      - assets/ (optional; currently text-only so can be empty)
2.2 Teacher bundle upload flow
    - Teacher requests upload slot -> server returns signed OSS PUT URL
    - Teacher uploads zip to OSS
    - Teacher calls finalize -> server validates hash + stores bundle metadata
2.3 Publish/unpublish flow
    - CourseCatalogEntry visibility: public/unlisted/private (catalog visibility)
    - Note: download is still gated by per-course enrollment approval
2.4 Student download flow
    - Student requests download -> server checks enrollment approved -> returns signed OSS GET URL
2.5 CDN/ESA caching for bundles
    - Ensure signed URL strategy works with CDN (or use origin auth/private distribution)

========================================
PHASE 3 - Marketplace + Enrollment (per-course approval)
========================================
3.1 Catalog read APIs
    - List teachers
    - List/search courses with filters (q/subject/grade/teacher)
    - Course detail
3.2 Enrollment APIs (per-course)
    - Student: create enrollment request (+message)
    - Teacher: list pending requests
    - Teacher: approve/reject
    - Student: list request status + enrollments
3.3 Teacher profile publishing controls
    - Teacher can optionally publish contact details
    - Require explicit checkbox consent when saving/publishing contact details
3.4 Abuse report flow (marketplace only)
    - report listing/teacher
    - admin action: hide listing / suspend account

========================================
PHASE 4 - E2EE Sync (Messages + Progress, multi-device, deletions)
========================================
4.1 Define sync event model (v1)
    - Event types: UPSERT, DELETE
    - DELETE is tombstone; irreversible
    - Plaintext header fields:
      event_id, event_type, course_id, conversation_id,
      sender_user_id, sender_device_id, recipient_user_id,
      seq, created_at, payload_size
    - Payload: ciphertext (<=200KB)
4.2 Device management
    - Each device has device_id + public key
    - Device registration on login
    - New device join flow (works with email reset approach)
4.3 Server sync APIs
    - POST /events/ingest (validate header size + store ciphertext)
    - GET /events/pull (by recipient, cursor per sender_device; pagination)
    - POST /ack (update ack_state)
4.4 Offline delivery queue (store-and-forward)
    - If recipient offline or P2P fails, store encrypted payload in offline_queue
    - Pull on recipient online; TTL 7 days for undelivered
4.5 Deletion propagation
    - Client deletion generates DELETE events
    - “Force Sync Now” flushes DELETE first
    - Teacher device must apply DELETE automatically (no confirm)
4.6 Retention enforcement for sync
    - Auto-expire events >365 days
    - Ensure tombstones remain effective within retention window to prevent resurrection
4.7 Optional: WebRTC P2P optimization
    - Implement signaling (presence + ICE exchange)
    - Try P2P DataChannel first; fallback to offline queue
    - TURN (coturn) as fallback for NAT traversal (no persistent logs)

========================================
PHASE 5 - Client UX + Local DB integration
========================================
5.1 Local DB layout
    - Read-only course.sqlite imported from bundle
    - Writable local user DB: conversations/messages/progress + applied tombstones
5.2 Teacher UX
    - Enrollment inbox (approve/reject per course)
    - Course publish/unpublish + upload new bundle
    - Sync runs in background; received data auto-imports into teacher DB
5.3 Student UX
    - Marketplace browse/search, course detail
    - Enrollment request + status
    - Download after approval (bundle -> import course.sqlite)
    - Force Sync Now button
5.4 No export feature (explicitly omit)

========================================
PHASE 6 - Hardening (minimal ops, single node)
========================================
6.1 Pagination + rate limits everywhere (catalog/events/requests)
6.2 Monitoring + audit-lite
    - system health metrics
    - admin actions audit (who hid listing/suspended account)
6.3 Security improvements
    - tighten password reset flow (rate limit + lockouts)
    - optional 2FA as later enhancement
6.4 Load tests
    - catalog browse/search
    - signed URL issuance
    - event pull/ack correctness under concurrency

========================================
DELIVERABLES (MVP acceptance)
========================================
D1 Teacher can publish course listing and upload bundle to OSS
D2 Student can browse marketplace and request enrollment per course
D3 Teacher can approve; only approved students can download bundle via signed URL
D4 E2EE sync works across devices for messages + progress (store-and-forward)
D5 User can delete part of content; deletion is irreversible and propagates to teacher device
D6 Retention enforced: events 365d, offline queue 7d, backups daily rolling 30d
D7 All external traffic over HTTPS 443; minimal logs; no export